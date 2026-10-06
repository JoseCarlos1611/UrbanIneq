# Copyright 2023-2024 Pepa Ramirez-Cobo and Ismael Montero
# Optimized spatial helpers. The expensive OSRM matrix is now exposed separately
# from min/mean/max reduction so it can be cached independently.

library(osrm)

CITY_SHP <- "IECA/13_01_TerminoMunicipal.shp"
TRACT_SHP <- "IECA/13_27_SeccionCensal.shp"
GREENZONE_SHP <- "IECA/07_06_ZonaVerde.shp"
CLINIC_SHP <- "IECA/12_01_CentroSalud.shp"
HOSPITAL_SHP <- "IECA/12_02_Hospital_CAE.shp"

sp.read_or_use <- function(x) {
    if (inherits(x, "sf") || inherits(x, "sfc")) return(x)
    st_read(x, quiet = TRUE)
}

sp.get_city <- function(cities_shp, city_code) {
    spdata <- sp.read_or_use(cities_shp)
    subset(spdata, subset = (cod_mun == city_code))
}

sp.get_tracts <- function(tracts_shp, city_code, tract_exclude = NULL) {
    spdata <- sp.read_or_use(tracts_shp)
    tractdata <- subset(spdata, subset = (cod_mun == city_code) & !(codigo %in% tract_exclude))
    tractdata <- tractdata[order(tractdata$codigo), ]
    rownames(tractdata) <- tractdata$codigo
    tractdata
}

sp.green_zones <- function(greenzone_shp, citydata) {
    spdata <- sp.read_or_use(greenzone_shp)
    gzdata <- subset(spdata, subset = (tipo == "Parque"))
    gzdata[st_contains(citydata, gzdata)[[1]], ]
}

sp.clinics <- function(clinic_shp, hospital_shp, city_code, tractdata = NULL) {
    clinic.data <- subset(sp.read_or_use(clinic_shp),
                          subset = cod_mun == city_code,
                          select = cod_mun)
    clinic.data$sistema_sa <- "Público"
    hospital.data <- subset(sp.read_or_use(hospital_shp),
                            subset = cod_mun == city_code,
                            select = c(cod_mun, sistema_sa))
    clinic.any <- rbind(clinic.data, hospital.data)
    if (!is.null(tractdata)) clinic.any <- clinic.any[st_contains(tractdata, clinic.any)[[1]], ]
    clinic.public <- subset(clinic.any, subset = sistema_sa == "Público")
    list(any = clinic.any, public = clinic.public)
}

sp.centroid_fix <- function(tract.data, tract_fix = NULL) {
    if (!is.null(tract_fix)) {
        tract.names <- rownames(tract.data)
        if (any(names(tract_fix) %in% tract.names)) {
            for (name in names(tract_fix)) {
                w <- which(tract.names == name)
                if (length(w) > 0) tract.data$geometry[w] <- st_point(tract_fix[[name]])
            }
        }
    }
    tract.data
}

sp.osrm_matrix <- function(tractdata, location.data, tract_fix = NULL, osrm_url = OSRM_URL) {
    if (is.null(location.data) || nrow(location.data) < 1) stop("No routing destinations are available")
    points.from <- sp.centroid_fix(st_centroid(tractdata), tract_fix)
    points.to <- st_centroid(location.data)
    dists.all <- osrmTable(
        src = points.from,
        dst = points.to,
        measure = "distance",
        osrm.server = osrm_url,
        osrm.profile = "foot"
    )$distances
    list(distances = as.matrix(dists.all), centroids = points.from)
}

sp.reduce_dists <- function(dists.all, dist.type = c("mean", "min", "max")) {
    dist.type <- match.arg(dist.type)
    values <- switch(
        dist.type,
        mean = rowMeans(dists.all),
        min = apply(dists.all, 1, min),
        max = apply(dists.all, 1, max)
    )
    dists <- data.frame(y = as.numeric(values))
    rownames(dists) <- rownames(dists.all)
    dists
}

# Backward-compatible wrapper.
sp.get_dists <- function(tractdata, location.data, tract_fix,
                         dist.type = c("mean", "min", "max")) {
    routing <- sp.osrm_matrix(tractdata, location.data, tract_fix, OSRM_URL)
    list(y = sp.reduce_dists(routing$distances, dist.type), centroids = routing$centroids)
}

# Legacy side-effect mode for outputData.R. The web/Plumber pipeline does not
# execute this block, so it can preserve the original CLI behavior (including
# loading all map layers) without affecting the optimized request path.
if (exists("CITY_CODE", inherits = FALSE) && exists("LOCATIONS", inherits = FALSE)) {
    sp.citydata <- sp.get_city(CITY_SHP, CITY_CODE)
    sp.tractdata <- sp.get_tracts(TRACT_SHP, CITY_CODE, TRACT_EXCLUDE)
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
    location.data <- list(
        parks = sp.gzdata,
        clinics_public = sp.clinic_public,
        clinics_any = sp.clinic_any
    )[[LOCATIONS]]
    sp.dists <- sp.get_dists(sp.tractdata, location.data, TRACT_FIX, DIST_TYPE)
}
