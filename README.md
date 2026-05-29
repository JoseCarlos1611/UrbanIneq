# 🗺️ UrbanIneq

**A reproducible platform for urban accessibility datasets and socio-spatial inequality analysis in Andalusia**

UrbanIneq is an open-source, containerized platform for the automated construction, processing, analysis, and visualization of urban accessibility datasets for municipalities in Andalusia, Spain. It combines public spatial data, socioeconomic indicators, demographic information, and network-based accessibility measures to support research on socio-spatial inequalities in urban environments.

The platform provides a complete workflow for generating municipality-level datasets at census-section level, computing walking-distance accessibility indicators to Urban Green Spaces (UGS) and Healthcare Facilities (HCF), producing exploratory maps, and downloading analysis-ready outputs.

UrbanIneq is not a fairness-correction framework. It does not automatically correct or mitigate inequalities. Instead, it provides an open data and accessibility infrastructure that helps researchers and policy makers explore, quantify, and visualize potential accessibility disparities affecting different population groups.

## Related publication

This repository accompanies the following publication:

Jiménez-Revuelta, J.C. and Montero, I. and Ramírez-Cobo, P. (2026)
*UrbanIneq: An Open Framework for Urban Accessibility Datasets with Potential Socio-Spatial Inequality Patterns*.
Preprint available through Zenodo: [10.5281/zenodo.20443535](https://zenodo.org/records/20443535)

If you use UrbanIneq in your research, please cite the corresponding article.

## 🚀 Quick deployment

The recommended way to run UrbanIneq is with Docker Compose.

From the root folder of the repository, run:

```bash
docker compose up --build
```

Once all services are running, open the web interface at:

```text
http://localhost:8081
```

The FastAPI backend will be available at:

```text
http://localhost:8080
```

The R/Plumber geospatial service will be available internally at:

```text
http://localhost:8000
```

The OSRM routing engine will run at:

```text
http://localhost:5001
```

---

## 🧭 What happens when Docker Compose starts?

When running:

```bash
docker compose up --build
```

UrbanIneq starts several coordinated services.

First, the data initialization service prepares the required data folders and downloads the IECA spatial datasets automatically. These include administrative boundaries, census sections, urban green areas, healthcare facilities, and demographic spatial layers. The IECA data are not stored in the GitHub repository because they are large and can be downloaded from public sources.

Second, the OSRM service downloads and preprocesses the OpenStreetMap network for Andalusia. This service is used to calculate walking-network distances between census-section centroids and urban services.

Third, the R/Plumber service starts. This service performs the geospatial processing workflow: data integration, census-section filtering, accessibility computation, dataset generation, disparity summaries, and map production.

Fourth, the FastAPI service starts. This service acts as the orchestration layer between the frontend and the R/Plumber processing service. It manages municipalities, jobs, job history, result files, ZIP downloads, and API responses.

Finally, the React frontend starts. This is the user-facing web interface where users can select municipalities, choose accessibility targets, configure distance indicators, launch analyses, inspect outputs, and download generated results.

---

## 📁 Data policy

UrbanIneq separates source code from large generated or downloaded data.

The following folders are intentionally not fully versioned in Git:

```text
backend/IECA/
backend/results/
```

The `backend/IECA/` folder is filled automatically when Docker Compose starts. It contains spatial data downloaded from IECA, including shapefiles and related files.

The `backend/results/` folder contains generated outputs such as `.rds`, `.png`, `.zip`, and job registry files. These are produced when users run analyses and should not be committed to GitHub.

The `backend/INE/` folder is kept under version control by default. This is useful when the INE files required by the R pipeline are relatively small, stable, or manually curated. Depending on the current version of the pipeline, this folder should contain the INE socioeconomic and census files expected by the R scripts.

A typical structure is:

```text
backend/
├── IECA/
│   └── .gitkeep
├── INE/
│   ├── 30824.xlsx
│   └── Censo_2021_Andalucia.xlsx
├── results/
│   └── .gitkeep
```

If the project is adapted to use CSV files instead of Excel files, the corresponding paths in the R scripts should be updated accordingly.

---

## ✅ Recommended `.gitignore`

The repository should avoid committing downloaded IECA data, generated results, OSRM files, and local temporary files.

A recommended `.gitignore` is:

```gitignore
# IECA is downloaded automatically by the Docker data-init service
backend/IECA/*
!backend/IECA/.gitkeep

# Generated results
backend/results/*
!backend/results/.gitkeep
results/*
!results/.gitkeep

# OSRM / OpenStreetMap heavy generated/downloaded files
*.osm.pbf
*.osrm
*.osrm.*

# Python
__pycache__/
*.pyc
.venv/
venv/
.env

# R
.Rhistory
.RData
.Rproj.user/

# Node / frontend
node_modules/
frontend/node_modules/
frontend/dist/
.vite/

# System/editor temporary files
.DS_Store
Thumbs.db
*~
*.swp
*.swo
```

If files from `backend/IECA/` were accidentally committed before adding this `.gitignore`, remove them from Git tracking with:

```bash
git rm -r --cached backend/IECA
mkdir -p backend/IECA
touch backend/IECA/.gitkeep
git add .gitignore backend/IECA/.gitkeep
git commit -m "Ignore downloaded IECA data"
```

---

## 🏗️ System architecture

UrbanIneq follows a containerized microservices architecture composed of four main services:

```text
┌─────────────────────────────────────────────────────────────┐
│                    Web client                               │
│              React + TypeScript + Vite + Nginx              │
│                         Port 8081                           │
└────────────────────┬────────────────────────────────────────┘
                     │ HTTP/REST
┌────────────────────▼────────────────────────────────────────┐
│              FastAPI Gateway                                │
│       Job management, municipalities, file downloads         │
│                         Port 8080                           │
└────────────────────┬────────────────────────────────────────┘
                     │ HTTP calls
┌────────────────────▼────────────────────────────────────────┐
│              R/Plumber geospatial service                   │
│       Data retrieval, preprocessing, accessibility analysis  │
│                         Port 8000                           │
└────────────────────┬────────────────────────────────────────┘
                     │ HTTP
┌────────────────────▼────────────────────────────────────────┐
│              OSRM routing engine                            │
│          Walking-network distance calculations              │
│                         Port 5001                           │
└─────────────────────────────────────────────────────────────┘
```

The frontend provides the interactive user interface. FastAPI coordinates jobs and communication between services. R/Plumber performs the geospatial and statistical processing. OSRM computes walking-network distances over OpenStreetMap data.

---

## 📖 Overview

Urban planning increasingly relies on data-driven approaches. However, urban datasets often remain fragmented across different institutional repositories, spatial formats, temporal references, and administrative scales. This fragmentation makes reproducible analysis of urban accessibility and socio-spatial inequality difficult.

UrbanIneq addresses this problem by providing a reproducible workflow for constructing harmonized urban datasets across Andalusian municipalities. It integrates spatial, socioeconomic, demographic, and routing-network data, and generates accessibility indicators at census-section level.

The platform focuses on two types of urban services:

* Urban Green Spaces (UGS)
* Healthcare Facilities (HCF)

For each municipality, UrbanIneq computes walking-distance accessibility indicators between census-section centroids and selected urban services. These indicators can then be analyzed together with socioeconomic and demographic variables to explore potential accessibility disparities among population groups.

---

## ✨ Main features

UrbanIneq provides:

* Automated retrieval and organization of IECA spatial datasets.
* Integration of socioeconomic and demographic information.
* Accessibility analysis to Urban Green Spaces and Healthcare Facilities.
* Walking-distance calculations using OSRM and OpenStreetMap network data.
* Census-section-level urban datasets.
* Interactive web interface for municipality selection and analysis configuration.
* FastAPI backend for job orchestration and result delivery.
* R/Plumber backend for geospatial processing and dataset generation.
* Downloadable results in formats such as RDS, PNG, and ZIP.
* Reproducible deployment with Docker Compose.

---

## 🗺️ Data sources

UrbanIneq uses public data sources for Andalusia and Spain.

### IECA Spatial Reference Data

The Andalusian Institute of Statistics and Cartography provides spatial reference datasets used by UrbanIneq, including:

* Municipal boundaries.
* Census-section boundaries.
* Urban green areas.
* Primary healthcare centers.
* Hospitals and specialized healthcare facilities.

These datasets are downloaded automatically into:

```text
backend/IECA/
```

### IECA demographic indicators

UrbanIneq uses demographic and socioeconomic spatial indicators from IECA, including information related to age structure, household composition, and other census-section-level characteristics.

### INE socioeconomic and census data

The platform uses INE data for income, employment, census, and population-related variables. Depending on the current version of the project, these files should be placed in:

```text
backend/INE/
```

By default, this folder is kept under Git version control so that required INE files can be included in the repository if they are not too large.

### OpenStreetMap / Geofabrik

UrbanIneq uses OpenStreetMap network data for Andalusia, obtained from Geofabrik, to build the OSRM routing engine. This allows the platform to compute walking-network distances rather than simple Euclidean distances.

---

## 📊 Variables and accessibility indicators

UrbanIneq combines accessibility indicators with socioeconomic and demographic variables.

The socioeconomic attributes include variables such as:

* Total population.
* Income.
* Underage population.
* Elderly population.
* Unemployment.
* Foreign population.
* Loneliness index.

The accessibility indicators are computed for:

* Urban Green Spaces.
* Public healthcare facilities.
* Public and private healthcare facilities.

For each selected service type, the system can compute:

* Minimum walking distance.
* Average walking distance.
* Maximum walking distance.

These distances are calculated over the OpenStreetMap walking network using OSRM.

---

## 🔎 Exploratory disparity analysis

UrbanIneq includes exploratory tools for comparing accessibility conditions across population groups.

For a selected socioeconomic variable, census sections can be divided according to the median value of that variable. The platform then compares accessibility indicators between sections below and above the median. This allows users to explore whether certain population groups may experience worse accessibility to urban services.

This should be interpreted as an exploratory disparity analysis. UrbanIneq helps identify potential socio-spatial inequality patterns, but it does not automatically establish causality, prescribe interventions, or correct algorithmic bias.

---

## 🧪 Typical workflow

A typical UrbanIneq analysis follows these steps:

1. Start the platform with Docker Compose.
2. Open the frontend at `http://localhost:8081`.
3. Select a municipality in Andalusia.
4. Choose the accessibility target:

   * Urban Green Spaces.
   * Public healthcare facilities.
   * Public and private healthcare facilities.
5. Select the distance indicator:

   * Minimum distance.
   * Average distance.
   * Maximum distance.
6. Select a socioeconomic variable for exploratory comparison.
7. Launch the job.
8. Wait for the job to finish.
9. Inspect maps, generated files, and downloadable results.
10. Download the generated ZIP or RDS dataset for further analysis.

---

## 📦 Outputs

UrbanIneq generates several types of outputs depending on the selected municipality and configuration.

Typical outputs include:

```text
backend/results/
├── <job_id>/
│   ├── dataset.rds
│   ├── accessibility_maps.png
│   ├── socioeconomic_maps.png
│   └── metadata.json
```

The exact filenames may vary depending on the job configuration and version of the pipeline.

The RDS dataset is intended for further statistical and spatial analysis in R. PNG files provide map-based visualizations. ZIP files are generated by FastAPI to make it easier to download all results from a job.

---

## 🧰 Technology stack

UrbanIneq uses:

* Docker Compose for reproducible deployment.
* React, TypeScript, Vite, and Nginx for the frontend.
* FastAPI and Python for the API gateway.
* R, sf, osrm, ggplot2, readxl, jsonlite, and Plumber for geospatial processing.
* OSRM for routing.
* OpenStreetMap network data from Geofabrik.
* IECA and INE public datasets.

---

## 📂 Directory structure

A simplified project structure is:

```text
UrbanIneq/
├── docker-compose.yml
├── README.md
├── .gitignore
├── backend/
│   ├── Dockerfile.api
│   ├── Dockerfile.r
│   ├── main.py
│   ├── plumber.R
│   ├── datadl.R
│   ├── numdata.R
│   ├── spdata.R
│   ├── outputData.R
│   ├── inequalities.R
│   ├── requirements.txt
│   ├── IECA/
│   │   └── .gitkeep
│   ├── INE/
│   │   └── required INE files
│   ├── results/
│   │   └── .gitkeep
│   └── andalucia-osrm/
│       └── Dockerfile
└── frontend/
    ├── Dockerfile
    ├── package.json
    ├── vite.config.ts
    └── src/
```

---

## 🔌 API endpoints

The FastAPI backend provides endpoints for municipality search, job management, result retrieval, and downloads.

Common endpoints include:

```text
GET  /health
GET  /options
GET  /municipalities/all
GET  /municipalities?q=<query>
POST /jobs
GET  /jobs
GET  /jobs/{job_id}
GET  /jobs/{job_id}/zip
GET  /jobs/{job_id}/dataset-inspect
GET  /files/{filename}
```

The frontend uses these endpoints internally. They can also be queried directly for development or integration purposes.

---

## 🧹 Cleaning local generated files

To remove generated results locally:

```bash
rm -rf backend/results/*
touch backend/results/.gitkeep
```

To remove downloaded IECA data and force a fresh download during the next deployment:

```bash
rm -rf backend/IECA/*
touch backend/IECA/.gitkeep
docker compose up --build
```

On Windows PowerShell:

```powershell
Remove-Item .\backend\IECA\* -Recurse -Force
New-Item -ItemType File -Path .\backend\IECA\.gitkeep -Force

Remove-Item .\backend\results\* -Recurse -Force
New-Item -ItemType File -Path .\backend\results\.gitkeep -Force
```

### Docker fails when downloading the OSRM `.osm.pbf`

If the OSRM Dockerfile uses `ADD http://...`, Docker BuildKit may fail with an HTTP cache or ETag-related error. A more robust Dockerfile should download the `.osm.pbf` in a separate downloader stage using Alpine and `curl`, then copy the file into the OSRM image for processing.

### Job history shows old jobs

Job history is stored in:

```text
backend/results/jobs_registry.json
```

FastAPI may also infer old jobs from existing files in `backend/results/`. To clear the history, remove generated files from `backend/results/`.

---

## 🧾 Academic context

UrbanIneq was designed as a reproducible open urban data science infrastructure for accessibility and socio-spatial inequality studies. It integrates heterogeneous spatial, socioeconomic, demographic, and routing-based information sources into a unified computational workflow.

The framework supports research on accessibility disparities by generating harmonized census-section-level datasets and spatial outputs for municipalities in Andalusia. Its focus is on enabling reproducible data preparation, exploratory visualization, and quantitative analysis of potential inequalities in access to urban services.

UrbanIneq should be understood as a data and accessibility infrastructure. It is intended to support subsequent fairness-oriented or equity-oriented urban analytics, but it is not itself a fairness-correction or bias-mitigation algorithm.

---

## 📄 License and citation

Add license information here if applicable.

If you use UrbanIneq in academic work, please cite the associated article or repository.

---

## 👥 Authors

UrbanIneq has been developed as part of a research effort on urban accessibility, open urban data, and socio-spatial inequality analysis in Andalusia.

Add full author and affiliation information here.
