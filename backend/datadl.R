# Copyright 2023-2024 Pepa Ramirez-Cobo and Ismael Montero

# This file contains the functions needed to download
# the raw data used to generate real world datasets.
# Namely, the following sources will be used:
# -IECA
# -INE
# Downloading the data will also allow the user to generate datasets
# for any municipality in the Andalusian region

IECA_URL_LIST <- IECA_FILE_LIST <- list()
IECA_URL_LIST[["LIMITS"]] <- "https://www.juntadeandalucia.es/institutodeestadisticaycartografia/dega/sites/default/files/datos/094-dera-13-limites-administrativos.zip"
#IECA_FILE_LIST[["LIMITS"]] <- c("13_01_TerminoMunicipal.cpg",
#                                "13_01_TerminoMunicipal.dbf",
#                                "13_01_TerminoMunicipal.prj",
#                                "13_01_TerminoMunicipal.shp",
#                                "13_01_TerminoMunicipal.shx",
#                                "13_24_BarrioUrbano.cpg",
#                                "13_24_BarrioUrbano.dbf",
#                                "13_24_BarrioUrbano.prj",
#                                "13_24_BarrioUrbano.shp",
#                                "13_24_BarrioUrbano.shx",
#                                "13_27_SeccionCensal.cpg",
#                                "13_27_SeccionCensal.dbf",
#                                "13_27_SeccionCensal.prj",
#                                "13_27_SeccionCensal.shp",
#                                "13_27_SeccionCensal.shx")
IECA_FILE_LIST[["LIMITS"]] <- c("13_01_TerminoMunicipal.cpg",
                                "13_01_TerminoMunicipal.dbf",
                                "13_01_TerminoMunicipal.prj",
                                "13_01_TerminoMunicipal.shp",
                                "13_01_TerminoMunicipal.shx",
                                "13_27_SeccionCensal.cpg",
                                "13_27_SeccionCensal.dbf",
                                "13_27_SeccionCensal.prj",
                                "13_27_SeccionCensal.shp",
                                "13_27_SeccionCensal.shx")
IECA_URL_LIST[["URBAN"]] <- "https://www.juntadeandalucia.es/institutodeestadisticaycartografia/dega/sites/default/files/datos/094-dera-7-sistema-urbano-6f7g.zip"
IECA_FILE_LIST[["URBAN"]] <- c("07_06_ZonaVerde.cpg",
                               "07_06_ZonaVerde.dbf",
                               "07_06_ZonaVerde.prj",
                               "07_06_ZonaVerde.shp",
                               "07_06_ZonaVerde.shx")
IECA_URL_LIST[["SERVICE"]] <- "https://www.juntadeandalucia.es/institutodeestadisticaycartografia/dega/sites/default/files/datos/094-dera-12-servicios.zip"
IECA_FILE_LIST[["SERVICE"]] <- c("12_01_CentroSalud.cpg",
                                 "12_01_CentroSalud.dbf",
                                 "12_01_CentroSalud.prj",
                                 "12_01_CentroSalud.shp",
                                 "12_01_CentroSalud.shx",
                                 "12_02_Hospital_CAE.cpg",
                                 "12_02_Hospital_CAE.dbf",
                                 "12_02_Hospital_CAE.prj",
                                 "12_02_Hospital_CAE.shp",
                                 "12_02_Hospital_CAE.shx")
IECA_URL_LIST[["DEMO"]] <- "https://www.juntadeandalucia.es/institutodeestadisticaycartografia/dega/sites/default/files/datos/077-poblacion-registros-administrativos-DatosEspacialesIEPABRA-1a5e.zip"
IECA_FILE_LIST[["DEMO"]] <- c("iepabra2021.cpg",
                              "iepabra2021.dbf",
                              "iepabra2021.prj",
                              "iepabra2021.qmd",
                              "iepabra2021.shp",
                              "iepabra2021.shx")

INE_INCOME_URL <- "https://www.ine.es/jaxiT3/files/t/es/xlsx/30824.xlsx"
INE_INCOME_NAME <- "30824.xlsx"

# Retrieve all spatial data files from IECA's website
# and unzip them so they can be used
ieca_get <- function(url_list, file_list) {
    timeout.prev <- getOption("timeout")
    options(timeout = 600)
    cat("Downloading spatial data from IECA's DERA website\n")
    for (name in names(url_list)) {
        filename <- tail(strsplit(url_list[[name]], "/")[[1]], 1)
        unzipfile <- paste0("IECA/", filename)
        if (!(filename %in% dir("IECA"))) download.file(url_list[[name]], unzipfile)
        unzip(unzipfile, files = file_list[[name]], exdir = "IECA")
    }
    options(timeout = timeout.prev)
}

# Function to download income data
ine_get <- function(income_url, filename) {
    if (filename %in% dir("INE")) {
        cat("INE income data already available, not downloading\n")
    }
    else {
        timeout.prev <- getOption("timeout")
        options(timeout = 600)
        cat("Downloading income data from INE website\n")
        if (.Platform$OS.type == "windows") {
            download.file(income_url, paste0("INE/", filename), mode = "wb")
        } else {
            download.file(income_url, paste0("INE/", filename))
        }
        options(timeout = timeout.prev)
    }
}

ieca_get(IECA_URL_LIST, IECA_FILE_LIST)
ine_get(INE_INCOME_URL, INE_INCOME_NAME)
