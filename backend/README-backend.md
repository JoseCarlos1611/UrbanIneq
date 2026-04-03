# Backend FastAPI + plumber

## Endpoints

### FastAPI
- `GET /health`
- `GET /options`
- `POST /jobs/execute`
- `GET /jobs/{job_id}`
- `GET /files/{job_id}/{filename}`

### Ejemplo de llamada
```bash
curl -X POST http://localhost:8080/jobs/execute \
  -H "Content-Type: application/json" \
  -d '{
    "city_name": "Sevilla",
    "locations": "parks",
    "dist_type": "mean"
  }'
```

## Estructura esperada
Coloca estos archivos junto con los `.R` originales y con la carpeta `andalucia-osrm/` del proyecto original.

```text
.
├── Dockerfile.api
├── Dockerfile.r
├── docker-compose.yml
├── main.py
├── plumber.R
├── datadl.R
├── numdata.R
├── spdata.R
├── outputData.R
├── inequalities.R
├── README.md
└── andalucia-osrm/
```

## Levantado
```bash
docker compose up --build
```
