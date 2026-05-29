# UrbanIneq Docker deployment notes

This corrected package is configured so that IECA data are **not** committed to Git.
The IECA files are downloaded automatically by the `data-init` service when running:

```bash
docker compose up --build
```

## Data policy

- `backend/IECA/` is ignored except for `.gitkeep`.
- `backend/INE/` is not ignored. Put here the INE input files required by the current R code:
  - `backend/INE/30824.xlsx`
  - `backend/INE/Censo_2021_Andalucia.xlsx`

The current R pipeline still reads Excel files with `read_excel()`. If you want to keep two CSV files instead, `numdata.R` and `plumber.R` must be adapted to the exact CSV filenames and column layout.

## Useful checks

Before pushing to GitHub:

```bash
git ls-files backend/IECA
git ls-files backend/INE
git ls-files backend/results
```

Expected for IECA/results:

```text
backend/IECA/.gitkeep
backend/results/.gitkeep
```

## Running

```bash
docker compose down
docker compose up --build
```

The startup order is:

1. `data-init` downloads and unzips IECA data into `backend/IECA`.
2. `andalucia-osrm` prepares/serves the OSRM network.
3. `r-plumber` starts the R geospatial service.
4. `api` starts FastAPI.
5. `frontend` starts Nginx/React.
