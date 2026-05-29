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
CONTEXT_CACHE_VERSION <- 2L

ensure_dirs <- function() {
  for (d in DATA_DIRS) {
    dir.create(file.path(APP_DIR, d), recursive = TRUE, showWarnings = FALSE)
  }
}

ensure_data <- function() {
  ensure_dirs()

  required_ieca <- c(
    file.path(APP_DIR, "IECA", "13_01_TerminoMunicipal.shp"),
    file.path(APP_DIR, "IECA", "13_01_TerminoMunicipal.dbf"),
    file.path(APP_DIR, "IECA", "13_27_SeccionCensal.shp"),
    file.path(APP_DIR, "IECA", "07_06_ZonaVerde.shp"),
    file.path(APP_DIR, "IECA", "12_01_CentroSalud.shp"),
    file.path(APP_DIR, "IECA", "12_02_Hospital_CAE.shp"),
    file.path(APP_DIR, "IECA", "iepabra2021.shp")
  )

  if (!all(file.exists(required_ieca))) {
    Sys.setenv(DOWNLOAD_IECA = "true")
    source(file.path(APP_DIR, "datadl.R"), local = .GlobalEnv)
  }

  required_ine <- c(
    file.path(APP_DIR, "INE", "30824.xlsx"),
    file.path(APP_DIR, "INE", "Censo_2021_Andalucia.xlsx")
  )

  if (!all(file.exists(required_ine))) {
    missing <- required_ine[!file.exists(required_ine)]
    stop(
      paste0(
        "Missing INE input files: ", paste(missing, collapse = ", "),
        ". Add them to backend/INE before running the pipeline, ",
        "or adapt numdata.R/plumber.R to read your CSV files."
      )
    )
  }
}

normalize_text <- function(x) {
  out <- iconv(x, from = "UTF-8", to = "ASCII//TRANSLIT")
  out <- tolower(trimws(out))
  out
}

resolve_city_code <- function(city_code = NULL, city_name = NULL, income_file) {
  if (!is.null(city_code) && nzchar(city_code)) {
    if (nchar(city_code) != 5) {
      stop("city_code must have length 5")
    }

    return(city_code)
  }

  if (is.null(city_name) || !nzchar(city_name)) {
    stop("You must provide either city_code or city_name")
  }

  alldata <- read_excel(
    path = income_file,
    range = "A8:A55442",
    .name_repair = "unique_quiet"
  )[[1]]

  alldata <- alldata[grep("^[0-9]{5} ", alldata)]
  alldata.pretty <- substr(alldata, 7, nchar(alldata))
  pretty.norm <- normalize_text(alldata.pretty)
  query <- normalize_text(city_name)

  exact_idx <- which(pretty.norm == query)

  if (length(exact_idx) == 1) {
    return(substr(alldata[exact_idx], 1, 5))
  }

  partial_idx <- grep(query, pretty.norm, ignore.case = TRUE)

  if (length(partial_idx) == 1) {
    return(substr(alldata[partial_idx], 1, 5))
  }

  if (length(partial_idx) > 1) {
    candidates <- unique(alldata.pretty[partial_idx])

    stop(
      paste0(
        "The municipality name is ambiguous. Matches: ",
        paste(head(candidates, 10), collapse = ", ")
      )
    )
  }

  stop(paste0("No municipality was found for: ", city_name))
}

url_check <- function(endpoint) {
  check <- try({ curlGetHeaders(endpoint) }, silent = TRUE)
  !inherits(check, "try-error")
}

databias_local <- function(x, y) {
  all_median <- as.numeric(apply(x, 2, median))

  all_data <- data.frame(
    t(
      sapply(seq_along(all_median), function(j) {
        jmedian <- all_median[j]
        w.lt <- as.numeric(which(x[, j] < jmedian))
        w.gt <- as.numeric(which(x[, j] >= jmedian))
        ymean.lt <- mean(y[w.lt])
        ymean.gt <- mean(y[w.gt])
        c(ymean.lt, ymean.gt)
      })
    )
  )

  nums <- abs(all_data[, 1] - all_data[, 2])

  variations <- (
    apply(all_data, 1, max) -
      apply(all_data, 1, min)
  ) / apply(all_data, 1, min) * 100

  variations <- round(variations, 2)

  all_data <- cbind(all_data, nums, variations, all_median)
  colnames(all_data) <- c("lower", "greater", "u", "variation", "median")
  rownames(all_data) <- colnames(x)

  all_data
}

bias_labels <- c(
  "Population",
  "Income",
  "Prop. of children",
  "Prop. of elderly population",
  "Unemployment rate",
  "Prop. of foreign population",
  "Loneliness index"
)

select_suggested_bias <- function(bias) {
  eligible <- rep(FALSE, nrow(bias))

  for (i in seq_len(nrow(bias))) {
    key <- rownames(bias)[i]
    var_num <- as.integer(sub("x", "", key))
    above_median <- as.numeric(bias[i, "greater"])
    below_median <- as.numeric(bias[i, "lower"])

    if (var_num == 2) {
      eligible[i] <- above_median < below_median
    } else {
      eligible[i] <- above_median > below_median
    }
  }

  if (!any(eligible)) {
    return(0L)
  }

  eligible_idx <- which(eligible)
  as.integer(eligible_idx[which.max(bias[eligible_idx, "variation"])])
}


no_facilities_error <- function(city_code, locations) {
  labels <- c(
    parks = "urban green areas",
    clinics_public = "public healthcare facilities",
    clinics_any = "public or private healthcare facilities"
  )

  label <- labels[[locations]]
  if (is.null(label)) label <- locations

  structure(
    list(
      message = paste0(
        "No destinations are available for this municipality and accessibility option: ",
        label,
        ". Choose another accessibility option or municipality."
      ),
      city_code = city_code,
      locations = locations,
      call = NULL
    ),
    class = c("no_facilities", "error", "condition")
  )
}

count_available_locations <- function(city_code, locations) {
  locations <- match.arg(locations, c("parks", "clinics_public", "clinics_any"))

  if (locations == "parks") {
    citydata <- st_read(file.path(APP_DIR, "IECA", "13_01_TerminoMunicipal.shp"), quiet = TRUE)
    citydata <- subset(citydata, subset = cod_mun == city_code)

    gzdata <- st_read(file.path(APP_DIR, "IECA", "07_06_ZonaVerde.shp"), quiet = TRUE)
    gzdata <- subset(gzdata, subset = tipo == "Parque")

    if (nrow(citydata) == 0 || nrow(gzdata) == 0) {
      return(0L)
    }

    return(length(st_contains(citydata, gzdata)[[1]]))
  }

  clinic_data <- subset(
    st_read(file.path(APP_DIR, "IECA", "12_01_CentroSalud.shp"), quiet = TRUE),
    subset = cod_mun == city_code,
    select = cod_mun
  )
  clinic_data$sistema_sa <- "Público"

  hospital_data <- subset(
    st_read(file.path(APP_DIR, "IECA", "12_02_Hospital_CAE.shp"), quiet = TRUE),
    subset = cod_mun == city_code,
    select = c(cod_mun, sistema_sa)
  )

  clinic_any <- rbind(clinic_data, hospital_data)

  if (locations == "clinics_public") {
    clinic_any <- subset(clinic_any, subset = sistema_sa == "Público")
  }

  nrow(clinic_any)
}

assert_locations_available <- function(city_code, locations) {
  n <- count_available_locations(city_code, locations)

  if (is.null(n) || is.na(n) || n < 1) {
    stop(no_facilities_error(city_code, locations))
  }

  invisible(n)
}

is_no_facilities_error <- function(e) {
  inherits(e, "no_facilities") || grepl('dst.*at least 1 row|should have at least 1 row|No destinations are available', conditionMessage(e))
}

no_facilities_response <- function(city_code, locations, dist_type, e) {
  list(
    available = FALSE,
    cache_id = NULL,
    locations = locations,
    dist_type = dist_type,
    rows = list(),
    message = conditionMessage(e)
  )
}

build_analysis_context <- function(
  city_code = NULL,
  city_name = NULL,
  locations = "parks",
  dist_type = "mean"
) {
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

  assert_locations_available(env$CITY_CODE, env$LOCATIONS)

  if (!url_check(env$OSRM_URL)) {
    stop(paste0("No OSRM instance is available at ", env$OSRM_URL))
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
    repl = c(
      "ct_code",
      "total",
      "elderly",
      "foreigner",
      "unemployed"
    )
  )

  env$VARS <- list(
    orig = c(
      "total",
      "mean_income",
      "underage",
      "elderly",
      "unemployed",
      "foreigner",
      "lonely"
    ),
    repl = c(
      "x1",
      "x2",
      "x3",
      "x4",
      "x5",
      "x6",
      "x7"
    )
  )

  env$ieca.get_data <- function(ct_code, shpfile) {
    ieca_data <- st_read(shpfile, quiet = TRUE)

    ieca_data <- st_drop_geometry(
      subset(
        ieca_data,
        subset = (CUMUN == env$CITY_CODE),
        select = c(CUSEC, I6, I16)
      )
    )

    colnames(ieca_data) <- c("ct_code", "lonely", "underage")

    ieca_data
  }

  env$ct.get_x <- function() {
    income_data <- env$ct.get_income(env$CITY_CODE, env$INCOME_FILE)
    census_data <- env$ct.get_census_info(env$CITY_CODE, env$HEADERS, env$CENSUS_FILE)
    ieca_data <- env$ieca.get_data(env$CITY_CODE, env$IECA_SHP_FILE)

    all_data1 <- merge(
      x = income_data,
      y = census_data,
      by = "ct_code"
    )

    all_data2 <- merge(
      x = all_data1,
      y = ieca_data,
      by = "ct_code"
    )

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
  citydata[["municipality"]] <- env$sp.citydata
  citydata[["name"]] <- env$sp.citydata$nombre
  citydata[["varname"]] <- iconv(
    gsub(" ", "", tolower(env$sp.citydata$nombre)),
    to = "ASCII//TRANSLIT"
  )

  list(
    env = env,
    citydata = citydata
  )
}

safe_results_path <- function(relative_path) {
  if (is.null(relative_path) || !nzchar(relative_path)) {
    stop("relative_path is required")
  }

  root <- normalizePath(RESULTS_ROOT, winslash = "/", mustWork = TRUE)
  candidate <- normalizePath(
    file.path(RESULTS_ROOT, relative_path),
    winslash = "/",
    mustWork = FALSE
  )

  if (!(startsWith(candidate, paste0(root, "/")) || identical(candidate, root))) {
    stop("Invalid path")
  }

  if (!file.exists(candidate)) {
    stop(paste0("File does not exist: ", relative_path))
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
  if (length(v) == 0 || is.null(v) || (length(v) == 1 && is.na(v))) {
    return(NULL)
  }

  if (is.numeric(v)) return(round(as.numeric(v), 4))
  if (inherits(v, "POSIXt")) return(as.character(v))
  if (is.factor(v)) return(as.character(v))

  as.character(v)
}

table_preview <- function(df, n = 10) {
  if (is.null(df) || !is.data.frame(df)) {
    return(list())
  }

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
    return(
      list(
        min = vals[1],
        max = vals[1],
        mean = vals[1],
        median = vals[1],
        breaks = c(vals[1], vals[1]),
        counts = c(length(vals))
      )
    )
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
    stop("The .rds file does not contain inspectable tables")
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

context_cache_dir <- function() {
  path <- file.path(RESULTS_ROOT, ".context_cache")
  dir.create(path, recursive = TRUE, showWarnings = FALSE)
  path
}

sanitize_cache_part <- function(x) {
  x <- if (is.null(x) || !nzchar(as.character(x))) "unknown" else as.character(x)
  gsub("[^A-Za-z0-9_-]", "_", x)
}

context_cache_id <- function(city_code, locations, dist_type) {
  paste(
    sanitize_cache_part(city_code),
    sanitize_cache_part(locations),
    sanitize_cache_part(dist_type),
    sep = "__"
  )
}

context_cache_path <- function(cache_id) {
  file.path(context_cache_dir(), paste0(sanitize_cache_part(cache_id), ".rds"))
}

minimal_env <- function(city_code, locations, dist_type) {
  env <- new.env(parent = globalenv())
  env$CITY_CODE <- city_code
  env$LOCATIONS <- match.arg(locations, c("parks", "clinics_public", "clinics_any"))
  env$DIST_TYPE <- match.arg(dist_type, c("mean", "min", "max"))
  env$DIST_NAME <- c(mean = "Average", min = "Min", max = "Max")[[env$DIST_TYPE]]
  env
}

read_cached_context <- function(cache_id) {
  if (is.null(cache_id) || !nzchar(as.character(cache_id))) {
    return(NULL)
  }

  path <- context_cache_path(cache_id)

  if (!file.exists(path)) {
    return(NULL)
  }

  cached <- readRDS(path)

  if (is.null(cached$citydata) || is.null(cached$config)) {
    return(NULL)
  }

  if (is.null(cached$cache_version) || !identical(as.integer(cached$cache_version), CONTEXT_CACHE_VERSION)) {
    return(NULL)
  }

  list(
    env = minimal_env(
      cached$config$city_code,
      cached$config$locations,
      cached$config$dist_type
    ),
    citydata = cached$citydata,
    cache_id = cache_id
  )
}

write_cached_context <- function(cache_id, ctx) {
  saveRDS(
    list(
      config = list(
        city_code = ctx$env$CITY_CODE,
        locations = ctx$env$LOCATIONS,
        dist_type = ctx$env$DIST_TYPE
      ),
      citydata = ctx$citydata,
      created_at = as.character(Sys.time()),
      cache_version = CONTEXT_CACHE_VERSION
    ),
    file = context_cache_path(cache_id)
  )
}

get_or_build_context <- function(
  city_code = NULL,
  city_name = NULL,
  locations = "parks",
  dist_type = "mean",
  cache_id = NULL
) {
  cached <- read_cached_context(cache_id)

  if (!is.null(cached)) {
    cached$cache_id <- cache_id
    return(cached)
  }

  ctx <- build_analysis_context(
    city_code = city_code,
    city_name = city_name,
    locations = locations,
    dist_type = dist_type
  )

  resolved_cache_id <- if (!is.null(cache_id) && nzchar(as.character(cache_id))) {
    cache_id
  } else {
    context_cache_id(ctx$env$CITY_CODE, ctx$env$LOCATIONS, ctx$env$DIST_TYPE)
  }

  write_cached_context(resolved_cache_id, ctx)
  ctx$cache_id <- resolved_cache_id
  ctx
}

build_bias_table <- function(city_code = NULL, city_name = NULL, locations = "parks", dist_type = "mean", cache_id = NULL) {
  ctx <- get_or_build_context(
    city_code = city_code,
    city_name = city_name,
    locations = locations,
    dist_type = dist_type,
    cache_id = cache_id
  )

  citydata <- ctx$citydata

  bias <- databias_local(citydata$x, citydata$y)[-1, , drop = FALSE]
  rownames(bias) <- paste0("x", seq_len(nrow(bias)))


  rows <- lapply(seq_len(nrow(bias)), function(i) {
    key <- rownames(bias)[i]
    key_num <- as.integer(sub("x", "", key))
    label <- if (key_num >= 1 && key_num <= length(bias_labels)) {
      bias_labels[[key_num]]
    } else {
      key
    }

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
    cache_id = ctx$cache_id,
    locations = ctx$env$LOCATIONS,
    dist_type = ctx$env$DIST_TYPE,
    rows = rows
  )
}


# -------------------------------------------------------------------
# Export helpers for open, non-R formats
# -------------------------------------------------------------------

add_rownames_column <- function(df, id_name = "ct_code") {
  if (is.null(df) || !is.data.frame(df)) return(df)

  rn <- rownames(df)
  has_meaningful_rownames <- !is.null(rn) && length(rn) == nrow(df) && !identical(rn, as.character(seq_len(nrow(df))))

  if (has_meaningful_rownames && !(id_name %in% names(df))) {
    df <- cbind(setNames(data.frame(rn, stringsAsFactors = FALSE), id_name), df)
  }

  rownames(df) <- NULL
  df
}

csv_ready_table <- function(x, id_name = "ct_code", default_name = "value") {
  df <- to_df(x, default_name = default_name)

  if (is.null(df)) return(NULL)

  add_rownames_column(df, id_name = id_name)
}

write_csv_if_possible <- function(x, path, id_name = "ct_code", default_name = "value") {
  df <- csv_ready_table(x, id_name = id_name, default_name = default_name)

  if (is.null(df)) {
    return(NULL)
  }

  utils::write.csv(df, path, row.names = FALSE, fileEncoding = "UTF-8")
  path
}

write_json_if_possible <- function(x, path) {
  jsonlite::write_json(x, path, auto_unbox = TRUE, pretty = TRUE, null = "null")
  path
}

as_wgs84_sf <- function(obj) {
  if (is.null(obj)) return(NULL)

  if (inherits(obj, "sfc")) {
    obj <- st_sf(geometry = obj)
  }

  if (!inherits(obj, "sf")) return(NULL)

  if (nrow(obj) < 1) return(NULL)

  if (is.na(st_crs(obj))) {
    return(obj)
  }

  tryCatch(
    st_transform(obj, 4326),
    error = function(e) obj
  )
}

write_geojson_if_possible <- function(obj, path) {
  sf_obj <- as_wgs84_sf(obj)

  if (is.null(sf_obj)) {
    return(NULL)
  }

  if (file.exists(path)) {
    unlink(path)
  }

  suppressWarnings(
    st_write(sf_obj, path, driver = "GeoJSON", quiet = TRUE)
  )

  path
}

centroids_to_sf <- function(centroids, crs_source = NULL) {
  if (is.null(centroids)) return(NULL)

  df <- as.data.frame(centroids, stringsAsFactors = FALSE)

  if (ncol(df) < 2) return(NULL)

  if (!all(c("X", "Y") %in% names(df))) {
    names(df)[1:2] <- c("X", "Y")
  }

  df <- add_rownames_column(df, id_name = "ct_code")

  crs_value <- NA
  if (!is.null(crs_source)) {
    crs_value <- tryCatch(st_crs(crs_source), error = function(e) NA)
  }

  st_as_sf(df, coords = c("X", "Y"), crs = crs_value, remove = FALSE)
}

bias_table_to_df <- function(bias) {
  df <- as.data.frame(bias, stringsAsFactors = FALSE)
  df <- add_rownames_column(df, id_name = "variable")

  if ("variable" %in% names(df)) {
    var_num <- suppressWarnings(as.integer(sub("x", "", df$variable)))
    df$label <- vapply(var_num, function(i) {
      if (!is.na(i) && i >= 1 && i <= length(bias_labels)) {
        bias_labels[[i]]
      } else {
        NA_character_
      }
    }, character(1))

    df <- df[, c("variable", "label", setdiff(names(df), c("variable", "label"))), drop = FALSE]
  }

  df
}

export_open_data_files <- function(citydata, bias, env, filenames, prefix, selected_bias = NULL) {
  out <- list()

  out$raw_csv <- write_csv_if_possible(citydata$raw, filenames$raw_csv, id_name = "ct_code", default_name = "raw")
  out$x_csv <- write_csv_if_possible(citydata$x, filenames$x_csv, id_name = "ct_code", default_name = "x")
  out$xnorm_csv <- write_csv_if_possible(citydata$xnorm, filenames$xnorm_csv, id_name = "ct_code", default_name = "xnorm")
  out$y_csv <- write_csv_if_possible(citydata$y, filenames$y_csv, id_name = "ct_code", default_name = "y")
  out$centroids_csv <- write_csv_if_possible(citydata$centroids, filenames$centroids_csv, id_name = "ct_code", default_name = "centroid")

  bias_df <- bias_table_to_df(bias)
  utils::write.csv(bias_df, filenames$bias_table_csv, row.names = FALSE, fileEncoding = "UTF-8")
  out$bias_table_csv <- filenames$bias_table_csv

  metadata <- list(
    city_code = env$CITY_CODE,
    city_name = as.character(citydata$name)[1],
    locations = env$LOCATIONS,
    dist_type = env$DIST_TYPE,
    distance_name = env$DIST_NAME,
    selected_bias = selected_bias,
    selected_bias_label = if (!is.null(selected_bias)) {
      idx <- suppressWarnings(as.integer(sub("x", "", selected_bias)))
      if (!is.na(idx) && idx >= 1 && idx <= length(bias_labels)) bias_labels[[idx]] else NULL
    } else {
      NULL
    },
    exported_tables = c("raw", "x", "xnorm", "y", "centroids", "bias_table"),
    exported_at = as.character(Sys.time())
  )

  out$metadata_json <- write_json_if_possible(metadata, filenames$metadata_json)

  out$raw_geojson <- write_geojson_if_possible(citydata$raw, filenames$raw_geojson)
  out$centroids_geojson <- write_geojson_if_possible(
    centroids_to_sf(citydata$centroids, crs_source = citydata$raw),
    filenames$centroids_geojson
  )
  out$municipality_geojson <- write_geojson_if_possible(citydata$municipality, filenames$municipality_geojson)
  out$greenzones_geojson <- write_geojson_if_possible(citydata$gz, filenames$greenzones_geojson)
  out$clinics_any_geojson <- write_geojson_if_possible(citydata$clinics_any, filenames$clinics_any_geojson)
  out$clinics_public_geojson <- write_geojson_if_possible(citydata$clinics_public, filenames$clinics_public_geojson)

  Filter(function(x) !is.null(x) && file.exists(x), out)
}

run_pipeline <- function(
  city_code = NULL,
  city_name = NULL,
  locations = "parks",
  dist_type = "mean",
  biasvar = NULL,
  cache_id = NULL
) {
  ctx <- get_or_build_context(
    city_code = city_code,
    city_name = city_name,
    locations = locations,
    dist_type = dist_type,
    cache_id = cache_id
  )

  env <- ctx$env
  citydata <- ctx$citydata

  bias <- databias_local(citydata$x, citydata$y)[-1, , drop = FALSE]
  rownames(bias) <- paste0("x", seq_len(nrow(bias)))

  if (is.null(biasvar) || !nzchar(as.character(biasvar))) {
    stop("biasvar is required and must be one of x1..x7")
  }

  selected_bias <- as.character(biasvar)

  if (!(selected_bias %in% rownames(bias))) {
    stop("biasvar must be one of x1..x7")
  }

  bias_idx <- as.integer(sub("x", "", selected_bias))

  locations_short <- list(
    parks = "ugs",
    clinics_public = "hcf_public",
    clinics_any = "hcf"
  )

  job_id <- paste0(
    env$CITY_CODE,
    "-",
    env$LOCATIONS,
    "-",
    format(Sys.time(), "%Y%m%d%H%M%S")
  )

  dir.create(RESULTS_ROOT, recursive = TRUE, showWarnings = FALSE)

  output_prefix <- paste0(env$CITY_CODE, "-", locations_short[[env$LOCATIONS]])

  filenames <- list(
    rds = file.path(
      RESULTS_ROOT,
      paste0(output_prefix, ".rds")
    ),
    raw_csv = file.path(
      RESULTS_ROOT,
      paste0(output_prefix, "-raw.csv")
    ),
    x_csv = file.path(
      RESULTS_ROOT,
      paste0(output_prefix, "-x.csv")
    ),
    xnorm_csv = file.path(
      RESULTS_ROOT,
      paste0(output_prefix, "-xnorm.csv")
    ),
    y_csv = file.path(
      RESULTS_ROOT,
      paste0(output_prefix, "-y.csv")
    ),
    centroids_csv = file.path(
      RESULTS_ROOT,
      paste0(output_prefix, "-centroids.csv")
    ),
    bias_table_csv = file.path(
      RESULTS_ROOT,
      paste0(output_prefix, "-bias_table.csv")
    ),
    metadata_json = file.path(
      RESULTS_ROOT,
      paste0(output_prefix, "-metadata.json")
    ),
    raw_geojson = file.path(
      RESULTS_ROOT,
      paste0(output_prefix, "-raw.geojson")
    ),
    centroids_geojson = file.path(
      RESULTS_ROOT,
      paste0(output_prefix, "-centroids.geojson")
    ),
    municipality_geojson = file.path(
      RESULTS_ROOT,
      paste0(output_prefix, "-municipality.geojson")
    ),
    greenzones_geojson = file.path(
      RESULTS_ROOT,
      paste0(output_prefix, "-greenzones.geojson")
    ),
    clinics_any_geojson = file.path(
      RESULTS_ROOT,
      paste0(output_prefix, "-clinics_any.geojson")
    ),
    clinics_public_geojson = file.path(
      RESULTS_ROOT,
      paste0(output_prefix, "-clinics_public.geojson")
    ),
    gz = file.path(
      RESULTS_ROOT,
      paste0(env$CITY_CODE, "_greenzones.png")
    ),
    clinic_any = file.path(
      RESULTS_ROOT,
      paste0(env$CITY_CODE, "_clinics_any.png")
    ),
    clinic_public = file.path(
      RESULTS_ROOT,
      paste0(env$CITY_CODE, "_clinics_public.png")
    ),
    y = file.path(
      RESULTS_ROOT,
      paste0(output_prefix, "_y.png")
    ),
    svar = file.path(
      RESULTS_ROOT,
      paste0(env$CITY_CODE, "_", selected_bias, ".png")
    )
  )

  saveRDS(citydata, file = filenames$rds)

  open_data_files <- export_open_data_files(
    citydata = citydata,
    bias = bias,
    env = env,
    filenames = filenames,
    prefix = output_prefix,
    selected_bias = selected_bias
  )

  fplot.gz <- ggplot() +
    geom_sf(data = citydata$geometry, fill = NA) +
    geom_sf(data = citydata$gz, fill = "green2") +
    theme_void()

  suppressMessages(ggsave(filenames$gz, plot = fplot.gz))

  fplot.clinic_any <- ggplot() +
    geom_sf(data = citydata$geometry, fill = NA) +
    geom_sf(data = citydata$clinics_any, color = "orange") +
    theme_void()

  suppressMessages(ggsave(filenames$clinic_any, plot = fplot.clinic_any))

  fplot.clinic_public <- ggplot() +
    geom_sf(data = citydata$geometry, fill = NA) +
    geom_sf(data = citydata$clinics_public, color = "red") +
    theme_void()

  suppressMessages(ggsave(filenames$clinic_public, plot = fplot.clinic_public))

  fplot.y <- ggplot() +
    geom_sf(data = citydata$geometry, aes(fill = citydata$y)) +
    scale_fill_steps(
      name = paste(env$DIST_NAME, "distance\n(meters)"),
      n.breaks = 8,
      low = "white",
      high = "red"
    ) +
    theme_void()

  suppressMessages(ggsave(filenames$y, plot = fplot.y))

  fplot.svar <- ggplot() +
    geom_sf(data = citydata$geometry, aes(fill = citydata$x[, bias_idx + 1])) +
    scale_fill_steps(
      name = "",
      n.breaks = 8,
      low = "white",
      high = "red"
    ) +
    theme_void()

  suppressMessages(ggsave(filenames$svar, plot = fplot.svar))

  generated_paths <- unique(c(
    filenames$rds,
    unname(unlist(open_data_files)),
    filenames$gz,
    filenames$clinic_any,
    filenames$clinic_public,
    filenames$y,
    filenames$svar
  ))

  generated_paths <- generated_paths[file.exists(generated_paths)]

  files_out <- lapply(generated_paths, function(path) {
    list(name = basename(path), path = path)
  })

  list(
    job_id = job_id,
    city_code = env$CITY_CODE,
    city_name = as.character(citydata[["name"]])[1],
    locations = env$LOCATIONS,
    dist_type = env$DIST_TYPE,
    biasvar = selected_bias,
    cache_id = ctx$cache_id,
    bias_summary = bias,
    files = files_out
  )
}

#* @get /health
function() {
  list(
    status = "ok",
    osrm_url = OSRM_URL,
    osrm_reachable = url_check(OSRM_URL)
  )
}

#* @get /bias-table/<city_code>
#* @serializer unboxedJSON
function(city_code, locations = "parks", dist_type = "mean", res) {
  out <- tryCatch(
    build_bias_table(
      city_code = city_code,
      locations = locations,
      dist_type = dist_type
    ),
    error = function(e) {
      if (is_no_facilities_error(e)) {
        res$status <- 200
        return(no_facilities_response(city_code, locations, dist_type, e))
      }

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
      relative_path = if (!is.null(payload$relative_path)) {
        payload$relative_path
      } else {
        NULL
      }
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
      biasvar = if (!is.null(payload$biasvar)) payload$biasvar else NULL,
      cache_id = if (!is.null(payload$cache_id)) payload$cache_id else NULL
    ),
    error = function(e) {
      res$status <- 400
      list(error = TRUE, message = conditionMessage(e))
    }
  )

  out
}
