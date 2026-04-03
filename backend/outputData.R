# Copyright 2023-2024 Pepa Ramirez-Cobo and Ismael Montero
options(warn = -1)

# This is the file to run (using source()) in order to get
# a working dataset for any Andalusian town or city. Also works
# as a standalone script with Rscript as well as with the
# provided .bat file

# The 2021 census file for the Andalusian region is
# provided unmodified as generated from INE's website
# https://www.ine.es/Censo2021
# This process relies on manually selecting and downloading
# the data via the website's form hence why it's included as an excel file
CENSUS_FILE <- "INE/Censo_2021_Andalucia.xlsx"
INCOME_FILE <- "INE/30824.xlsx"
IECA_SHP_FILE <- "IECA/iepabra2021.shp"
OSRM_URL1 <- "http://127.0.0.1:5001/" # local docker instance
OSRM_URL2 <- "http://192.168.99.100:5001/" # local docker vm instance

# When needed, modify this variable to define new centroids for the
# census tracts needing it.
TRACT_FIX <- NULL
#TRACT_FIX <- list("4109111001" = c(233782.88419027737, 4139657.6115614707),
#                  "4109107013" = c(235737.22084712566, 4145047.400172972),
#                  "4109107022" = c(239105.78505961807, 4147356.036047681),
#                  "4109107023" = c(242365.99078879764, 4146947.5452778214),
#                  "4109109069" = c(242164.74552233698, 4144100.248191675),
#                  "4109109018" = c(242929.53720470652, 4141649.6993550234),
#                  "4109105051" = c(238157.231, 4139082.873))

# Also possible to edit the exclude variable if we want to keep tracts
# out of the process. Always keep a NULL value else script will crash
# at some point
TRACT_EXCLUDE <- NULL
#TRACT_EXCLUDE <- c("1102010001", "1102010002", "1102004003",
#                   "1102008001", "1102009002", "1102009004",
#                   "1102009005", "1102009006", "1102009007",
#                   "1102009008", "1102009009", "1102009010",
#                   "1102009011", "1102009012", "1102009013",
#                   "1102009014", "1102010003", "1102010004",
#                   "1101210012")

library(readxl)
library(sf)
library(ggplot2)

source("datadl.R")
source("numdata.R")

# Simple check for available connections
url_check <- function(endpoint) {
    check <- try({ curlGetHeaders(endpoint) }, silent = TRUE)
    if (inherits(check, "try-error")) return(FALSE)
    else return(TRUE)
}

## Get options from user input
# Allow behavior to change depending on where this is running
sourced <- interactive()

# City code
CITY_CODE <- NULL
while (is.null(CITY_CODE)) {
    cat("\nPlease choose the municipality you are interested in: ")
    if (sourced) {
        city_prompt <- readline()
    } else city_prompt <- readLines("stdin", n = 1)
    if (city_prompt == "") {
        CITY_CODE <- NULL
    } else CITY_CODE <- cityname_match(city_prompt, INCOME_FILE)
}

# Locations
location_options <- c("UGS", "HCF (public)", "HCF (all public and private)")
location_seq <- seq(length(location_options))
LOCATIONS <- NULL
while (is.null(LOCATIONS)) {
    #cat("\nWhat locations to use as reference?\n")
    cat("\nAccessibility is going to be measured in terms of:\n")
    for (i in 1:length(location_options)) {
        cat(paste0(i, ":"), location_options[i], "\n")
    }
    if (sourced) {
        location_choice <- as.numeric(readline())
    } else {
        location_choice <- as.numeric(scan("stdin", character(), n = 1, quiet = TRUE))
    }
    if (!(location_choice %in% location_seq)) {
        LOCATIONS <- NULL
    } else {
        LOCATIONS <- c("parks", "clinics_public", "clinics_any")[location_choice]
    }
}
locations_short <- list(parks = "ugs",
                        clinics_public = "hcf_public",
                        clinics_any = "hcf")

# OSRM check
osrm_available <- FALSE
osrm1_available <- url_check(OSRM_URL1)
if (osrm1_available) {
    osrm_available <- TRUE
    OSRM_URL <- OSRM_URL1
} else {
    osrm2_available <- url_check(OSRM_URL2)
    if (osrm2_available) {
        osrm_available <- TRUE
        OSRM_URL <- OSRM_URL2
    }
}

if (osrm_available) {
    library(osrm)
} else {
    err_str <- paste("No OSRM instance was found locally, please ensure",
                     "it is running. This routine will check on the following",
                     "URLs:\n", OSRM_URL1, "\n", OSRM_URL2)
    stop(err_str)
}

# Distance type
dist_options <- c("Average distance (default)", "Minimum distance", "Maximum distance")
dist_seq <- seq(length(dist_options))
DIST_TYPE <- NULL
while (is.null(DIST_TYPE)) {
    cat("\nWhat type of distance should we use?\n")
    for (i in 1:length(dist_options)) {
        cat(paste0(i, ":"), dist_options[i], "\n")
    }
    if (sourced) {
        dist_choice <- as.numeric(readline())
    } else {
        dist_choice <- as.numeric(scan("stdin", character(), n = 1, quiet = TRUE))
    }
    if (!(dist_choice %in% dist_seq)) DIST_TYPE <- NULL
    else DIST_TYPE <- c("mean", "min", "max")[dist_choice]
}
DIST_NAME <- c("Average", "Min", "Max")[dist_choice]

source("spdata.R")

HEADERS <- list()
HEADERS[["orig"]] <- c("Sección",
                       "Personas",
                       "Porcentaje de personas de más de 64 años",
                       "Porcentaje de población extranjera",
                       "Porcentaje de población parada sobre población activa")
HEADERS[["repl"]] <- c("ct_code",
                       "total",
                       "elderly",
                       "foreigner",
                       "unemployed")
VARS <- list()
VARS[["orig"]] <- c("total",
                    "mean_income",
                    "underage",
                    "elderly",
                    "unemployed",
                    "foreigner",
                    "lonely")
VARS[["repl"]] <- c("x1",
                    "x2",
                    "x3",
                    "x4",
                    "x5",
                    "x6",
                    "x7")

# Retrieve IEPABRA's data for the underage (X3) and loneliness (X7) variables
ieca.get_data <- function(ct_code, shpfile) {
    ieca_data <- st_read(shpfile, quiet = TRUE)
    ieca_data <- st_drop_geometry(subset(ieca_data,
                                         subset = (CUMUN == CITY_CODE),
                                         select = c(CUSEC, I6, I16)))
    colnames(ieca_data) <- c("ct_code", "lonely", "underage")
    return(ieca_data)
}

# Merge X and Y data
ct.get_x <- function() {
    income_data <- ct.get_income(CITY_CODE, INCOME_FILE)
    census_data <- ct.get_census_info(CITY_CODE, HEADERS, CENSUS_FILE)
    ieca_data <- ieca.get_data(CITY_CODE, IECA_SHP_FILE)
    all_data1 <- merge(x = income_data,
                       y = census_data,
                       by = "ct_code")
    all_data2 <- merge(x = all_data1,
                       y = ieca_data,
                       by = "ct_code")
    ct_codes <- all_data2$ct_code
# reorder and rename columns
    all_data2 <- all_data2[, VARS[["orig"]]]
    colnames(all_data2) <- VARS[["repl"]]
    rownames(all_data2) <- ct_codes
    return(all_data2)
}

# Once all input is available, generate the requested data
# Any sp.* variable comes from "spdata.R"
x <- ct.get_x()
y <- sp.dists$y
centroids <- sp.dists$centroids
xy <- merge(x, y, by = "row.names")
rownames(xy) <- xy$Row.names
xy <- subset(xy, select = -Row.names)
raw <- st_as_sf(merge(xy, sp.tractdata, by = "row.names"))
raw.rownames <- raw$Row.names
raw <- subset(raw, select = c(VARS[["repl"]], "y"))
rownames(raw) <- raw.rownames
x <- cbind(1, st_drop_geometry(raw[, 1:7]))
xnorm <- cbind(1, scale(st_drop_geometry(raw[, 1:7])))
colnames(x)[1] <- colnames(xnorm)[1] <- "Intercept"
y <- matrix(st_drop_geometry(raw[, 8])$y)
rownames(y) <- raw.rownames
centroids <- st_as_sf(merge(xy, centroids, by = "row.names"))
#centroids <- subset(centroids, select = c(municipio, geometry))
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
if (!is.null(TRACT_FIX)) {
    citydata[["centroids_orig"]] <- st_coordinates(
                                        st_centroid(
                                            citydata[["geometry"]]))
}
#citydata[["d"]] <- matrix(st_distance(st_centroid(citydata[["geometry"]])),
#                          nrow(x), nrow(x))
citydata[["d"]] <- as.matrix(dist(centroids))
citydata[["gz"]] <- sp.gzdata
citydata[["clinics_any"]] <- sp.clinic_any
citydata[["clinics_public"]] <- sp.clinic_public
citydata[["name"]] <- sp.citydata$nombre
citydata[["varname"]] <- iconv(gsub(" ", "", tolower(sp.citydata$nombre)), to = "ASCII//TRANSLIT")
eval(parse(text = paste0(citydata[["varname"]], " <- citydata")))

filenames <- list()
filenames['rds'] <- paste0("results/", CITY_CODE, "-",
                           locations_short[LOCATIONS], ".rds")
filenames['gz'] <- paste0("results/", CITY_CODE, "_greenzones.png")
filenames['clinic_any'] <- paste0("results/", CITY_CODE, "_clinics_any.png")
filenames['clinic_public'] <- paste0("results/", CITY_CODE, "_clinics_public.png")
filenames['y'] <- paste0("results/", CITY_CODE, "-",
                         locations_short[LOCATIONS], "_y.png")
#filenames.total_ppl <- paste0("results/", CITY_CODE, "_total_ppl.png")

# Table: select a sensitive variable
source("inequalities.R")
svar.name <- paste0("x", biasvar)
filenames['svar'] <- paste0("results/", CITY_CODE, "_", svar.name, ".png")

# Export as rds
eval(parse(text = paste0("saveRDS(", citydata[["varname"]], ", file = filenames$rds)")))

# Generate plots
# Green zones (also referred to as UGS)
fplot.gz <- ggplot() +
    geom_sf(data = citydata$geometry, fill = NA) +
    geom_sf(data = citydata$gz, fill = "green2") +
    ggtitle(paste0("Green zones map for ",
                   citydata[["name"]],
                   " (code ", CITY_CODE, ")")) +
    theme_void()
suppressMessages(ggsave(filenames$gz, plot = fplot.gz))

# All clinics
fplot.clinic_any <- ggplot() +
    geom_sf(data = citydata$geometry, fill = NA) +
    geom_sf(data = citydata$clinics_any, color = "orange") +
    ggtitle(paste0("All clinics map for ",
                   citydata[["name"]],
                   " (code ", CITY_CODE, ")")) +
    theme_void()
suppressMessages(ggsave(filenames$clinic_any, plot = fplot.clinic_any))

# Public clinics
fplot.clinic_public <- ggplot() +
    geom_sf(data = citydata$geometry, fill = NA) +
    geom_sf(data = citydata$clinics_public, color = "red") +
    ggtitle(paste0("Public clinics map for ",
                   citydata[["name"]],
                   " (code ", CITY_CODE, ")"))+
    theme_void()
suppressMessages(ggsave(filenames$clinic_public, plot = fplot.clinic_public))

# Y plot
fplot.y <- ggplot() +
    geom_sf(data = citydata$geometry, aes(fill = citydata$y)) +
    scale_fill_steps(name = paste(DIST_NAME, "distance\n(meters)"),
                     n.breaks = 8,
                     low = "white",
                     high = "red") +
    ggtitle(paste0("Y values for ",
                   citydata[["name"]],
                   " (code ", CITY_CODE, ")")) + theme_void()
suppressMessages(ggsave(filenames$y, plot = fplot.y))

# Chosen sensitive variable
fplot.svar <- ggplot() +
    geom_sf(data = citydata$geometry, aes(fill = citydata$x[, biasvar + 1])) +
    scale_fill_steps(name = "",
                     n.breaks = 8,
                     low = "white",
                     high = "red") +
    ggtitle(paste0(svar.name, " values for ", citydata[["name"]],
                   " (code ", CITY_CODE, ")")) + theme_void()
suppressMessages(ggsave(filenames$svar, plot = fplot.svar))

# Map with census tract codes
# uncomment if needed
#ggplot() +
#    geom_sf(data = citydata$geometry) +
#    geom_label(aes(x = citydata$centroids[,1],
#                   y = citydata$centroids[,2],
#                   label = rownames(citydata$x)),
#               data = citydata$geometry)
options(warn = 0)

# Inform user when done
cat(paste0("\n\nThe generated data can be found at ", file.path(getwd(), filenames['rds']), "\n"))
cat("Maps are available at:\n")
filenames$rds <- NULL
for (filename in filenames) cat(file.path(getwd(), filename), "\n")
cat("\nThe preprocessing routine is done!\n")
