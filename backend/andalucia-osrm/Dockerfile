# Stage 1: download the Andalusia OSM extract with a modern image.
FROM alpine:3.20 AS downloader

ARG DOWNLOAD_URL=https://download.geofabrik.de/europe/spain/andalucia-latest.osm.pbf
ARG OSM_FILE=andalucia-latest.osm.pbf

RUN apk add --no-cache curl ca-certificates
WORKDIR /download
RUN curl -fL --retry 5 --retry-delay 10 --connect-timeout 60 --max-time 0 \
    -o "${OSM_FILE}" "${DOWNLOAD_URL}"

# Stage 2: build the OSRM dataset and serve it.
FROM osrm/osrm-backend:latest

ARG OSM_FILE=andalucia-latest.osm.pbf
ARG OSRM_FILE=andalucia-latest.osrm

ENV OSM_FILE=${OSM_FILE}
ENV OSRM_FILE=${OSRM_FILE}

RUN mkdir -p /data
COPY --from=downloader /download/${OSM_FILE} /data/${OSM_FILE}

RUN osrm-extract -p /opt/foot.lua /data/${OSM_FILE}
RUN rm -f /data/${OSM_FILE}
RUN osrm-partition /data/${OSRM_FILE}
RUN osrm-customize /data/${OSRM_FILE}

EXPOSE 5001
CMD osrm-routed --algorithm mld --port 5001 --max-table-size 1000000 /data/${OSRM_FILE}
