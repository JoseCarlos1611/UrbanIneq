#!/bin/sh
set -eu

DATA_DIR=/data
OSM_PATH="${DATA_DIR}/${OSM_FILE:-andalucia-latest.osm.pbf}"
OSRM_PATH="${DATA_DIR}/${OSRM_FILE:-andalucia-latest.osrm}"
READY_FILE="${DATA_DIR}/.urbanineq-osrm-ready-v1"

mkdir -p "$DATA_DIR"

if [ ! -f "$READY_FILE" ] || [ ! -f "$OSRM_PATH" ]; then
  echo "[UrbanIneq/OSRM] No prepared routing dataset found. Preparing it once..."
  rm -f "$READY_FILE"

  # Remove any partial OSRM build left by an interrupted previous run.
  rm -f "${OSRM_PATH}" "${OSRM_PATH}."* 2>/dev/null || true

  if [ ! -f "$OSM_PATH" ]; then
    echo "[UrbanIneq/OSRM] ERROR: ${OSM_PATH} is missing."
    echo "[UrbanIneq/OSRM] The osrm-data-init service must download it first."
    exit 1
  fi

  echo "[UrbanIneq/OSRM] osrm-extract (foot profile)"
  osrm-extract -p /opt/foot.lua "$OSM_PATH"

  echo "[UrbanIneq/OSRM] osrm-partition"
  osrm-partition "$OSRM_PATH"

  echo "[UrbanIneq/OSRM] osrm-customize"
  osrm-customize "$OSRM_PATH"

  rm -f "$OSM_PATH"
  touch "$READY_FILE"
  echo "[UrbanIneq/OSRM] Dataset prepared and persisted in the Docker volume."
else
  echo "[UrbanIneq/OSRM] Reusing prepared routing dataset from persistent volume."
fi

exec osrm-routed \
  --algorithm mld \
  --port 5001 \
  --max-table-size 1000000 \
  "$OSRM_PATH"
