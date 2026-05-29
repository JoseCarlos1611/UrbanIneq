# Copyright 2023-2024 Pepa Ramirez-Cobo and Ismael Montero

# Data bootstrapper for UrbanIneq.
# By default this script downloads only IECA data. INE files are expected
# to be versioned under backend/INE or provided by the user.
# Set DOWNLOAD_INE=true to also download INE/30824.xlsx.

APP_DIR <- getwd()
IECA_DIR <- file.path(APP_DIR, "IECA")
INE_DIR <- file.path(APP_DIR, "INE")

dir.create(IECA_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(INE_DIR, recursive = TRUE, showWarnings = FALSE)

IECA_URL_LIST <- IECA_FILE_LIST <- list()

IECA_URL_LIST[["LIMITS"]] <- "https://www.juntadeandalucia.es/institutodeestadisticaycartografia/dega/sites/default/files/datos/094-dera-13-limites-administrativos.zip"
IECA_FILE_LIST[["LIMITS"]] <- c(
  "13_01_TerminoMunicipal.cpg",
  "13_01_TerminoMunicipal.dbf",
  "13_01_TerminoMunicipal.prj",
  "13_01_TerminoMunicipal.shp",
  "13_01_TerminoMunicipal.shx",
  "13_27_SeccionCensal.cpg",
  "13_27_SeccionCensal.dbf",
  "13_27_SeccionCensal.prj",
  "13_27_SeccionCensal.shp",
  "13_27_SeccionCensal.shx"
)

IECA_URL_LIST[["URBAN"]] <- "https://www.juntadeandalucia.es/institutodeestadisticaycartografia/dega/sites/default/files/datos/094-dera-7-sistema-urbano-6f7g.zip"
IECA_FILE_LIST[["URBAN"]] <- c(
  "07_06_ZonaVerde.cpg",
  "07_06_ZonaVerde.dbf",
  "07_06_ZonaVerde.prj",
  "07_06_ZonaVerde.shp",
  "07_06_ZonaVerde.shx"
)

IECA_URL_LIST[["SERVICE"]] <- "https://www.juntadeandalucia.es/institutodeestadisticaycartografia/dega/sites/default/files/datos/094-dera-12-servicios.zip"
IECA_FILE_LIST[["SERVICE"]] <- c(
  "12_01_CentroSalud.cpg",
  "12_01_CentroSalud.dbf",
  "12_01_CentroSalud.prj",
  "12_01_CentroSalud.shp",
  "12_01_CentroSalud.shx",
  "12_02_Hospital_CAE.cpg",
  "12_02_Hospital_CAE.dbf",
  "12_02_Hospital_CAE.prj",
  "12_02_Hospital_CAE.shp",
  "12_02_Hospital_CAE.shx"
)

IECA_URL_LIST[["DEMO"]] <- "https://www.juntadeandalucia.es/institutodeestadisticaycartografia/dega/sites/default/files/datos/077-poblacion-registros-administrativos-DatosEspacialesIEPABRA-1a5e.zip"
IECA_FILE_LIST[["DEMO"]] <- c(
  "iepabra2021.cpg",
  "iepabra2021.dbf",
  "iepabra2021.prj",
  "iepabra2021.qmd",
  "iepabra2021.shp",
  "iepabra2021.shx"
)

INE_INCOME_URL <- "https://www.ine.es/jaxiT3/files/t/es/xlsx/30824.xlsx"
INE_INCOME_NAME <- "30824.xlsx"

all_files_exist <- function(dir_path, files) {
  all(file.exists(file.path(dir_path, files)))
}

download_file <- function(url, destfile) {
  timeout.prev <- getOption("timeout")
  method.prev <- getOption("download.file.method")
  on.exit({
    options(timeout = timeout.prev)
    options(download.file.method = method.prev)
  }, add = TRUE)

  options(timeout = 3600)

  cat("Downloading ", url, "\n", sep = "")

  if (.Platform$OS.type == "windows") {
    download.file(url, destfile, mode = "wb")
  } else {
    download.file(url, destfile, mode = "wb", method = "libcurl")
  }
}

ieca_get <- function(url_list, file_list) {
  cat("Checking IECA spatial data in ", IECA_DIR, "\n", sep = "")

  for (name in names(url_list)) {
    required_files <- file_list[[name]]

    if (all_files_exist(IECA_DIR, required_files)) {
      cat("IECA layer ", name, " already available, skipping download\n", sep = "")
      next
    }

    filename <- tail(strsplit(url_list[[name]], "/")[[1]], 1)
    zip_path <- file.path(IECA_DIR, filename)

    if (!file.exists(zip_path)) {
      download_file(url_list[[name]], zip_path)
    } else {
      cat("IECA zip ", filename, " already available, reusing it\n", sep = "")
    }

    cat("Unzipping IECA layer ", name, "\n", sep = "")
    unzip(zip_path, files = required_files, exdir = IECA_DIR, overwrite = TRUE)
  }

  cat("IECA data are ready\n")
}

ine_get <- function(income_url, filename) {
  destfile <- file.path(INE_DIR, filename)

  if (file.exists(destfile)) {
    cat("INE income data already available, not downloading\n")
  } else {
    cat("Downloading INE income data\n")
    download_file(income_url, destfile)
  }
}

if (tolower(Sys.getenv("DOWNLOAD_IECA", "true")) == "true") {
  ieca_get(IECA_URL_LIST, IECA_FILE_LIST)
} else {
  cat("Skipping IECA download because DOWNLOAD_IECA is not true\n")
}

if (tolower(Sys.getenv("DOWNLOAD_INE", "false")) == "true") {
  ine_get(INE_INCOME_URL, INE_INCOME_NAME)
} else {
  cat("Skipping INE download because DOWNLOAD_INE is not true\n")
}
