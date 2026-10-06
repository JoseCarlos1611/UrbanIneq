FROM osrm/osrm-backend:latest

USER root

COPY prepare-and-run.sh /usr/local/bin/prepare-and-run-osrm
RUN chmod +x /usr/local/bin/prepare-and-run-osrm

ENV OSM_FILE=andalucia-latest.osm.pbf \
    OSRM_FILE=andalucia-latest.osrm

EXPOSE 5001
ENTRYPOINT ["/usr/local/bin/prepare-and-run-osrm"]
