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
CONTEXT_CACHE_VERSION <- 3L

source(file.path(APP_DIR, "cache_utils.R"), local = TRUE)
source(file.path(APP_DIR, "numdata.R"), local = TRUE)
source(file.path(APP_DIR, "spdata.R"), local = TRUE)

ensure_dirs <- function() {
  for (d in DATA_DIRS) dir.create(file.path(APP_DIR, d), recursive = TRUE, showWarnings = FALSE)
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
    stop(paste0(
      "Missing INE input files: ", paste(missing, collapse = ", "),
      ". Add them to backend/INE before running the pipeline."
    ))
  }
}

normalize_text <- function(x) {
  out <- iconv(x, from = "UTF-8", to = "ASCII//TRANSLIT")
  tolower(trimws(out))
}

resolve_city_code <- function(city_code = NULL, city_name = NULL, income_file = NULL) {
  if (!is.null(city_code) && nzchar(city_code)) {
    if (nchar(city_code) != 5) stop("city_code must have length 5")
    return(city_code)
  }
  if (is.null(city_name) || !nzchar(city_name)) stop("You must provide either city_code or city_name")

  bundle <- load_ine_bundle()
  alldata <- bundle$city_names
  alldata <- alldata[grep("^[0-9]{5} ", alldata)]
  pretty <- substr(alldata, 7, nchar(alldata))
  pretty.norm <- normalize_text(pretty)
  query <- normalize_text(city_name)
  exact_idx <- which(pretty.norm == query)
  if (length(exact_idx) == 1) return(substr(alldata[exact_idx], 1, 5))

  partial_idx <- grep(query, pretty.norm, ignore.case = TRUE)
  if (length(partial_idx) == 1) return(substr(alldata[partial_idx], 1, 5))
  if (length(partial_idx) > 1) {
    stop(paste0("The municipality name is ambiguous. Matches: ", paste(head(unique(pretty[partial_idx]), 10), collapse = ", ")))
  }
  stop(paste0("No municipality was found for: ", city_name))
}

url_check <- function(endpoint) {
  check <- try({ curlGetHeaders(endpoint) }, silent = TRUE)
  !inherits(check, "try-error")
}

# Same statistic as before, with less apply()/temporary-matrix overhead.
databias_local <- function(x, y) {
  x <- as.data.frame(x)
  y <- as.numeric(y)
  medians <- vapply(x, median, numeric(1))
  lower <- greater <- numeric(ncol(x))
  for (j in seq_len(ncol(x))) {
    below <- which(x[[j]] < medians[j])
    above <- which(x[[j]] >= medians[j])
    lower[j] <- mean(y[below])
    greater[j] <- mean(y[above])
  }
  nums <- abs(lower - greater)
  minv <- pmin(lower, greater)
  maxv <- pmax(lower, greater)
  variations <- round((maxv - minv) / minv * 100, 2)
  out <- data.frame(lower = lower, greater = greater, u = nums, variation = variations, median = medians)
  rownames(out) <- colnames(x)
  out
}

bias_labels <- c(
  "Population", "Income", "Prop. of children", "Prop. of elderly population",
  "Unemployment rate", "Prop. of foreign population", "Loneliness index"
)

select_suggested_bias <- function(bias) {
  eligible <- rep(FALSE, nrow(bias))
  for (i in seq_len(nrow(bias))) {
    var_num <- as.integer(sub("x", "", rownames(bias)[i]))
    above_median <- as.numeric(bias[i, "greater"])
    below_median <- as.numeric(bias[i, "lower"])
    eligible[i] <- if (var_num == 2) above_median < below_median else above_median > below_median
  }
  if (!any(eligible)) return(0L)
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
      message = paste0("No destinations are available for this municipality and accessibility option: ", label,
                       ". Choose another accessibility option or municipality."),
      city_code = city_code, locations = locations, call = NULL
    ),
    class = c("no_facilities", "error", "condition")
  )
}

is_no_facilities_error <- function(e) {
  inherits(e, "no_facilities") || grepl('dst.*at least 1 row|should have at least 1 row|No destinations are available', conditionMessage(e))
}

no_facilities_response <- function(city_code, locations, dist_type, e) {
  list(available = FALSE, cache_id = NULL, locations = locations, dist_type = dist_type, rows = list(), message = conditionMessage(e))
}

analysis_headers <- function() {
  list(
    orig = c(
      "Sección", "Personas", "Porcentaje de personas de más de 64 años",
      "Porcentaje de población extranjera", "Porcentaje de población parada sobre población activa"
    ),
    repl = c("ct_code", "total", "elderly", "foreigner", "unemployed")
  )
}

analysis_vars <- function() {
  list(
    orig = c("total", "mean_income", "underage", "elderly", "unemployed", "foreigner", "lonely"),
    repl = c("x1", "x2", "x3", "x4", "x5", "x6", "x7")
  )
}

build_base_data <- function(city_code) {
  cached <- read_base_cache(city_code)
  if (!is.null(cached)) return(cached)

  headers <- analysis_headers()
  vars <- analysis_vars()
  ine <- load_ine_bundle()

  municipality <- sp.get_city(get_spatial_layer("municipalities"), city_code)
  tractdata <- sp.get_tracts(get_spatial_layer("tracts"), city_code, tract_exclude = NULL)
  if (nrow(municipality) < 1 || nrow(tractdata) < 1) stop(paste0("No spatial census data found for municipality ", city_code))

  income_data <- ct.get_income(city_code, file.path(APP_DIR, "INE", "30824.xlsx"), ine_bundle = ine)
  census_data <- ct.get_census_info(city_code, headers, file.path(APP_DIR, "INE", "Censo_2021_Andalucia.xlsx"), ine_bundle = ine)

  iepabra <- get_spatial_layer("iepabra")
  ieca_data <- st_drop_geometry(subset(iepabra, subset = (CUMUN == city_code), select = c(CUSEC, I6, I16)))
  colnames(ieca_data) <- c("ct_code", "lonely", "underage")

  all_data <- merge(income_data, census_data, by = "ct_code")
  all_data <- merge(all_data, ieca_data, by = "ct_code")
  ct_codes <- all_data$ct_code
  all_data <- all_data[, vars$orig, drop = FALSE]
  colnames(all_data) <- vars$repl
  rownames(all_data) <- ct_codes

  # Join X to tract geometry once. This is independent of destination and distance statistic.
  raw_base <- st_as_sf(merge(all_data, tractdata, by = "row.names"))
  raw_names <- raw_base$Row.names
  raw_base <- subset(raw_base, select = vars$repl)
  rownames(raw_base) <- raw_names

  x <- cbind(1, st_drop_geometry(raw_base[, vars$repl, drop = FALSE]))
  xnorm <- cbind(1, scale(st_drop_geometry(raw_base[, vars$repl, drop = FALSE])))
  colnames(x)[1] <- colnames(xnorm)[1] <- "Intercept"

  centroids_all <- sp.centroid_fix(st_centroid(tractdata), NULL)
  rownames(centroids_all) <- rownames(tractdata)
  centroid_idx <- match(rownames(raw_base), rownames(centroids_all))
  centroids <- st_coordinates(centroids_all[centroid_idx, ])
  rownames(centroids) <- rownames(raw_base)

  data <- list(
    city_code = city_code,
    municipality = municipality,
    tractdata = tractdata,
    raw_base = raw_base,
    x = x,
    xnorm = xnorm,
    centroids = centroids,
    name = municipality$nombre,
    varname = iconv(gsub(" ", "", tolower(municipality$nombre)), to = "ASCII//TRANSLIT")
  )
  write_base_cache(city_code, data)
  data
}

get_destinations <- function(base, locations) {
  locations <- match.arg(locations, c("parks", "clinics_public", "clinics_any"))
  if (locations == "parks") {
    parks <- subset(get_spatial_layer("parks"), subset = (tipo == "Parque"))
    return(parks[st_contains(base$municipality, parks)[[1]], ])
  }

  clinics <- subset(get_spatial_layer("clinics"), subset = cod_mun == base$city_code, select = cod_mun)
  clinics$sistema_sa <- "Público"
  hospitals <- subset(get_spatial_layer("hospitals"), subset = cod_mun == base$city_code, select = c(cod_mun, sistema_sa))
  destinations <- rbind(clinics, hospitals)
  if (locations == "clinics_public") destinations <- subset(destinations, subset = sistema_sa == "Público")
  destinations
}

get_or_build_routing <- function(base, locations) {
  cached <- read_routing_cache(base$city_code, locations)
  if (!is.null(cached)) return(cached)

  destinations <- get_destinations(base, locations)
  if (is.null(destinations) || nrow(destinations) < 1) stop(no_facilities_error(base$city_code, locations))
  if (!url_check(OSRM_URL)) stop(paste0("No OSRM instance is available at ", OSRM_URL))

  routing <- sp.osrm_matrix(base$tractdata, destinations, tract_fix = NULL, osrm_url = OSRM_URL)
  if (nrow(routing$distances) == nrow(base$tractdata)) {
    rownames(routing$distances) <- rownames(base$tractdata)
  }
  rownames(routing$centroids) <- rownames(base$tractdata)
  routing$destinations <- destinations
  routing$locations <- locations
  write_routing_cache(base$city_code, locations, routing)
  routing
}

count_available_locations <- function(city_code, locations) {
  base <- build_base_data(city_code)
  destinations <- get_destinations(base, locations)
  if (is.null(destinations)) 0L else nrow(destinations)
}

assert_locations_available <- function(city_code, locations) {
  n <- count_available_locations(city_code, locations)
  if (is.null(n) || is.na(n) || n < 1) stop(no_facilities_error(city_code, locations))
  invisible(n)
}

build_analysis_context <- function(city_code = NULL, city_name = NULL, locations = "parks", dist_type = "mean") {
  oldwd <- getwd()
  on.exit(setwd(oldwd), add = TRUE)
  setwd(APP_DIR)
  ensure_data()

  resolved_city <- resolve_city_code(city_code, city_name, file.path(APP_DIR, "INE", "30824.xlsx"))
  locations <- match.arg(locations, c("parks", "clinics_public", "clinics_any"))
  dist_type <- match.arg(dist_type, c("mean", "min", "max"))

  base <- build_base_data(resolved_city)
  routing <- get_or_build_routing(base, locations)
  y_all <- sp.reduce_dists(routing$distances, dist_type)

  idx <- match(rownames(base$raw_base), rownames(y_all))
  if (any(is.na(idx))) stop("Routing result could not be aligned with census sections")
  y <- matrix(y_all$y[idx], ncol = 1)
  rownames(y) <- rownames(base$raw_base)

  raw <- base$raw_base
  raw$y <- as.numeric(y[, 1])

  citydata <- list(
    x = base$x,
    y = y,
    centroids = base$centroids,
    centroids_orig = NULL,
    xnorm = base$xnorm,
    raw = raw,
    geometry = st_geometry(raw),
    # citydata$d intentionally removed: O(n^2) and unused by the current web pipeline.
    gz = if (locations == "parks") routing$destinations else NULL,
    clinics_any = if (locations == "clinics_any") routing$destinations else NULL,
    clinics_public = if (locations == "clinics_public") routing$destinations else NULL,
    municipality = base$municipality,
    name = base$name,
    varname = base$varname
  )

  env <- new.env(parent = globalenv())
  env$CITY_CODE <- resolved_city
  env$LOCATIONS <- locations
  env$DIST_TYPE <- dist_type
  env$DIST_NAME <- c(mean = "Average", min = "Min", max = "Max")[[dist_type]]
  env$OSRM_URL <- OSRM_URL

  list(env = env, citydata = citydata)
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
  paste(sanitize_cache_part(city_code), sanitize_cache_part(locations), sanitize_cache_part(dist_type), sep = "__")
}

context_cache_path <- function(cache_id) {
  file.path(context_cache_dir(), paste0(sanitize_cache_part(cache_id), ".rds"))
}

context_dependency_signature <- function(locations) {
  paste(base_source_signature(), routing_source_signature(locations), sep = "##")
}

minimal_env <- function(city_code, locations, dist_type) {
  env <- new.env(parent = globalenv())
  env$CITY_CODE <- city_code
  env$LOCATIONS <- match.arg(locations, c("parks", "clinics_public", "clinics_any"))
  env$DIST_TYPE <- match.arg(dist_type, c("mean", "min", "max"))
  env$DIST_NAME <- c(mean = "Average", min = "Min", max = "Max")[[env$DIST_TYPE]]
  env$OSRM_URL <- OSRM_URL
  env
}

read_cached_context <- function(cache_id, expected_city = NULL, expected_locations = NULL, expected_dist_type = NULL) {
  if (is.null(cache_id) || !nzchar(as.character(cache_id))) return(NULL)
  path <- context_cache_path(cache_id)
  if (!file.exists(path)) return(NULL)
  cached <- tryCatch(readRDS(path), error = function(e) NULL)
  if (is.null(cached) || is.null(cached$citydata) || is.null(cached$config)) return(NULL)
  if (is.null(cached$cache_version) || !identical(as.integer(cached$cache_version), CONTEXT_CACHE_VERSION)) return(NULL)

  cfg <- cached$config
  if (!is.null(expected_city) && !identical(as.character(cfg$city_code), as.character(expected_city))) return(NULL)
  if (!is.null(expected_locations) && !identical(as.character(cfg$locations), as.character(expected_locations))) return(NULL)
  if (!is.null(expected_dist_type) && !identical(as.character(cfg$dist_type), as.character(expected_dist_type))) return(NULL)

  expected_sig <- context_dependency_signature(cfg$locations)
  if (is.null(cached$source_signature) || !identical(cached$source_signature, expected_sig)) return(NULL)

  list(
    env = minimal_env(cfg$city_code, cfg$locations, cfg$dist_type),
    citydata = cached$citydata,
    cache_id = cache_id
  )
}

write_cached_context <- function(cache_id, ctx) {
  atomic_save_rds(
    list(
      config = list(
        city_code = ctx$env$CITY_CODE,
        locations = ctx$env$LOCATIONS,
        dist_type = ctx$env$DIST_TYPE
      ),
      citydata = ctx$citydata,
      created_at = as.character(Sys.time()),
      source_signature = context_dependency_signature(ctx$env$LOCATIONS),
      cache_version = CONTEXT_CACHE_VERSION
    ),
    context_cache_path(cache_id)
  )
}

get_or_build_context <- function(city_code = NULL, city_name = NULL, locations = "parks", dist_type = "mean", cache_id = NULL) {
  ensure_data()
  resolved_city <- resolve_city_code(city_code, city_name, file.path(APP_DIR, "INE", "30824.xlsx"))
  locations <- match.arg(locations, c("parks", "clinics_public", "clinics_any"))
  dist_type <- match.arg(dist_type, c("mean", "min", "max"))

  automatic_id <- context_cache_id(resolved_city, locations, dist_type)
  requested_id <- if (!is.null(cache_id) && nzchar(as.character(cache_id))) as.character(cache_id) else automatic_id

  cached <- read_cached_context(requested_id, resolved_city, locations, dist_type)
  if (is.null(cached) && !identical(requested_id, automatic_id)) {
    cached <- read_cached_context(automatic_id, resolved_city, locations, dist_type)
    if (!is.null(cached)) cached$cache_id <- automatic_id
  }
  if (!is.null(cached)) return(cached)

  ctx <- build_analysis_context(
    city_code = resolved_city,
    locations = locations,
    dist_type = dist_type
  )
  write_cached_context(automatic_id, ctx)
  ctx$cache_id <- automatic_id
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

  # Facility/park maps are static for a municipality. Generate only the
  # selected accessibility target, and only if the file does not already exist.
  static_target_paths <- character()

  if (env$LOCATIONS == "parks" && !is.null(citydata$gz)) {
    if (!static_map_is_current(filenames$gz, env$LOCATIONS)) {
      fplot.gz <- ggplot() +
        geom_sf(data = citydata$geometry, fill = NA) +
        geom_sf(data = citydata$gz, fill = "green2") +
        theme_void()
      suppressMessages(ggsave(filenames$gz, plot = fplot.gz))
      mark_static_map_current(filenames$gz, env$LOCATIONS)
    }
    static_target_paths <- c(static_target_paths, filenames$gz)
  } else if (env$LOCATIONS == "clinics_any" && !is.null(citydata$clinics_any)) {
    if (!static_map_is_current(filenames$clinic_any, env$LOCATIONS)) {
      fplot.clinic_any <- ggplot() +
        geom_sf(data = citydata$geometry, fill = NA) +
        geom_sf(data = citydata$clinics_any, color = "orange") +
        theme_void()
      suppressMessages(ggsave(filenames$clinic_any, plot = fplot.clinic_any))
      mark_static_map_current(filenames$clinic_any, env$LOCATIONS)
    }
    static_target_paths <- c(static_target_paths, filenames$clinic_any)
  } else if (env$LOCATIONS == "clinics_public" && !is.null(citydata$clinics_public)) {
    if (!static_map_is_current(filenames$clinic_public, env$LOCATIONS)) {
      fplot.clinic_public <- ggplot() +
        geom_sf(data = citydata$geometry, fill = NA) +
        geom_sf(data = citydata$clinics_public, color = "red") +
        theme_void()
      suppressMessages(ggsave(filenames$clinic_public, plot = fplot.clinic_public))
      mark_static_map_current(filenames$clinic_public, env$LOCATIONS)
    }
    static_target_paths <- c(static_target_paths, filenames$clinic_public)
  }

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
    static_target_paths,
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
