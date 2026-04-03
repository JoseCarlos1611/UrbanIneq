# Copyright 2023-2024 Pepa Ramirez-Cobo and Ismael Montero

# Part of the preprocessing process focused on the handling of spatial data
# from IECA. This file is not meant to be ran by itself but rather will run
# when calling `source("preprocess.R")`.

library(osrm)

# Hardcoded file paths
CITY_SHP <- "IECA/13_01_TerminoMunicipal.shp"
TRACT_SHP <- "IECA/13_27_SeccionCensal.shp"
GREENZONE_SHP <- "IECA/07_06_ZonaVerde.shp"
CLINIC_SHP <- "IECA/12_01_CentroSalud.shp"
HOSPITAL_SHP <- "IECA/12_02_Hospital_CAE.shp"

sp.get_city <- function(cities_shp, city_code) {
    spdata <- st_read(cities_shp, quiet = TRUE)
    citydata <- subset(spdata, subset = (cod_mun == city_code))
    #rownames(citydata) <- citydata$cod_mun
    return(citydata)
}

sp.get_tracts <- function(tracts_shp, city_code) {
    spdata <- st_read(tracts_shp, quiet = TRUE)
    tractdata <- subset(spdata, subset = (cod_mun == city_code) & !(codigo %in% TRACT_EXCLUDE))
    tractdata <- tractdata[order(tractdata$codigo), ]
    rownames(tractdata) <- tractdata$codigo
    return(tractdata)
}

sp.green_zones <- function(greenzone_shp, citydata) {
    spdata <- st_read(greenzone_shp, quiet = TRUE)
    gzdata <- subset(spdata, subset = (tipo == "Parque"))
    return(gzdata[st_contains(citydata, gzdata)[[1]], ])
}

sp.clinics <- function(clinic_shp, hospital_shp, city_code, tractdata = NULL) {
    clinic.data <- subset(st_read(clinic_shp, quiet = TRUE),
                         subset = cod_mun == city_code,
                         select = cod_mun)
    clinic.data$sistema_sa <- "Público"
    hospital.data <- subset(st_read(hospital_shp, quiet = TRUE),
                           subset = cod_mun == city_code,
                           select = c(cod_mun, sistema_sa))
    clinic.any <- rbind(clinic.data, hospital.data)
    if (!is.null(tractdata)) {
        clinic.any <- clinic.any[st_contains(tractdata, clinic.any)[[1]], ]
    }
    clinic.public <- subset(clinic.any,
                            subset = sistema_sa == "Público")
    return(list(any = clinic.any,
                public = clinic.public))
}

sp.centroid_fix <- function(tract.data, tract_fix = NULL) {
    if (!is.null(tract_fix)) {
        tract.names <- rownames(tract.data)
        if (any((names(tract_fix) %in% tract.names))) {
            for (name in names(tract_fix)) {
                w <- which(tract.names == name)
                centroid.new <- tract_fix[[name]]
                tract.data$geometry[w] <- st_point(centroid.new)
            }
        }
    }
    return(tract.data)
}

# get the specified distance type from every tract
# to every location, i.e. parks or hospitals
sp.get_dists <- function(tractdata, location.data, tract_fix,
                         dist.type = c("mean", "min", "max")) {
    dist.type <- match.arg(dist.type)
    points.from <- sp.centroid_fix(st_centroid(tractdata), tract_fix)
    points.to <- st_centroid(location.data)
    dists.all <- osrmTable(src = points.from,
                           dst = points.to,
                           measure = "distance",
                           osrm.server = OSRM_URL,
                           osrm.profile = "foot")$distances
    dists <- as.data.frame(as.matrix(apply(dists.all, 1, dist.type)))
    colnames(dists) <- "y"
    #return(dists)
    return(list(y = dists, centroids = points.from))
}

sp.citydata <- sp.get_city(CITY_SHP, CITY_CODE)
sp.tractdata <- sp.get_tracts(TRACT_SHP, CITY_CODE)
if (is.null(TRACT_EXCLUDE)) {
    sp.gzdata <- sp.green_zones(GREENZONE_SHP, sp.citydata)
    sp.clinicdata <- sp.clinics(CLINIC_SHP, HOSPITAL_SHP, CITY_CODE)
} else {
    sp.tractdata_r <- st_union(sp.tractdata)
    sp.gzdata <- sp.green_zones(GREENZONE_SHP, sp.tractdata_r)
    sp.clinicdata <- sp.clinics(CLINIC_SHP, HOSPITAL_SHP, CITY_CODE, sp.tractdata_r)
}
sp.clinic_any <- sp.clinicdata$any
sp.clinic_public <- sp.clinicdata$public
location.data <- list(parks = sp.gzdata,
                      clinics_public = sp.clinic_public,
                      clinics_any = sp.clinic_any)[[LOCATIONS]]
sp.dists <- sp.get_dists(sp.tractdata, location.data, TRACT_FIX, DIST_TYPE)
