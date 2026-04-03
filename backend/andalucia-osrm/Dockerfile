#import docker file
FROM osrm/osrm-backend:latest

# define variables
ARG DOWNLOAD_URL=http://download.geofabrik.de/europe/spain/andalucia-latest.osm.pbf
ARG OSM_FILE=andalucia-latest.osm.pbf
ARG OSRM_FILE=andalucia-latest.osrm

# transform variables
ENV OSM_FILE=$OSM_FILE
ENV OSRM_FILE=$OSRM_FILE
ENV DOWNLOAD_URL=$DOWNLOAD_URL

## download data
RUN mkdir /data
ADD ${DOWNLOAD_URL} /data/${OSM_FILE}

## extract the osm file
RUN osrm-extract -p /opt/foot.lua /data/$OSM_FILE
## delete the osm file
RUN rm -rf /data/$OSM_FILE
## create other formats
RUN osrm-partition /data/$OSRM_FILE
RUN osrm-customize /data/$OSRM_FILE
#
## Start the docker
CMD osrm-routed --algorithm mld --port 5001 --max-table-size 1000000 /data/$OSRM_FILE
#
EXPOSE 5001
