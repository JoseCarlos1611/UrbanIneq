# Unfair urban data
A set of R routines automating the download and processing of spatial datasets for the Spanish region of Andalusia.

## Sourcing
The data is obtained in unprocessed form from the following sources:
- Andalusian Institute of Statistics and Cartography (IECA)
  - [Spatial Reference Data of Andalusia (DERA)](https://www.juntadeandalucia.es/institutodeestadisticaycartografia/dega/datos-espaciales-de-referencia-de-andalucia-dera)
  - [Statistical Indicators of Andalusia's Population Based on Administrative Records (IEPABRA)](https://www.juntadeandalucia.es/institutodeestadisticaycartografia/dega/estadisticas-de-poblacion-de-andalucia-basadas-en-registros-administrativos-epabra)
- Spain's National Institute of Statistics (INE)
  - [Household Income Distribution Atlas (ADRH)](https://www.ine.es/componentes\_inebase/ADRH\_total\_nacional.htm)
  - [Population and Housing Census](https://www.ine.es/censos2021/)
- Geofabrik: [Openstreetmap data for the Andalusian region](https://download.geofabrik.de/europe/spain/andalucia.html)

## Requirements
A working **R** (>=4.0) installation, with the packages:
- osrm
- readxl
- sf
- ggplot2

A **docker** installation with a [osrm-backend](https://github.com/Project-OSRM/osrm-backend) container running in port **5001**, with maps for, at least, the Andalusian region. A *Dockerfile* simplifying the installation and deployment of a container for use with this project is provided in the `andalucia-osrm` folder, this can be done as:
```
cd andalucia-osrm
docker build --network host -t andalucia-osrm .
docker run --name andalucia-osrm -t -p 5001:5001 andalucia-osrm
```
And starting our container as:
```
docker start andalucia-osrm
```
When done, we can stop it in the same way:
```
docker stop andalucia-osrm
```

## Running
The `outputData.R` file wraps all the functions in the other R files and presents a user-friendly assistant. This can be run in R with `source("outputData.R")`. A Windows-compatible `outputData.bat` executable is provided for ease of use, if needed.
