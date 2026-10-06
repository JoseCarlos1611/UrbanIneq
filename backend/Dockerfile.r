FROM rocker/geospatial:4.4.1

WORKDIR /app

# rocker/geospatial already contains the heavy geospatial system stack
# (sf/GDAL/GEOS/PROJ). Install only packages missing from the base image.
# Rocker's install2.r uses the repositories configured by the base image;
# the fallback intentionally does not force cloud.r-project.org.
RUN --mount=type=cache,target=/root/.cache/R \
    set -eu; \
    if command -v install2.r >/dev/null 2>&1; then \
      install2.r --error --skipinstalled -n "$(nproc)" plumber osrm readxl jsonlite; \
    else \
      R -q -e "pkgs <- c('plumber','osrm','readxl','jsonlite'); missing <- setdiff(pkgs, rownames(installed.packages())); if (length(missing)) install.packages(missing, Ncpus=max(1L, parallel::detectCores(logical=FALSE)-1L))"; \
    fi; \
    rm -rf /tmp/downloaded_packages

# Keep a self-contained image for production. During development docker-compose
# copies the current *.R files from the host when the container starts, so an R
# code change only requires `docker compose restart r-plumber`.
COPY *.R ./
COPY README.md ./

RUN mkdir -p /app/results /app/IECA /app/INE

EXPOSE 8000
CMD ["R", "-q", "-e", "pr <- plumber::plumb('plumber.R'); pr$run(host='0.0.0.0', port=8000)"]
