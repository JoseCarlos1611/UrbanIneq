# UrbanIneq cache utilities
# Separates source-data, municipality-base and OSRM-routing caches.

CACHE_ROOT <- file.path(RESULTS_ROOT, ".cache")
CACHE_EPOCH <- Sys.getenv("URBANINEQ_CACHE_EPOCH", unset = "1")
INPUT_CACHE_VERSION <- 1L
BASE_CACHE_VERSION <- 1L
ROUTING_CACHE_VERSION <- 1L

.URBANINEQ_MEMORY <- new.env(parent = emptyenv())
.URBANINEQ_MEMORY$spatial <- new.env(parent = emptyenv())
.URBANINEQ_MEMORY$ine <- new.env(parent = emptyenv())
.URBANINEQ_MEMORY$base <- new.env(parent = emptyenv())
.URBANINEQ_MEMORY$routing <- new.env(parent = emptyenv())

cache_dir <- function(kind) {
  path <- file.path(CACHE_ROOT, kind)
  dir.create(path, recursive = TRUE, showWarnings = FALSE)
  path
}

cache_safe_name <- function(x) {
  gsub("[^A-Za-z0-9_.-]", "_", as.character(x))
}

file_signature <- function(paths) {
  paths <- normalizePath(paths, winslash = "/", mustWork = FALSE)
  info <- file.info(paths)
  pieces <- vapply(seq_along(paths), function(i) {
    paste(
      paths[i],
      if (is.na(info$size[i])) "missing" else as.character(info$size[i]),
      if (is.na(info$mtime[i])) "missing" else format(info$mtime[i], "%Y-%m-%dT%H:%M:%OS6", tz = "UTC"),
      sep = "|"
    )
  }, character(1))
  paste(c(CACHE_EPOCH, pieces), collapse = "||")
}

atomic_save_rds <- function(object, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".tmp-", Sys.getpid(), "-", sprintf("%08d", sample.int(99999999L, 1)))
  saveRDS(object, tmp)
  if (!file.rename(tmp, path)) {
    file.copy(tmp, path, overwrite = TRUE)
    unlink(tmp)
  }
  invisible(path)
}

read_versioned_cache <- function(path, version, signature = NULL) {
  if (!file.exists(path)) return(NULL)
  obj <- tryCatch(readRDS(path), error = function(e) NULL)
  if (is.null(obj) || is.null(obj$cache_version)) return(NULL)
  if (!identical(as.integer(obj$cache_version), as.integer(version))) return(NULL)
  if (!is.null(signature) && !identical(obj$source_signature, signature)) return(NULL)
  obj
}

# ---- Lazy IECA spatial layer cache -----------------------------------------

spatial_layer_specs <- function() {
  list(
    municipalities = file.path(APP_DIR, "IECA", "13_01_TerminoMunicipal.shp"),
    tracts = file.path(APP_DIR, "IECA", "13_27_SeccionCensal.shp"),
    parks = file.path(APP_DIR, "IECA", "07_06_ZonaVerde.shp"),
    clinics = file.path(APP_DIR, "IECA", "12_01_CentroSalud.shp"),
    hospitals = file.path(APP_DIR, "IECA", "12_02_Hospital_CAE.shp"),
    iepabra = file.path(APP_DIR, "IECA", "iepabra2021.shp")
  )
}

get_spatial_layer <- function(name) {
  specs <- spatial_layer_specs()
  path <- specs[[name]]
  if (is.null(path)) stop(paste0("Unknown spatial layer: ", name))

  sig <- file_signature(path)
  mem <- .URBANINEQ_MEMORY$spatial
  if (exists(name, envir = mem, inherits = FALSE)) {
    cached <- get(name, envir = mem, inherits = FALSE)
    if (identical(cached$source_signature, sig)) return(cached$data)
  }

  cache_path <- file.path(cache_dir("inputs"), paste0("spatial-", cache_safe_name(name), ".rds"))
  disk <- read_versioned_cache(cache_path, INPUT_CACHE_VERSION, sig)
  if (!is.null(disk) && !is.null(disk$data)) {
    assign(name, disk, envir = mem)
    return(disk$data)
  }

  data <- sf::st_read(path, quiet = TRUE)
  record <- list(
    data = data,
    source_signature = sig,
    cache_version = INPUT_CACHE_VERSION,
    created_at = as.character(Sys.time())
  )
  atomic_save_rds(record, cache_path)
  assign(name, record, envir = mem)
  data
}

# ---- INE workbook cache ----------------------------------------------------

ine_source_paths <- function() {
  c(
    income = file.path(APP_DIR, "INE", "30824.xlsx"),
    census = file.path(APP_DIR, "INE", "Censo_2021_Andalucia.xlsx")
  )
}

load_ine_bundle <- function() {
  paths <- ine_source_paths()
  sig <- file_signature(paths)
  mem <- .URBANINEQ_MEMORY$ine

  if (exists("bundle", envir = mem, inherits = FALSE)) {
    cached <- get("bundle", envir = mem, inherits = FALSE)
    if (identical(cached$source_signature, sig)) return(cached$data)
  }

  cache_path <- file.path(cache_dir("inputs"), "ine-workbooks.rds")
  disk <- read_versioned_cache(cache_path, INPUT_CACHE_VERSION, sig)
  if (!is.null(disk) && !is.null(disk$data)) {
    assign("bundle", disk, envir = mem)
    return(disk$data)
  }

  # Preserve the exact read_excel layouts used by the original code.
  city_names <- readxl::read_excel(
    path = paths[["income"]],
    range = "A8:A55442",
    .name_repair = "unique_quiet"
  )[[1]]
  income_years <- colnames(readxl::read_excel(
    path = paths[["income"]],
    range = "A8:Z8",
    .name_repair = "unique_quiet"
  ))
  income_data <- readxl::read_excel(
    path = paths[["income"]],
    skip = 6,
    .name_repair = "unique_quiet"
  )
  census_data <- readxl::read_excel(path = paths[["census"]], skip = 10)

  data <- list(
    city_names = city_names,
    income_years = income_years,
    income_data = income_data,
    census_data = census_data
  )
  record <- list(
    data = data,
    source_signature = sig,
    cache_version = INPUT_CACHE_VERSION,
    created_at = as.character(Sys.time())
  )
  atomic_save_rds(record, cache_path)
  assign("bundle", record, envir = mem)
  data
}

# ---- Municipality base cache ----------------------------------------------

base_source_signature <- function() {
  paths <- c(
    unname(unlist(spatial_layer_specs()[c("municipalities", "tracts", "iepabra")])),
    unname(ine_source_paths())
  )
  file_signature(paths)
}

base_cache_path <- function(city_code) {
  file.path(cache_dir("base"), paste0(cache_safe_name(city_code), ".rds"))
}

read_base_cache <- function(city_code) {
  key <- as.character(city_code)
  sig <- base_source_signature()
  mem <- .URBANINEQ_MEMORY$base
  if (exists(key, envir = mem, inherits = FALSE)) {
    obj <- get(key, envir = mem, inherits = FALSE)
    if (identical(obj$source_signature, sig) && identical(as.integer(obj$cache_version), BASE_CACHE_VERSION)) {
      return(obj$data)
    }
  }

  disk <- read_versioned_cache(base_cache_path(city_code), BASE_CACHE_VERSION, sig)
  if (is.null(disk) || is.null(disk$data)) return(NULL)
  assign(key, disk, envir = mem)
  disk$data
}

write_base_cache <- function(city_code, data) {
  record <- list(
    data = data,
    source_signature = base_source_signature(),
    cache_version = BASE_CACHE_VERSION,
    created_at = as.character(Sys.time())
  )
  atomic_save_rds(record, base_cache_path(city_code))
  assign(as.character(city_code), record, envir = .URBANINEQ_MEMORY$base)
  invisible(data)
}

# ---- OSRM routing matrix cache --------------------------------------------

routing_source_signature <- function(locations) {
  specs <- spatial_layer_specs()
  target_paths <- switch(
    locations,
    parks = specs[["parks"]],
    clinics_public = c(specs[["clinics"]], specs[["hospitals"]]),
    clinics_any = c(specs[["clinics"]], specs[["hospitals"]]),
    stop(paste0("Unknown locations: ", locations))
  )
  file_signature(c(specs[["municipalities"]], specs[["tracts"]], target_paths))
}

routing_cache_id <- function(city_code, locations) {
  paste(cache_safe_name(city_code), cache_safe_name(locations), "foot", sep = "__")
}

routing_cache_path <- function(city_code, locations) {
  file.path(cache_dir("routing"), paste0(routing_cache_id(city_code, locations), ".rds"))
}

read_routing_cache <- function(city_code, locations) {
  key <- routing_cache_id(city_code, locations)
  sig <- routing_source_signature(locations)
  mem <- .URBANINEQ_MEMORY$routing
  if (exists(key, envir = mem, inherits = FALSE)) {
    obj <- get(key, envir = mem, inherits = FALSE)
    if (identical(obj$source_signature, sig) && identical(as.integer(obj$cache_version), ROUTING_CACHE_VERSION)) {
      return(obj$data)
    }
  }

  disk <- read_versioned_cache(routing_cache_path(city_code, locations), ROUTING_CACHE_VERSION, sig)
  if (is.null(disk) || is.null(disk$data)) return(NULL)
  assign(key, disk, envir = mem)
  disk$data
}

write_routing_cache <- function(city_code, locations, data) {
  key <- routing_cache_id(city_code, locations)
  record <- list(
    data = data,
    source_signature = routing_source_signature(locations),
    cache_version = ROUTING_CACHE_VERSION,
    created_at = as.character(Sys.time()),
    osrm_url = OSRM_URL,
    profile = "foot"
  )
  atomic_save_rds(record, routing_cache_path(city_code, locations))
  assign(key, record, envir = .URBANINEQ_MEMORY$routing)
  invisible(data)
}

clear_memory_caches <- function() {
  rm(list = ls(.URBANINEQ_MEMORY$spatial), envir = .URBANINEQ_MEMORY$spatial)
  rm(list = ls(.URBANINEQ_MEMORY$ine), envir = .URBANINEQ_MEMORY$ine)
  rm(list = ls(.URBANINEQ_MEMORY$base), envir = .URBANINEQ_MEMORY$base)
  rm(list = ls(.URBANINEQ_MEMORY$routing), envir = .URBANINEQ_MEMORY$routing)
  invisible(TRUE)
}

# ---- Static target-map cache ----------------------------------------------

static_map_meta_path <- function(output_path) {
  file.path(cache_dir("static_maps"), paste0(cache_safe_name(basename(output_path)), ".meta.rds"))
}

static_map_is_current <- function(output_path, locations) {
  if (!file.exists(output_path)) return(FALSE)
  meta <- tryCatch(readRDS(static_map_meta_path(output_path)), error = function(e) NULL)
  if (is.null(meta)) return(FALSE)
  identical(meta$source_signature, routing_source_signature(locations)) &&
    identical(as.integer(meta$cache_version), ROUTING_CACHE_VERSION)
}

mark_static_map_current <- function(output_path, locations) {
  atomic_save_rds(
    list(
      source_signature = routing_source_signature(locations),
      cache_version = ROUTING_CACHE_VERSION,
      created_at = as.character(Sys.time())
    ),
    static_map_meta_path(output_path)
  )
  invisible(output_path)
}
