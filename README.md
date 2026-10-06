# 🗺️ UrbanIneq

**A reproducible platform for urban accessibility datasets and socio-spatial inequality analysis in Andalusia**

UrbanIneq is an open-source, containerized platform for the automated construction, processing, analysis, and visualization of urban accessibility datasets for municipalities in Andalusia, Spain. It combines public spatial data, socioeconomic and demographic indicators, and network-based accessibility measures to support reproducible research on socio-spatial inequalities in urban environments.

The platform generates municipality-level datasets at census-section level, computes walking-distance accessibility indicators to Urban Green Spaces (UGS) and Healthcare Facilities (HCF), produces exploratory maps and disparity summaries, and provides analysis-ready outputs through a web interface and API.

UrbanIneq is not a fairness-correction framework. It does not automatically correct or mitigate inequalities. Instead, it provides an open data and accessibility infrastructure that helps researchers and policy makers explore, quantify, and visualize potential accessibility disparities affecting different population groups.

---

## Related publication

This repository accompanies the following publication:

Jiménez-Revuelta, J.C. and Montero, I. and Ramírez-Cobo, P. (2026)  
*UrbanIneq: An Open Framework for Urban Accessibility Datasets with Potential Socio-Spatial Inequality Patterns*.  
Preprint available through Zenodo: [10.5281/zenodo.20443535](https://zenodo.org/records/20443535)

If you use UrbanIneq in your research, please cite the corresponding article.

---

## 🚀 Quick deployment

The recommended way to run UrbanIneq is with Docker Compose from the root directory of the repository.

### Requirements

You need:

- Docker Desktop or Docker Engine with Docker Compose support.
- Enough free disk space for the Andalusia OpenStreetMap extract and the processed OSRM routing dataset.
- The required INE input files in `backend/INE/`:
  - `30824.xlsx`
  - `Censo_2021_Andalucia.xlsx`

IECA spatial data are downloaded automatically when the platform starts.

### First deployment

From the project root, run:

```bash
docker compose up --build
```

The first deployment may take substantially longer than later runs because Docker may need to download base images and OSRM must download and preprocess the Andalusia OpenStreetMap network.

The processed OSRM dataset is stored in the persistent Docker volume:

```text
urbanineq-osrm-data
```

Once this routing dataset has been prepared, subsequent starts reuse it and do not repeat `osrm-extract`, `osrm-partition`, and `osrm-customize`.

### Normal startup

After the images and OSRM data have been prepared, use:

```bash
docker compose up
```

There is normally no need to use `--build` on every startup.

### Application URLs

Once all services are ready:

```text
Web interface:       http://localhost:8081
FastAPI backend:     http://localhost:8080
R/Plumber service:   http://localhost:8000
OSRM routing engine: http://localhost:5001
```

---

## 🧭 What happens when Docker Compose starts?

UrbanIneq starts several coordinated services.

### 1. `data-init`

The data initialization container checks the IECA folders and downloads any missing spatial datasets.

These data include:

- municipal boundaries;
- census-section boundaries;
- urban green areas;
- healthcare facilities;
- demographic spatial indicators.

Existing files are reused, so IECA data are not downloaded again when they are already available.

### 2. `osrm-data-init`

A lightweight Alpine container checks the persistent OSRM volume.

If a prepared routing dataset already exists, the download step is skipped. Otherwise, it downloads:

```text
andalucia-latest.osm.pbf
```

from Geofabrik.

### 3. `andalucia-osrm`

The OSRM service prepares the walking network when necessary by running:

```text
osrm-extract
osrm-partition
osrm-customize
```

The resulting routing files are stored in the persistent `urbanineq-osrm-data` volume.

On later starts, the prepared routing dataset is reused directly.

### 4. `osrm-ready`

A small readiness service waits until OSRM is actually accepting routing requests. This prevents the geospatial backend from starting before the routing engine is ready.

### 5. `r-plumber`

The R/Plumber service performs the geospatial and statistical workflow:

- data loading and harmonization;
- municipality and census-section filtering;
- socioeconomic and demographic integration;
- accessibility calculations;
- cache management;
- disparity summaries;
- map generation;
- output generation.

### 6. `api`

The FastAPI service acts as the orchestration layer between the web client and R/Plumber. It manages:

- municipality lookup;
- job creation and status;
- job history;
- result discovery;
- dataset inspection;
- ZIP downloads;
- file delivery.

### 7. `frontend`

The React frontend provides the user-facing interface for configuring and launching analyses and inspecting the resulting datasets and maps.

---

## 🏗️ System architecture

UrbanIneq uses a containerized service architecture:

```text
┌─────────────────────────────────────────────────────────────┐
│                    Web client                               │
│              React + TypeScript + Vite + Nginx              │
│                         Port 8081                           │
└────────────────────┬────────────────────────────────────────┘
                     │ HTTP/REST
┌────────────────────▼────────────────────────────────────────┐
│              FastAPI Gateway                                │
│     Jobs, municipalities, results, downloads, inspection    │
│                         Port 8080                           │
└────────────────────┬────────────────────────────────────────┘
                     │ HTTP
┌────────────────────▼────────────────────────────────────────┐
│              R/Plumber geospatial service                   │
│  Data integration, accessibility, disparity analysis, maps  │
│                         Port 8000                           │
└────────────────────┬────────────────────────────────────────┘
                     │ HTTP
┌────────────────────▼────────────────────────────────────────┐
│              OSRM routing engine                            │
│            Walking-network distance matrices                │
│                         Port 5001                           │
└─────────────────────────────────────────────────────────────┘
```

Docker Compose also manages the one-shot initialization and readiness services used to prepare IECA and OSRM data.

---

## 📖 Overview

Urban planning increasingly relies on data-driven analysis, but relevant information is often fragmented across different public institutions, spatial formats, temporal references, and administrative scales.

UrbanIneq addresses this problem by providing a reproducible workflow for constructing harmonized urban datasets for Andalusian municipalities. The platform integrates:

- spatial boundaries;
- demographic indicators;
- socioeconomic information;
- urban-service locations;
- walking-network accessibility.

The main unit of analysis is the census section.

The platform focuses on accessibility to:

- Urban Green Spaces (UGS);
- public Healthcare Facilities (HCF);
- public and private Healthcare Facilities.

For each municipality, UrbanIneq calculates walking-network distances between census-section centroids and the selected destination type.

---

## ✨ Main features

UrbanIneq provides:

- automated retrieval and organization of IECA spatial datasets;
- integration of INE socioeconomic and census data;
- integration of IECA demographic indicators;
- municipality search and selection;
- census-section-level data construction;
- accessibility analysis to Urban Green Spaces;
- accessibility analysis to public healthcare facilities;
- accessibility analysis to public and private healthcare facilities;
- walking-distance calculations using OSRM and OpenStreetMap;
- minimum, average, and maximum accessibility indicators;
- exploratory sensitive-attribute disparity analysis;
- map generation for services, accessibility, and socioeconomic attributes;
- downloadable RDS, CSV, GeoJSON, PNG, JSON, and ZIP outputs;
- asynchronous job execution through FastAPI;
- dataset inspection from the web application;
- persistent caching to avoid unnecessary recomputation;
- reproducible deployment with Docker Compose.

---

## 🗺️ Data sources

UrbanIneq uses public data from Andalusia and Spain.

### IECA spatial reference data

The Andalusian Institute of Statistics and Cartography (IECA) provides spatial layers including:

- municipal boundaries;
- census-section boundaries;
- urban green areas;
- primary healthcare centers;
- hospitals and specialized healthcare facilities.

These datasets are automatically downloaded into:

```text
backend/IECA/
```

### IECA demographic indicators

UrbanIneq also uses IECA population indicators, including variables related to age structure and household composition.

The current pipeline uses the `iepabra2021` spatial dataset.

### INE socioeconomic and census data

The platform expects the following INE files:

```text
backend/INE/30824.xlsx
backend/INE/Censo_2021_Andalucia.xlsx
```

These data are used to construct income, population, employment, age, and related census-section attributes.

The files are not automatically recreated by the main pipeline and should be present before running an analysis.

### OpenStreetMap / Geofabrik

UrbanIneq uses the Andalusia OpenStreetMap extract distributed by Geofabrik.

The network is processed by OSRM using the walking profile and is used to calculate network-based distances rather than straight-line Euclidean distances.

---

## 📊 Variables and accessibility indicators

UrbanIneq combines accessibility measurements with seven socioeconomic and demographic attributes:

```text
X_1  Population
X_2  Income
X_3  Proportion of children
X_4  Proportion of elderly population
X_5  Unemployment rate
X_6  Proportion of foreign population
X_7  Loneliness index
```

Accessibility can be calculated for:

- Urban Green Spaces;
- public healthcare facilities;
- public and private healthcare facilities.

For each selected destination type, the user can choose:

- minimum walking distance;
- average walking distance;
- maximum walking distance.

The underlying routing matrix contains the walking-network distance from each census-section centroid to the relevant destinations.

---

## 🔎 Exploratory disparity analysis

UrbanIneq includes an exploratory procedure for comparing accessibility conditions across groups defined by socioeconomic or demographic attributes.

For each candidate attribute:

1. the median of the attribute is calculated;
2. census sections are divided into:
   - values below the median;
   - values equal to or above the median;
3. mean accessibility is calculated for both groups;
4. the absolute and relative difference between group accessibility values is reported.

This analysis is intended for exploratory comparison only.

A large relative difference indicates that the two median-defined groups experience different accessibility conditions, but it should not by itself be interpreted as evidence of causality, discrimination, or a statistically validated fairness violation.

Results should also be interpreted cautiously for municipalities with very few usable census sections, because group averages may then represent only a small number of spatial units.

---

## ⚡ Caching and performance

UrbanIneq includes persistent and in-memory caches to reduce repeated processing.

### Spatial input cache

IECA shapefiles are converted to cached R objects after their first load and are reused while their source files remain unchanged.

### INE workbook cache

The required Excel workbooks are parsed and cached, avoiding repeated full Excel reads during subsequent analyses.

### Municipality base cache

Municipality-level census-section data, socioeconomic attributes, geometries, and centroids are cached independently of the chosen accessibility statistic.

### OSRM routing cache

OSRM distance matrices are cached by:

```text
municipality + destination type + walking profile
```

The matrix is independent of the selected `min`, `mean`, or `max` summary.

This means that once the routing matrix has been generated for a municipality and destination type, switching between minimum, average, and maximum distance does not require repeating the OSRM routing calculation.

### Static map cache

Maps that depend only on relatively stable destination geometries can be reused instead of regenerated for every job.

### Persistent OSRM network

The processed Andalusia routing graph is stored in:

```text
urbanineq-osrm-data
```

Do not remove this volume unless you intentionally want to rebuild the OSRM network.

---

## 🧪 Typical workflow

A typical UrbanIneq analysis follows these steps:

1. Start the platform with Docker Compose.
2. Open `http://localhost:8081`.
3. Select a municipality in Andalusia.
4. Choose the accessibility target:
   - Urban Green Spaces;
   - public healthcare facilities;
   - public and private healthcare facilities.
5. Select the accessibility indicator:
   - minimum distance;
   - average distance;
   - maximum distance.
6. Review the exploratory sensitive-attribute table.
7. Select the socioeconomic or demographic attribute to analyze.
8. Launch the dataset generation job.
9. Wait for the asynchronous job to complete.
10. Inspect maps and generated data.
11. Download the complete result package or individual files.

---

## 📦 Outputs

UrbanIneq stores generated outputs under:

```text
backend/results/
```

Depending on the selected configuration and current pipeline version, generated files can include:

```text
<municipality>-<target>.rds
<municipality>-<target>-raw.csv
<municipality>-<target>-x.csv
<municipality>-<target>-xnorm.csv
<municipality>-<target>-y.csv
<municipality>-<target>-centroids.csv
<municipality>-<target>-bias_table.csv
<municipality>-<target>-metadata.json
<municipality>-<target>-raw.geojson
<municipality>-<target>-centroids.geojson
<municipality>-<target>-municipality.geojson
<municipality>-<target>-greenzones.geojson
<municipality>-<target>-clinics_any.geojson
<municipality>-<target>-clinics_public.geojson
*.png
```

FastAPI can also package the files associated with a job into a downloadable ZIP archive.

The RDS output contains the integrated analysis object and is intended for further work in R.

CSV files provide tabular access to the main matrices and variables.

GeoJSON files expose spatial layers in an interoperable format.

PNG files provide map-based visualization of services, accessibility values, and selected sensitive attributes.

---

## 🧰 Technology stack

UrbanIneq uses:

- Docker Compose for orchestration;
- React and TypeScript for the frontend;
- Vite for frontend builds;
- Nginx for frontend serving;
- FastAPI and Python for API orchestration;
- R and Plumber for the geospatial processing API;
- `sf` for spatial data processing;
- `osrm` for routing requests;
- `ggplot2` for map generation;
- `readxl` for INE workbook ingestion;
- `jsonlite` for JSON input/output;
- OSRM Backend for routing;
- OpenStreetMap data from Geofabrik;
- IECA and INE public datasets.

---

## 📂 Directory structure

A simplified project structure is:

```text
UrbanIneq/
├── docker-compose.yml
├── README.md
├── .gitignore
├── backend/
│   ├── .dockerignore
│   ├── Dockerfile.api
│   ├── Dockerfile.data-init
│   ├── Dockerfile.r
│   ├── main.py
│   ├── plumber.R
│   ├── cache_utils.R
│   ├── datadl.R
│   ├── numdata.R
│   ├── spdata.R
│   ├── outputData.R
│   ├── inequalities.R
│   ├── requirements.txt
│   ├── IECA/
│   ├── INE/
│   ├── results/
│   └── andalucia-osrm/
│       ├── Dockerfile
│       └── prepare-and-run.sh
└── frontend/
    ├── Dockerfile
    ├── package.json
    ├── package-lock.json
    ├── vite.config.ts
    └── src/
```

---

## 🔌 API endpoints

The FastAPI backend provides endpoints for municipality discovery, job management, result retrieval, and downloads.

Common endpoints include:

```text
GET  /health
GET  /options
GET  /municipalities/all
GET  /municipalities?q=<query>
GET  /bias-table/{city_code}
POST /jobs
GET  /jobs
GET  /jobs/{job_id}
GET  /jobs/{job_id}/zip
GET  /jobs/{job_id}/dataset-inspect
GET  /files/{filename}
```

The frontend uses these endpoints internally, but they can also be used for development and integration.

The R/Plumber service exposes the geospatial processing endpoints used by FastAPI, including the analysis execution and RDS inspection operations.

---

## 🛠️ Development workflow

The optimized Docker configuration is intended to avoid full rebuilds during normal development.

### Changes to R code

The backend directory is mounted into the R container.

After editing `plumber.R`, `spdata.R`, `numdata.R`, `cache_utils.R`, or another R script, restart Plumber:

```bash
docker compose restart r-plumber
```

A full image rebuild is normally unnecessary.

### Changes to FastAPI

`main.py` is mounted into the API container.

After modifying it, restart FastAPI:

```bash
docker compose restart api
```

### Changes to frontend code

Frontend source changes require rebuilding the frontend image:

```bash
docker compose build frontend
docker compose up -d frontend
```

### Dependency or Dockerfile changes

Use a targeted build whenever possible:

```bash
docker compose build r-plumber
docker compose build api
docker compose build frontend
```

Use a complete:

```bash
docker compose up --build
```

only when the Docker configuration or multiple image dependencies have changed.

---

## 📁 Data policy

UrbanIneq separates source code from large downloaded, cached, and generated data.

### Downloaded IECA data

```text
backend/IECA/
```

This directory is populated automatically and should normally not be committed to Git.

### INE inputs

```text
backend/INE/
```

The required INE files are expected to be supplied with the project or placed there manually.

### Generated outputs and caches

```text
backend/results/
```

This directory contains generated outputs, the job registry, ZIP cache, processing caches, and other analysis artifacts.

### OSRM routing data

OSRM routing files are stored in the Docker volume:

```text
urbanineq-osrm-data
```

This prevents expensive network preprocessing from being repeated after a normal container shutdown.

---

## 🧹 Cleaning and resetting local data

### Remove generated analysis results

Linux/macOS:

```bash
rm -rf backend/results/*
touch backend/results/.gitkeep
```

Windows PowerShell:

```powershell
Remove-Item .\backend\results\* -Recurse -Force
New-Item -ItemType File -Path .\backend\results\.gitkeep -Force
```

### Force IECA data to be downloaded again

Linux/macOS:

```bash
rm -rf backend/IECA/*
touch backend/IECA/.gitkeep
docker compose up
```

Windows PowerShell:

```powershell
Remove-Item .\backend\IECA\* -Recurse -Force
New-Item -ItemType File -Path .\backend\IECA\.gitkeep -Force
docker compose up
```

### Rebuild the OSRM network from scratch

A normal:

```bash
docker compose down
```

does **not** delete the persistent OSRM volume.

To intentionally remove the prepared OSRM dataset, use:

```bash
docker compose down -v
```

or remove the `urbanineq-osrm-data` volume manually.

This will force the Andalusia OpenStreetMap extract to be downloaded and processed again on the next startup.

---

## 🩺 Troubleshooting

### Plumber is waiting for OSRM

On the first startup, OSRM may take several minutes to prepare the routing network.

The `osrm-ready` service intentionally waits until port `5001` accepts a valid routing request before allowing R/Plumber to start.

Repeated connection-refused messages from the readiness container during `osrm-extract`, `osrm-partition`, or `osrm-customize` are expected until OSRM becomes ready.

### First startup is slow

The first deployment may involve:

- downloading Docker base images;
- downloading IECA datasets;
- downloading the Andalusia OSM extract;
- preprocessing the walking network;
- installing image dependencies.

Later runs should be substantially faster because these resources are cached or persisted.

### Job history contains old analyses

Job information is stored in:

```text
backend/results/jobs_registry.json
```

FastAPI can also infer legacy jobs from files remaining in `backend/results/`.

Clear the generated results directory if a completely clean history is required.

### INE files are missing

The current pipeline expects:

```text
backend/INE/30824.xlsx
backend/INE/Censo_2021_Andalucia.xlsx
```

If either file is missing, the R processing service will not be able to construct the complete municipality dataset.

---

## 🧾 Academic context

UrbanIneq was designed as a reproducible open urban data science infrastructure for accessibility and socio-spatial inequality studies.

It integrates heterogeneous spatial, socioeconomic, demographic, and routing-based information sources into a unified computational workflow.

The framework supports research on accessibility disparities by generating harmonized census-section-level datasets and spatial outputs for municipalities in Andalusia.

Its focus is on reproducible data preparation, accessibility measurement, exploratory visualization, and quantitative comparison of potential inequalities in access to urban services.

UrbanIneq should be understood as a data and accessibility infrastructure. It can support later fairness-oriented or equity-oriented analyses, but it is not itself a fairness-correction or bias-mitigation algorithm.

---

## 📄 Citation

If you use UrbanIneq in academic work, please cite:

> Jiménez-Revuelta, J.C., Montero, I., and Ramírez-Cobo, P. (2026). *UrbanIneq: An Open Framework for Urban Accessibility Datasets with Potential Socio-Spatial Inequality Patterns*. Zenodo. https://doi.org/10.5281/zenodo.20443535

---

## 👥 Authors

UrbanIneq has been developed as part of a research effort on urban accessibility, open urban data, and socio-spatial inequality analysis in Andalusia.

The associated publication is authored by:

- J.C. Jiménez-Revuelta
- I. Montero
- P. Ramírez-Cobo
