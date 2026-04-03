FROM rocker/geospatial:4.4.1

WORKDIR /app

RUN R -q -e "install.packages(c('plumber','osrm','readxl','jsonlite'), repos='https://cloud.r-project.org')"

COPY plumber.R ./
COPY datadl.R ./
COPY numdata.R ./
COPY spdata.R ./
COPY outputData.R ./
COPY inequalities.R ./
COPY README.md ./

RUN mkdir -p /app/results /app/IECA /app/INE

EXPOSE 8000
CMD ["R", "-q", "-e", "pr <- plumber::plumb('plumber.R'); pr$run(host='0.0.0.0', port=8000)"]
