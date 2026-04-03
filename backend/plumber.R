library(plumber)
library(jsonlite)
library(readxl)
library(sf)
library(ggplot2)
library(osrm)

options(warn = -1)

APP_DIR <- getwd()
RESULTS_ROOT <- file.path(APP_DIR, "results")
DATA_DIRS <- c("IECA", "INE", "results")
OSRM_URL <- Sys.getenv("OSRM_URL", unset = "http://andalucia-osrm:5001/")

ensure_dirs <- function() {
  for (d in DATA_DIRS) {
    dir.create(file.path(APP_DIR, d), recursive = TRUE, showWarnings = FALSE)
  }
}

ensure_data <- function() {
  ensure_dirs()
  required <- c(
    file.path(APP_DIR, "INE", "30824.xlsx"),
    file.path(APP_DIR, "IECA", "13_01_TerminoMunicipal.shp"),
    file.path(APP_DIR, "IECA", "13_27_SeccionCensal.shp"),
    file.path(APP_DIR, "IECA", "07_06_ZonaVerde.shp"),
    file.path(APP_DIR, "IECA", "12_01_CentroSalud.shp"),
    file.path(APP_DIR, "IECA", "12_02_Hospital_CAE.shp"),
    file.path(APP_DIR, "IECA", "iepabra2021.shp")
  )
  if (!all(file.exists(required))) {
    source(file.path(APP_DIR, "datadl.R"), local = .GlobalEnv)
  }
}

normalize_text <- function(x) {
  out <- iconv(x, from = "UTF-8", to = "ASCII//TRANSLIT")
  out <- tolower(trimws(out))
  out
}

resolve_city_code <- function(city_code = NULL, city_name = NULL, income_file) {
  if (!is.null(city_code) && nzchar(city_code)) {
    if (nchar(city_code) != 5) stop("city_code debe tener longitud 5")
    return(city_code)
  }
  if (is.null(city_name) || !nzchar(city_name)) stop("Debes indicar city_code o city_name")

  alldata <- read_excel(path = income_file, range = "A8:A55442", .name_repair = "unique_quiet")[[1]]
  alldata <- alldata[grep("^[0-9]{5} ", alldata)]
  alldata.norm <- normalize_text(alldata)
  alldata.pretty <- substr(alldata, 7, nchar(alldata))
  pretty.norm <- normalize_text(alldata.pretty)
  query <- normalize_text(city_name)

  exact_idx <- which(pretty.norm == query)
  if (length(exact_idx) == 1) return(substr(alldata[exact_idx], 1, 5))

  partial_idx <- grep(query, pretty.norm, ignore.case = TRUE)
  if (length(partial_idx) == 1) return(substr(alldata[partial_idx], 1, 5))
  if (length(partial_idx) > 1) {
    candidates <- unique(alldata.pretty[partial_idx])
    stop(paste0(
      "El nombre del municipio es ambiguo. Coincidencias: ",
      paste(head(candidates, 10), collapse = ", ")
    ))
  }
  stop(paste0("No se encontró ningún municipio para: ", city_name))
}

url_check <- function(endpoint) {
  check <- try({ curlGetHeaders(endpoint) }, silent = TRUE)
  !inherits(check, "try-error")
}

databias_local <- function(x, y) {
  all_median <- as.numeric(apply(x, 2, median))
  all_data <- data.frame(t(sapply(seq_along(all_median), function(j) {
    jmedian <- all_median[j]
    w.lt <- as.numeric(which(x[, j] < jmedian))
    w.gt <- as.numeric(which(x[, j] >= jmedian))
    ymean.lt <- mean(y[w.lt])
    ymean.gt <- mean(y[w.gt])
    c(ymean.lt, ymean.gt)
  })))
  nums <- abs(all_data[, 1] - all_data[, 2])
  variations <- (apply(all_data, 1, max) - apply(all_data, 1, min)) / apply(all_data, 1, min) * 100
  variations <- round(variations, 2)
  all_data <- cbind(all_data, nums, variations, all_median)
  colnames(all_data) <- c("lower", "greater", "u", "variation", "median")
  rownames(all_data) <- colnames(x)
  all_data
}

bias_labels <- c(
  "Renta",
  "Desempleo",
  "Edad",
  "Educación",
  "Densidad",
  "Hogares",
  "Población extranjera"
)

build_analysis_context <- function(city_code = NULL, city_name = NULL, locations = "parks", dist_type = "mean") {
  oldwd <- getwd()
  on.exit(setwd(oldwd), add = TRUE)
  setwd(APP_DIR)

  ensure_data()

  env <- new.env(parent = globalenv())
  env$CENSUS_FILE <- "INE/Censo_2021_Andalucia.xlsx"
  env$INCOME_FILE <- "INE/30824.xlsx"
  env$IECA_SHP_FILE <- "IECA/iepabra2021.shp"
  env$OSRM_URL <- OSRM_URL
  env$TRACT_FIX <- NULL
  env$TRACT_EXCLUDE <- NULL

  env$CITY_CODE <- resolve_city_code(city_code, city_name, env$INCOME_FILE)
  env$LOCATIONS <- match.arg(locations, c("parks", "clinics_public", "clinics_any"))
  env$DIST_TYPE <- match.arg(dist_type, c("mean", "min", "max"))
  env$DIST_NAME <- c(mean = "Average", min = "Min", max = "Max")[[env$DIST_TYPE]]
  env$sourced <- FALSE

  if (!url_check(env$OSRM_URL)) {
    stop(paste0("No hay una instancia OSRM disponible en ", env$OSRM_URL))
  }

  source(file.path(APP_DIR, "numdata.R"), local = env)
  source(file.path(APP_DIR, "spdata.R"), local = env)

  env$HEADERS <- list(
    orig = c(
      "Sección",
      "Personas",
      "Porcentaje de personas de más de 64 años",
      "Porcentaje de población extranjera",
      "Porcentaje de población parada sobre población activa"
    ),
    repl = c("ct_code", "total", "elderly", "foreigner", "unemployed")
  )

  env$VARS <- list(
    orig = c("total", "mean_income", "underage", "elderly", "unemployed", "foreigner", "lonely"),
    repl = c("x1", "x2", "x3", "x4", "x5", "x6", "x7")
  )

  env$ieca.get_data <- function(ct_code, shpfile) {
    ieca_data <- st_read(shpfile, quiet = TRUE)
    ieca_data <- st_drop_geometry(
      subset(ieca_data, subset = (CUMUN == env$CITY_CODE), select = c(CUSEC, I6, I16))
    )
    colnames(ieca_data) <- c("ct_code", "lonely", "underage")
    ieca_data
  }

  env$ct.get_x <- function() {
    income_data <- env$ct.get_income(env$CITY_CODE, env$INCOME_FILE)
    census_data <- env$ct.get_census_info(env$CITY_CODE, env$HEADERS, env$CENSUS_FILE)
    ieca_data <- env$ieca.get_data(env$CITY_CODE, env$IECA_SHP_FILE)
    all_data1 <- merge(x = income_data, y = census_data, by = "ct_code")
    all_data2 <- merge(x = all_data1, y = ieca_data, by = "ct_code")
    ct_codes <- all_data2$ct_code
    all_data2 <- all_data2[, env$VARS[["orig"]]]
    colnames(all_data2) <- env$VARS[["repl"]]
    rownames(all_data2) <- ct_codes
    all_data2
  }

  x <- env$ct.get_x()
  y <- env$sp.dists$y
  centroids <- env$sp.dists$centroids
  xy <- merge(x, y, by = "row.names")
  rownames(xy) <- xy$Row.names
  xy <- subset(xy, select = -Row.names)
  raw <- st_as_sf(merge(xy, env$sp.tractdata, by = "row.names"))
  raw.rownames <- raw$Row.names
  raw <- subset(raw, select = c(env$VARS[["repl"]], "y"))
  rownames(raw) <- raw.rownames

  x <- cbind(1, st_drop_geometry(raw[, 1:7]))
  xnorm <- cbind(1, scale(st_drop_geometry(raw[, 1:7])))
  colnames(x)[1] <- colnames(xnorm)[1] <- "Intercept"

  y <- matrix(st_drop_geometry(raw[, 8])$y)
  rownames(y) <- raw.rownames

  centroids <- st_as_sf(merge(xy, centroids, by = "row.names"))
  centroids <- st_coordinates(centroids)
  rownames(centroids) <- raw.rownames

  citydata <- list()
  citydata[["x"]] <- x
  citydata[["y"]] <- y
  citydata[["centroids"]] <- centroids
  citydata[["centroids_orig"]] <- NULL
  citydata[["xnorm"]] <- xnorm
  citydata[["raw"]] <- raw
  citydata[["geometry"]] <- st_geometry(raw)
  citydata[["d"]] <- as.matrix(dist(centroids))
  citydata[["gz"]] <- env$sp.gzdata
  citydata[["clinics_any"]] <- env$sp.clinic_any
  citydata[["clinics_public"]] <- env$sp.clinic_public
  citydata[["name"]] <- env$sp.citydata$nombre
  citydata[["varname"]] <- iconv(gsub(" ", "", tolower(env$sp.citydata$nombre)), to = "ASCII//TRANSLIT")

  list(
    env = env,
    citydata = citydata
  )
}

safe_results_path <- function(relative_path) {
  if (is.null(relative_path) || !nzchar(relative_path)) {
    stop("relative_path es obligatorio")
  }

  root <- normalizePath(RESULTS_ROOT, winslash = "/", mustWork = TRUE)
  candidate <- normalizePath(file.path(RESULTS_ROOT, relative_path), winslash = "/", mustWork = FALSE)

  if (!(startsWith(candidate, paste0(root, "/")) || identical(candidate, root))) {
    stop("Ruta inválida")
  }

  if (!file.exists(candidate)) {
    stop(paste0("No existe el archivo: ", relative_path))
  }

  candidate
}

drop_geom_if_needed <- function(x) {
  tryCatch(
    {
      if (inherits(x, "sf")) st_drop_geometry(x) else x
    },
    error = function(e) x
  )
}

to_df <- function(x, default_name = "value") {
  if (is.null(x)) return(NULL)

  x <- drop_geom_if_needed(x)

  if (is.data.frame(x)) {
    return(x)
  }

  if (is.matrix(x)) {
    df <- as.data.frame(x, stringsAsFactors = FALSE)
    if (ncol(df) == 1 && (is.null(colnames(df)) || colnames(df)[1] == "")) {
      colnames(df) <- default_name
    }
    return(df)
  }

  if (is.vector(x) || is.factor(x)) {
    df <- data.frame(x, stringsAsFactors = FALSE)
    colnames(df) <- default_name
    return(df)
  }

  NULL
}

clean_preview_value <- function(v) {
  if (length(v) == 0 || is.null(v) || (length(v) == 1 && is.na(v))) return(NULL)
  if (is.numeric(v)) return(round(as.numeric(v), 4))
  if (inherits(v, "POSIXt")) return(as.character(v))
  if (is.factor(v)) return(as.character(v))
  as.character(v)
}

table_preview <- function(df, n = 10) {
  if (is.null(df) || !is.data.frame(df)) return(list())

  rows <- head(df, n)
  out <- vector("list", nrow(rows))

  for (i in seq_len(nrow(rows))) {
    row_list <- list()
    for (col in names(rows)) {
      row_list[[col]] <- clean_preview_value(rows[[col]][i])
    }
    out[[i]] <- row_list
  }

  out
}

numeric_distribution <- function(values, bins = 12) {
  vals <- suppressWarnings(as.numeric(values))
  vals <- vals[is.finite(vals)]

  if (length(vals) == 0) {
    return(NULL)
  }

  if (length(unique(vals)) == 1) {
    return(list(
      min = vals[1],
      max = vals[1],
      mean = vals[1],
      median = vals[1],
      breaks = c(vals[1], vals[1]),
      counts = c(length(vals))
    ))
  }

  h <- hist(vals, breaks = bins, plot = FALSE)

  list(
    min = min(vals),
    max = max(vals),
    mean = mean(vals),
    median = median(vals),
    breaks = as.numeric(h$breaks),
    counts = as.integer(h$counts)
  )
}

summarise_column <- function(x, name) {
  non_na <- sum(!is.na(x))
  out <- list(
    name = name,
    type = class(x)[1],
    missing = sum(is.na(x)),
    non_missing = non_na,
    unique = length(unique(x[!is.na(x)]))
  )

  if (is.numeric(x) || is.integer(x)) {
    vals <- as.numeric(x)
    vals <- vals[is.finite(vals)]

    if (length(vals) > 0) {
      out$min <- min(vals)
      out$max <- max(vals)
      out$mean <- mean(vals)
      out$median <- median(vals)
      out$sd <- if (length(vals) > 1) sd(vals) else 0
    } else {
      out$min <- NULL
      out$max <- NULL
      out$mean <- NULL
      out$median <- NULL
      out$sd <- NULL
    }
  } else {
    vals <- as.character(x[!is.na(x)])
    out$sample_values <- unique(head(vals, 5))
  }

  out
}

inspect_rds <- function(relative_path) {
  path <- safe_results_path(relative_path)
  obj <- readRDS(path)

  tables <- list()

  if (is.list(obj)) {
    tables$raw <- to_df(obj$raw, "raw")
    tables$x <- to_df(obj$x, "x")
    tables$xnorm <- to_df(obj$xnorm, "xnorm")
    tables$y <- to_df(obj$y, "y")
    tables$centroids <- to_df(obj$centroids, "centroid")
  } else {
    tables$raw <- to_df(obj, "value")
  }

  tables <- tables[!vapply(tables, is.null, logical(1))]

  if (length(tables) == 0) {
    stop("El .rds no contiene tablas inspeccionables")
  }

  preferred_table_name <- if ("raw" %in% names(tables)) "raw" else names(tables)[1]
  preferred_table <- tables[[preferred_table_name]]

  table_dimensions <- lapply(tables, function(df) {
    list(rows = nrow(df), cols = ncol(df))
  })

  table_previews <- lapply(tables, table_preview, n = 10)

  variables <- lapply(names(preferred_table), function(col) {
    summarise_column(preferred_table[[col]], col)
  })

  numeric_cols <- names(preferred_table)[vapply(preferred_table, is.numeric, logical(1))]
  distributions <- lapply(numeric_cols, function(col) {
    dist <- numeric_distribution(preferred_table[[col]], bins = 12)
    list(
      variable = col,
      table = preferred_table_name,
      distribution = dist
    )
  })
  names(distributions) <- numeric_cols

  list(
    file = basename(path),
    municipality = if (!is.null(obj$name)) as.character(obj$name)[1] else NULL,
    available_tables = names(tables),
    preferred_table = preferred_table_name,
    table_dimensions = table_dimensions,
    table_previews = table_previews,
    variables = variables,
    distributions = distributions
  )
}

build_bias_table <- function(city_code = NULL, city_name = NULL) {
  ctx <- build_analysis_context(
    city_code = city_code,
    city_name = city_name,
    locations = "parks",
    dist_type = "mean"
  )

  citydata <- ctx$citydata

  bias <- databias_local(citydata$x, citydata$y)[-1, , drop = FALSE]
  rownames(bias) <- paste0("x", seq_len(nrow(bias)))
  suggested_idx <- which.max(bias$variation)

  rows <- lapply(seq_len(nrow(bias)), function(i) {
    key <- rownames(bias)[i]
    key_num <- as.integer(sub("x", "", key))
    label <- if (key_num >= 1 && key_num <= length(bias_labels)) bias_labels[[key_num]] else key

    list(
      key = key,
      label = label,
      lower = as.numeric(bias[i, "lower"]),
      greater = as.numeric(bias[i, "greater"]),
      u = as.numeric(bias[i, "u"]),
      variation = as.numeric(bias[i, "variation"]),
      median = as.numeric(bias[i, "median"])
    )
  })

  list(
    suggested = suggested_idx,
    rows = rows
  )
}

run_pipeline <- function(city_code = NULL, city_name = NULL, locations = "parks", dist_type = "mean", biasvar = NULL) {
  ctx <- build_analysis_context(
    city_code = city_code,
    city_name = city_name,
    locations = locations,
    dist_type = dist_type
  )

  env <- ctx$env
  citydata <- ctx$citydata

  bias <- databias_local(citydata$x, citydata$y)[-1, ]
  rownames(bias) <- paste0("x", seq_len(nrow(bias)))
  suggested_idx <- which.max(bias$variation)
  selected_bias <- if (is.null(biasvar) || !nzchar(biasvar)) rownames(bias)[suggested_idx] else biasvar
  if (!(selected_bias %in% rownames(bias))) stop("biasvar debe ser uno de x1..x7")
  bias_idx <- as.integer(sub("x", "", selected_bias))

  locations_short <- list(parks = "ugs", clinics_public = "hcf_public", clinics_any = "hcf")
  job_id <- paste0(env$CITY_CODE, "-", env$LOCATIONS, "-", format(Sys.time(), "%Y%m%d%H%M%S"))
  dir.create(RESULTS_ROOT, recursive = TRUE, showWarnings = FALSE)

  filenames <- list(
    rds = file.path(RESULTS_ROOT, paste0(env$CITY_CODE, "-", locations_short[[env$LOCATIONS]], ".rds")),
    gz = file.path(RESULTS_ROOT, paste0(env$CITY_CODE, "_greenzones.png")),
    clinic_any = file.path(RESULTS_ROOT, paste0(env$CITY_CODE, "_clinics_any.png")),
    clinic_public = file.path(RESULTS_ROOT, paste0(env$CITY_CODE, "_clinics_public.png")),
    y = file.path(RESULTS_ROOT, paste0(env$CITY_CODE, "-", locations_short[[env$LOCATIONS]], "_y.png")),
    svar = file.path(RESULTS_ROOT, paste0(env$CITY_CODE, "_", selected_bias, ".png"))
  )

  saveRDS(citydata, file = filenames$rds)

  fplot.gz <- ggplot() +
    geom_sf(data = citydata$geometry, fill = NA) +
    geom_sf(data = citydata$gz, fill = "green2") +
    ggtitle(paste0("Green zones map for ", citydata[["name"]], " (code ", env$CITY_CODE, ")")) +
    theme_void()
  suppressMessages(ggsave(filenames$gz, plot = fplot.gz))

  fplot.clinic_any <- ggplot() +
    geom_sf(data = citydata$geometry, fill = NA) +
    geom_sf(data = citydata$clinics_any, color = "orange") +
    ggtitle(paste0("All clinics map for ", citydata[["name"]], " (code ", env$CITY_CODE, ")")) +
    theme_void()
  suppressMessages(ggsave(filenames$clinic_any, plot = fplot.clinic_any))

  fplot.clinic_public <- ggplot() +
    geom_sf(data = citydata$geometry, fill = NA) +
    geom_sf(data = citydata$clinics_public, color = "red") +
    ggtitle(paste0("Public clinics map for ", citydata[["name"]], " (code ", env$CITY_CODE, ")")) +
    theme_void()
  suppressMessages(ggsave(filenames$clinic_public, plot = fplot.clinic_public))

  fplot.y <- ggplot() +
    geom_sf(data = citydata$geometry, aes(fill = citydata$y)) +
    scale_fill_steps(name = paste(env$DIST_NAME, "distance\n(meters)"), n.breaks = 8, low = "white", high = "red") +
    ggtitle(paste0("Y values for ", citydata[["name"]], " (code ", env$CITY_CODE, ")")) +
    theme_void()
  suppressMessages(ggsave(filenames$y, plot = fplot.y))

  fplot.svar <- ggplot() +
    geom_sf(data = citydata$geometry, aes(fill = citydata$x[, bias_idx + 1])) +
    scale_fill_steps(name = "", n.breaks = 8, low = "white", high = "red") +
    ggtitle(paste0(selected_bias, " values for ", citydata[["name"]], " (code ", env$CITY_CODE, ")")) +
    theme_void()
  suppressMessages(ggsave(filenames$svar, plot = fplot.svar))

  files_out <- lapply(unname(unlist(filenames)), function(path) {
    list(name = basename(path), path = path)
  })

  list(
    job_id = job_id,
    city_code = env$CITY_CODE,
    city_name = as.character(citydata[["name"]])[1],
    locations = env$LOCATIONS,
    dist_type = env$DIST_TYPE,
    biasvar = selected_bias,
    bias_summary = bias,
    files = files_out
  )
}

#* @get /health
function() {
  list(status = "ok", osrm_url = OSRM_URL, osrm_reachable = url_check(OSRM_URL))
}

#* @get /bias-table/<city_code>
#* @serializer unboxedJSON
function(city_code, res) {
  out <- tryCatch(
    build_bias_table(city_code = city_code),
    error = function(e) {
      res$status <- 400
      list(error = TRUE, message = conditionMessage(e))
    }
  )
  out
}

#* @post /inspect-rds
#* @serializer unboxedJSON
function(req, res) {
  payload <- jsonlite::fromJSON(req$postBody, simplifyVector = TRUE)

  out <- tryCatch(
    inspect_rds(
      relative_path = if (!is.null(payload$relative_path)) payload$relative_path else NULL
    ),
    error = function(e) {
      res$status <- 400
      list(error = TRUE, message = conditionMessage(e))
    }
  )

  out
}

#* @post /run
#* @serializer unboxedJSON
function(req, res) {
  payload <- jsonlite::fromJSON(req$postBody, simplifyVector = TRUE)
  out <- tryCatch(
    run_pipeline(
      city_code = if (!is.null(payload$city_code)) payload$city_code else NULL,
      city_name = if (!is.null(payload$city_name)) payload$city_name else NULL,
      locations = if (!is.null(payload$locations)) payload$locations else "parks",
      dist_type = if (!is.null(payload$dist_type)) payload$dist_type else "mean",
      biasvar = if (!is.null(payload$biasvar)) payload$biasvar else NULL
    ),
    error = function(e) {
      res$status <- 400
      list(error = TRUE, message = conditionMessage(e))
    }
  )
  out
}