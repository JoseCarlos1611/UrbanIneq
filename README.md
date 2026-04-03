# 🗺️ Unfair Urban Dataset

**Análisis geoespacial de desigualdades urbanas en Andalucía**

Un sistema integral de código abierto que automatiza la descarga, procesamiento y visualización de datos espaciales para el análisis de injusticias e inequidades urbanas en municipios andaluces. Combina técnicas avanzadas de análisis geoespacial con una interfaz web moderna e interactiva.

---

## 📋 Tabla de Contenidos

- [Descripción General](#descripción-general)
- [Características Principales](#características-principales)
- [Arquitectura del Sistema](#arquitectura-del-sistema)
- [Estructura de Directorios](#estructura-de-directorios)
- [Requisitos Previos](#requisitos-previos)
- [Instalación Rápida](#instalación-rápida)
- [Uso](#uso)
- [Fuentes de Datos](#fuentes-de-datos)
- [Stack Tecnológico](#stack-tecnológico)
- [Componentes Detallados](#componentes-detallados)
- [APIs y Endpoints](#apis-y-endpoints)
- [Desarrollo](#desarrollo)

---

## 📖 Descripción General

El proyecto **Unfair Urban Dataset** analiza y visualiza patrones de inequidad en ciudades andaluzas mediante:

- **Análisis de accesibilidad**: Distancias a zonas verdes, centros de salud públicos y privados
- **Indicadores socioeconómicos**: Renta, desempleo, educación, densidad poblacional
- **Datos demográficos**: Edad, población extranjera, soledad (hogares unipersonales)
- **Visualización geoespacial**: Mapas interactivos de variables y biases identificados

El sistema identifica automáticamente **cuáles son los factores que más desigualdad generan** en cada municipio, permitiendo investigadores y responsables políticos tomar decisiones basadas en datos.

---

## ✨ Características Principales

✅ **Procesamiento automatizado** de datos espaciales de múltiples fuentes públicas  
✅ **API REST moderna** para consultas y análisis bajo demanda  
✅ **Interfaz web interactiva** con mapas, gráficos y visualizaciones  
✅ **Cobertura completa de Andalucía** con acceso a todos los municipios  
✅ **Análisis de bias** para identificar variables con mayor variación espacial  
✅ **Descarga de resultados** en múltiples formatos (PNG, RDS, ZIP)  
✅ **Cálculos de accesibilidad** usando motor de enrutamiento OSRM  
✅ **Totalmente containerizado** con Docker Compose

---

## 🏗️ Arquitectura del Sistema

El proyecto está estructurado en una **arquitectura de 4 microservicios** orquestados por Docker Compose:

```
┌─────────────────────────────────────────────────────────────┐
│                   CLIENTE WEB (Frontend)                     │
│              React + TypeScript + Vite + Nginx              │
│                      Puerto 8081                             │
└────────────────────┬────────────────────────────���─────────────┘
                     │ HTTP/REST
┌────────────────────▼──────────────────────────────────────────┐
│            FastAPI Gateway (Backend Python)                   │
│     Gestión de jobs, municipios, descarga de archivos        │
│                      Puerto 8080                             │
└────────────────────┬──────────────────────────────────────────┘
                     │ Llamadas HTTP
┌────────────────────▼──────────────────────────────────────────┐
│     R Plumber (Análisis Geoespacial + Visualizaciones)      │
│    Cálculos complejos, procesamiento de datos espaciales     │
│                      Puerto 8000                             │
└────────────────────┬──────────────────────────────────────────┘
                     │ HTTP
┌────────────────────▼──────────────────────────────────────────┐
│      OSRM Backend (Open Source Routing Machine)              │
│         Cálculo de rutas y distancias urbanas                │
│                      Puerto 5001                             │
└─────────────────────────────────────────────────────────────┘
```

### Flujo de Datos

```
Usuario en Web ─→ Frontend (React) ─→ API Gateway (FastAPI)
                                           ├─→ Lee municipios (DBF)
                                           ├─→ Gestiona jobs
                                           └─→ Delega cálculos a R
                                                    ↓
                                       R Plumber (sf, osrm)
                                           ├─→ Descarga datos (IECA/INE)
                                           ├─→ Procesa datos espaciales
                                           ├─→ Calcula distancias (OSRM)
                                           ├─→ Genera mapas (ggplot2)
                                           └─→ Exporta resultados
                                                    ↓
                                       Backend guarda resultados
                                            ↓
                                       Usuario descarga/visualiza
```

---

## 📁 Estructura de Directorios

```
UnfairUrbanDataset/
│
├── docker-compose.yml                          # Orquestación de servicios
│
├── backend/                                     # Servicios backend
│   │
│   ├── Dockerfile.api                           # Container FastAPI
│   ├── Dockerfile.r                             # Container R/Plumber
│   ├── requirements.txt                         # Dependencias Python
│   │
│   ├── main.py                                  # FastAPI Gateway (765 líneas)
│   │   ├── Endpoint /health
│   │   ├── Endpoints /municipalities/*
│   │   ├── Endpoint /bias-table/{city_code}
│   │   ├── Endpoints /jobs/*
│   │   ├── Endpoint /files/{filename}
│   │   └── Gestión de registry JSON
│   │
│   ├── plumber.R                                # API R/Plumber (592 líneas)
│   │   ├── Endpoint GET /health
│   │   ├── Endpoint GET /bias-table/<city_code>
│   │   ├── Endpoint POST /inspect-rds
│   │   ├── Endpoint POST /run (pipeline principal)
│   │   └── Funciones de análisis geoespacial
│   │
│   ├── datadl.R                                 # Descarga de datos (101 líneas)
│   │   ├── ieca_get() - Descarga desde IECA
│   │   └── ine_get() - Descarga desde INE
│   │
│   ├── numdata.R                                # Procesamiento numérico (datos de INE)
│   │   ├── Lectura de Excel (30824.xlsx)
│   │   ├── Extracción por municipio
│   │   └── Limpieza y normalización
│   │
│   ├── spdata.R                                 # Procesamiento espacial (datos IECA)
│   │   ├── Lectura de shapefiles
│   │   ├── Cálculo de centroides
│   │   ├── Filtrado por municipio
│   │   ├── Query OSRM para distancias
│   │   └── Matriz de distancias
│   │
│   ├── inequalities.R                           # Análisis de bias (datos IEPABRA)
│   │   └── databias_local() - Identifica variables críticas
│   │
│   ├── outputData.R                             # Orquestador principal (interfaz)
│   │   └── Wrapper para ejecución local
│   │
│   ├── outputData.bat                           # Script Windows
│   │
│   ├── IECA/                                    # Datos espaciales (descargados)
│   │   ├── 13_01_TerminoMunicipal.*             # Límites municipales (shapefile)
│   │   ├── 13_27_SeccionCensal.*                # Secciones censales (shapefile)
│   │   ├── 07_06_ZonaVerde.*                    # Zonas verdes (shapefile)
│   │   ├── 12_01_CentroSalud.*                  # Centros de salud (shapefile)
│   │   ├── 12_02_Hospital_CAE.*                 # Hospitales (shapefile)
│   │   └── iepabra2021.*                        # Datos demográficos IEPABRA (shapefile)
│   │
│   ├── INE/                                     # Datos estadísticos (descargados)
│   │   ├── 30824.xlsx                           # Atlas de renta de hogares (INE)
│   │   └── Censo_2021_Andalucia.xlsx            # Censo 2021 (si existe)
│   │
│   ├── results/                                 # Resultados de análisis
│   │   ├── {city_code}-{locations}.rds          # Objeto R con datos procesados
│   │   ├── {city_code}_greenzones.png           # Mapa de zonas verdes
│   │   ├── {city_code}_clinics_any.png          # Mapa de clínicas (todas)
│   │   ├── {city_code}_clinics_public.png       # Mapa de clínicas (públicas)
│   │   ├── {city_code}-{locations}_y.png        # Mapa de distancias
│   │   ├── {city_code}_{x1..x7}.png             # Mapas de variables/bias
│   │   ├── .zip_cache/                          # Descargas comprimidas
│   │   │   └── {job_id}.zip
│   │   └── jobs_registry.json                   # Historial de jobs ejecutados
│   │
│   └── andalucia-osrm/                          # Motor de enrutamiento
│       └── Dockerfile                           # Image OSRM preconfigurada
│
├── frontend/                                    # Aplicación web
│   │
│   ├── Dockerfile                               # Build multi-stage (Node + Nginx)
│   ├── package.json                             # Dependencias NPM
│   ├── package-lock.json
│   │
│   ├── index.html                               # Punto de entrada HTML
│   │
│   ├── vite.config.ts                           # Configuración Vite
│   ├── tsconfig.json                            # Configuración TypeScript
│   ├── tailwind.config.ts                       # Configuración Tailwind CSS
│   ├── postcss.config.js                        # PostCSS
│   │
│   ├── src/                                     # Código TypeScript/React
│   │   ├── main.tsx                             # Entry point React
│   │   ├── App.tsx                              # Componente raíz
│   │   ├── App.css                              # Estilos globales
│   │   ├── index.css                            # Estilos Tailwind
│   │   │
│   │   ├── components/                          # Componentes React
│   │   │   ├── Header.tsx
│   │   │   ├── Sidebar.tsx
│   │   │   ├── MunicipalitySearch.tsx
│   │   │   ├── AnalysisForm.tsx
│   │   │   ├── JobsList.tsx
│   │   │   ├── ResultsViewer.tsx
│   │   │   ├── BiasTable.tsx
│   │   │   ├── MapViewer.tsx
│   │   │   └── [...componentes shadcn-ui]
│   │   │
│   │   ├── pages/                               # Páginas
│   │   │   ├── HomePage.tsx
│   │   │   ├── AnalysisPage.tsx
│   │   │   ├── ResultsPage.tsx
│   │   │   └── DocumentationPage.tsx
│   │   │
│   │   ├── hooks/                               # Custom React Hooks
│   │   │   ├── useApi.ts                        # HTTP client
│   │   │   ├── useMunicipalities.ts
│   │   │   ├── useJobStatus.ts
│   │   │   └── [...]
│   │   │
│   │   ├── lib/                                 # Utilidades
│   │   │   ├── api.ts                           # Cliente API
│   │   │   ├── constants.ts
│   │   │   └── utils.ts
│   │   │
│   │   ├── types/                               # Definiciones TypeScript
│   │   │   ├── api.ts
│   │   │   ├── job.ts
│   │   │   ├── municipality.ts
│   │   │   └── analysis.ts
│   │   │
│   │   ├── test/                                # Tests unitarios
│   │   │   └── [...tests con vitest]
│   │   │
│   │   └── vite-env.d.ts                        # Declaraciones Vite
│   │
│   └── public/                                  # Archivos estáticos
│       └── [imágenes, favicon, etc]
│
├── README.md                                    # Este archivo
│
└── [archivos de exportación de código - para desarrollo]
    ├── codigo_exportado.txt
    └── codigo_exportadobackend.txt
```

---

## ⚙️ Requisitos Previos

### Requerimientos del Sistema

- **Docker** >= 20.10
- **Docker Compose** >= 2.0
- **Git** para clonar el repositorio
- **4GB RAM** mínimo para Docker

### Puertos Requeridos

| Puerto | Servicio | Función |
|--------|----------|---------|
| **8081** | Frontend Nginx | Interfaz web (http://localhost:8081) |
| **8080** | FastAPI Gateway | API principal (http://localhost:8080) |
| **8000** | R Plumber | API de análisis (http://localhost:8000) |
| **5001** | OSRM Backend | Motor de enrutamiento (http://localhost:5001) |

> ⚠️ **Nota**: Asegúrate de que estos puertos estén disponibles. Si no lo están, modifica `docker-compose.yml`

---

## 🚀 Instalación Rápida

### 1. Clonar el Repositorio

```bash
git clone https://github.com/JoseCarlos1611/UnfairUrbanDataset.git
cd UnfairUrbanDataset
```

### 2. Levantar los Servicios

```bash
# Build y start en modo foreground (recomendado para primera vez)
docker-compose up --build

# O en modo background
docker-compose up -d --build
```

### 3. Esperar a que los Servicios Inicialicen

Los servicios se inician en este orden:
1. **OSRM Backend** (5001) - 30-60s
2. **R Plumber** (8000) - 1-2 min (descarga datos IECA/INE si es primera ejecución)
3. **FastAPI Gateway** (8080) - 15-30s
4. **Frontend Nginx** (8081) - Inmediato

> 💡 Monitoriza los logs: `docker-compose logs -f r-plumber`

### 4. Verificar Instalación

```bash
# Comprobar salud de servicios
curl http://localhost:8080/health

# Respuesta esperada:
# {"status":"ok","services":{"fastapi":"ok","plumber":{...}}}
```

### 5. Acceder a la Interfaz

Abre tu navegador: **http://localhost:8081**

---

## 📊 Uso

### Vía Interfaz Web

1. **Selecciona municipio**
   - Busca por nombre o código INE
   - Ej: "Sevilla", "41091", "Córdoba"

2. **Configura análisis**
   - **Ubicaciones**: Zonas verdes | Clínicas públicas | Clínicas todas
   - **Tipo de distancia**: Media | Mínima | Máxima
   - **Variable de bias**: Elige qué indicador analizar (o automático)

3. **Ejecuta análisis**
   - Se generan 5 mapas PNG + 1 archivo RDS
   - Visualiza resultados interactivos
   - Descarga como ZIP

### Vía API REST

#### Listar Municipios

```bash
# Todos
curl http://localhost:8080/municipalities/all

# Búsqueda
curl "http://localhost:8080/municipalities?q=sevilla"
```

#### Crear Análisis

```bash
curl -X POST http://localhost:8080/jobs \
  -H "Content-Type: application/json" \
  -d '{
    "city_code": "41091",
    "city_name": "Sevilla",
    "locations": "parks",
    "dist_type": "mean",
    "bias_var": 1
  }'
```

#### Obtener Resultados

```bash
# Listar jobs
curl http://localhost:8080/jobs

# Obtener job específico
curl http://localhost:8080/jobs/{job_id}

# Descargar ZIP
curl http://localhost:8080/jobs/{job_id}/zip -o resultados.zip

# Inspeccionar dataset RDS
curl -X POST http://localhost:8080/jobs/{job_id}/dataset-inspect
```

#### Tabla de Bias (preview)

```bash
curl http://localhost:8080/bias-table/41091
```

---

## 💾 Fuentes de Datos

### IECA (Instituto Andaluz de Estadística y Cartografía)

| Dato | URL | Formato | Contenido |
|------|-----|---------|----------|
| **Límites Municipales** | [DERA Límites](https://www.juntadeandalucia.es/institutodeestadisticaycartografia/) | Shapefile | Contornos municipales (13_01_*) |
| **Secciones Censales** | DERA Límites | Shapefile | Secciones para análisis demográfico (13_27_*) |
| **Zonas Verdes** | [DERA Urbano](https://www.juntadeandalucia.es/institutodeestadisticaycartografia/) | Shapefile | Parques y UGS (07_06_*) |
| **Centros de Salud** | [DERA Servicios](https://www.juntadeandalucia.es/institutodeestadisticaycartografia/) | Shapefile | Clínicas y hospitales (12_01_*, 12_02_*) |
| **Demográficos** | [IEPABRA 2021](https://www.juntadeandalucia.es/institutodeestadisticaycartografia/) | Shapefile | Edad, extranjeros, hogares (iepabra2021.*) |

### INE (Instituto Nacional de Estadística)

| Dato | URL | Formato | Contenido |
|------|-----|---------|----------|
| **Renta de Hogares** | [ADRH 30824](https://www.ine.es/) | XLSX | Distribución de renta por sección censal |
| **Censo 2021** | [Censo](https://www.ine.es/censos2021/) | XLSX | Población, educación (si se obtiene) |

### Servicio OSRM

- **OpenStreetMap** vía **OSRM** para enrutamiento
- **Cobertura**: Andalucía completa
- **Método**: Cálculo de distancias red vial real (no euclidiana)

---

## 🛠️ Stack Tecnológico

### Backend

| Componente | Versión | Rol |
|-----------|---------|-----|
| **R** | 4.4.1 | Análisis geoespacial, estadístico |
| **Plumber** | Última | Framework REST para R |
| **sf** | - | Operaciones geoespaciales (shapefiles) |
| **osrm** | - | Cliente OSRM para distancias |
| **ggplot2** | - | Visualización de mapas |
| **readxl** | - | Lectura de Excel |
| **jsonlite** | - | Serialización JSON |
| **Python** | 3.11 | FastAPI gateway |
| **FastAPI** | 0.115.12 | API REST moderna async |
| **uvicorn** | 0.34.0 | ASGI server |
| **httpx** | 0.28.1 | Cliente HTTP async |
| **pydantic** | 2.10.6 | Validación de datos |
| **dbfread** | - | Lectura de DBF (IECA) |
| **OSRM** | Última | Enrutamiento (contenedor) |

### Frontend

| Componente | Versión | Rol |
|-----------|---------|-----|
| **React** | 18.3.1 | Framework UI |
| **TypeScript** | 5.8.3 | Tipado estático |
| **Vite** | 5.4.19 | Bundler moderno |
| **React Router** | 6.30.1 | Enrutamiento |
| **TanStack Query** | 5.83.0 | State management (API) |
| **Tailwind CSS** | 3.4.17 | Estilos utilitarios |
| **shadcn/ui** | - | Componentes accesibles |
| **Recharts** | 2.15.4 | Gráficos |
| **Hook Form** | 7.61.1 | Gestión de formularios |
| **Zod** | 3.25.76 | Validación esquemas |
| **Lucide React** | 0.462.0 | Iconos |
| **Nginx** | 1.27 | Servidor web (producción) |

### DevOps

- **Docker** - Containerización
- **Docker Compose** - Orquestación
- **Multi-stage builds** - Optimización de imágenes

---

## 🔧 Componentes Detallados

### Backend: main.py (FastAPI Gateway)

**Responsabilidades:**
- Punto de entrada para la interfaz web
- Gestión de municipios (lectura DBF IECA)
- Orquestación de jobs
- Proxy a Plumber para cálculos
- Descarga de resultados (archivos, ZIP)
- Registry JSON de historial

**Funciones Clave:**

```python
# Municipios
get_municipalities_cached()          # Caché en memoria (optimización)
resolve_city(code, name)             # Resolver código/nombre a municipio

# Registry de jobs
load_registry() / save_registry()    # Persistencia JSON
upsert_registry_entry()              # Crear/actualizar job

# Archivos
collect_city_files()                 # Archivos de un municipio
build_images_map()                   # Mapear PNGs a URLs
build_zip_for_job()                  # Comprimir resultados

# Comunicación con Plumber
plumber_get() / plumber_post()       # Llamadas HTTP async
```

**Endpoints Principales:**

| Método | Ruta | Descripción |
|--------|------|-------------|
| GET | `/health` | Comprobar estado servicios |
| GET | `/municipalities/all` | Todos los municipios |
| GET | `/municipalities?q=...` | Búsqueda |
| GET | `/bias-table/{city_code}` | Tabla de bias preview |
| POST | `/jobs` | Crear análisis |
| GET | `/jobs` | Listar histórico |
| GET | `/jobs/{job_id}` | Obtener detalles |
| GET | `/jobs/{job_id}/zip` | Descargar ZIP |
| GET | `/jobs/{job_id}/dataset-inspect` | Inspeccionar RDS |
| GET | `/files/{filename}` | Descargar archivo individual |

### Backend: plumber.R (API de Análisis)

**Responsabilidades:**
- Descarga automática de datos IECA/INE (primera ejecución)
- Procesamiento geoespacial completo
- Análisis de inequidad
- Generación de visualizaciones
- Cálculos de accesibilidad

**Flujo Principal (`run_pipeline`):**

```
1. Validar código municipio
2. Cargar datos numéricos (INE renta + censo)
3. Cargar datos espaciales (shapefiles IECA)
4. Calcular centroides de secciones censales
5. Consultar OSRM para matriz de distancias
   - A zonas verdes (parks)
   - O clínicas (públicas/todas)
6. Estandarizar variables (normalización Z)
7. Calcular matriz de "bias" (databias_local)
   - Mediana de cada variable
   - Media de Y por encima/debajo de mediana
   - Variación %
8. Generar 5 visualizaciones (ggplot2):
   - Zonas verdes
   - Clínicas (cualquier tipo)
   - Clínicas (públicas)
   - Variable Y (distancias)
   - Variable seleccionada (bias)
9. Guardar RDS con objeto completo
10. Retornar metadata
```

**Funciones Clave:**

```r
ensure_data()                      # Verificar/descargar datos
build_analysis_context()           # Preparar entorno R
ct.get_x()                        # Matriz X de variables
sp.dists$y                        # Vector Y de distancias
databias_local()                  # Análisis de bias
run_pipeline()                    # Ejecución completa
```

### Backend: datadl.R (Descarga de Datos)

Automatiza descargas de:
- **IECA LIMITS**: Límites administrativos (ZIP ~50MB)
- **IECA URBAN**: Zonas verdes (ZIP ~20MB)
- **IECA SERVICE**: Centros de salud (ZIP ~10MB)
- **IECA DEMO**: Datos demográficos IEPABRA (ZIP ~30MB)
- **INE INCOME**: Excel de renta (XLSX ~5MB)

> Ejecutado automáticamente en `plumber.R` si faltan ficheros

### Backend: Procesamiento de Datos

**numdata.R** - Lee Excel (renta + censo) y extrae por municipio
```r
ct.get_income()        # Código municipio → renta media
ct.get_census_info()   # Población, edad, desempleo, etc.
```

**spdata.R** - Lee shapefiles y calcula accesibilidad
```r
sp.dists            # Consulta OSRM para distancias
sp.tractdata        # Datos espaciales de secciones
sp.clinic_public    # Puntos de clínicas públicas
sp.clinic_any       # Puntos de todas las clínicas
sp.gzdata          # Geometrías de zonas verdes
```

**inequalities.R** - Análisis de sesgos
```r
databias_local()    # Detección automática de variables críticas
```

### Frontend: Arquitectura React

**Flujo de Datos:**
```
App → Router → Pages
         ├→ HomePage
         ├→ AnalysisPage
         │   ├→ MunicipalitySearch (busca + selecciona)
         │   ├→ AnalysisForm (config parámetros)
         │   └→ useMunicipalities (query)
         │
         ├→ ResultsPage
         │   ├→ JobsList (historial)
         │   ├→ ResultsViewer (mapas)
         │   ├→ BiasTable (tabla análisis)
         │   └→ useJobStatus (polling)
         │
         └→ DocumentationPage
```

**State Management:**
- **TanStack Query** para cacheo de API
- **React Hook Form** para formularios
- **Zod** para validación
- **React Context** para temas/preferencias

**Componentes shadcn:**
- Dialog, Tabs, Select, Button, Card
- Form, Input, Textarea, Checkbox
- Alert, Toast, Loading states

---

## 📡 APIs y Endpoints

### Health Check

```bash
GET /health
```

Respuesta:
```json
{
  "status": "ok",
  "services": {
    "fastapi": "ok",
    "plumber": {
      "status": "ok",
      "osrm_url": "http://andalucia-osrm:5001/",
      "osrm_reachable": true
    }
  }
}
```

### Municipios

```bash
# Obtener todos
GET /municipalities/all

# Buscar
GET /municipalities?q=sev
```

Respuesta:
```json
[
  {
    "city_code": "41091",
    "name": "Sevilla"
  },
  {
    "city_code": "41069",
    "name": "Osuna"
  }
]
```

### Jobs - Crear Análisis

```bash
POST /jobs
Content-Type: application/json

{
  "city_code": "41091",
  "city_name": "Sevilla",
  "locations": "parks",        # parks|clinics_public|clinics_any
  "dist_type": "mean",         # mean|min|max
  "bias_var": 1                # 1-7 o null (automático)
}
```

Respuesta:
```json
{
  "job_id": "41091-parks-mean-x1-20260403120000",
  "status": "succeeded",
  "stage": "done",
  "progress": 100,
  "created_at": "2026-04-03T12:00:00+00:00",
  "config": {
    "city_code": "41091",
    "city_name": "Sevilla",
    "locations": "parks",
    "dist_type": "mean",
    "bias_var": 1
  },
  "result": {
    "images": {
      "greenzones": "/files/41091_greenzones.png",
      "clinics_any": "/files/41091_clinics_any.png",
      "y": "/files/41091-parks_y.png",
      "x1": "/files/41091_x1.png"
    },
    "rds_url": "/files/41091-parks.rds",
    "zip_url": "/jobs/41091-parks-mean-x1/zip"
  },
  "files": [
    {
      "name": "41091_greenzones.png",
      "size_bytes": 45234,
      "url": "/files/41091_greenzones.png"
    }
  ]
}
```

### Inspeccionar Datos

```bash
POST /jobs/{job_id}/dataset-inspect

# Respuesta: estructura del RDS
{
  "file": "41091-parks.rds",
  "municipality": "Sevilla",
  "available_tables": ["raw", "x", "y", "centroids"],
  "table_dimensions": {
    "raw": {"rows": 126, "cols": 8},
    "x": {"rows": 126, "cols": 8}
  },
  "variables": [
    {
      "name": "total",
      "type": "numeric",
      "min": 234,
      "max": 45678,
      "mean": 12345.67,
      "median": 10000,
      "sd": 8234.5
    }
  ],
  "distributions": {
    "mean_income": {
      "variable": "mean_income",
      "distribution": {
        "min": 15000,
        "max": 85000,
        "mean": 35000,
        "median": 32000,
        "breaks": [15000, 20000, ..., 85000],
        "counts": [5, 12, 23, ...]
      }
    }
  }
}
```

### Descargar Resultados

```bash
# ZIP de todo
GET /jobs/{job_id}/zip

# Archivo individual
GET /files/41091_greenzones.png
GET /files/41091-parks.rds
```

---

## 👨‍💻 Desarrollo

### Setup Local (Sin Docker)

#### Frontend

```bash
cd frontend
npm install
npm run dev        # Vite dev server http://localhost:5173
npm run build      # Producción
npm test           # Vitest
npm run lint       # ESLint
```

#### Backend (FastAPI)

```bash
cd backend
python3 -m venv venv
source venv/bin/activate  # o venv\Scripts\activate en Windows
pip install -r requirements.txt
uvicorn main:app --reload --port 8080
```

#### Backend (R/Plumber)

Requiere instalación local de R 4.0+:

```bash
# Instalar paquetes
R -q -e "install.packages(c('plumber','osrm','readxl','sf','ggplot2','jsonlite'))"

# En R REPL
setwd("backend")
library(plumber)
pr <- plumber::plumb('plumber.R')
pr$run(host='0.0.0.0', port=8000)
```

### Debugging

#### Ver logs

```bash
docker-compose logs -f                 # Todos
docker-compose logs -f r-plumber       # Solo R
docker-compose logs -f api             # Solo FastAPI
docker-compose logs -f frontend        # Solo Nginx
```

#### Acceder a contenedores

```bash
docker exec -it unfair-urban-r R       # R interactivo
docker exec -it unfair-urban-fastapi bash
docker exec -it unfair-urban-frontend sh
```

#### Datos persistentes

Los volumenes están montados en `docker-compose.yml`:
```yaml
volumes:
  - ./backend/IECA:/app/IECA           # Datos IECA (compartido)
  - ./backend/INE:/app/INE             # Datos INE (compartido)
  - ./backend/results:/app/results     # Resultados (compartido)
```

Esto permite:
- Compartir datos entre contenedores
- Persistencia después de reiniciar Docker
- Fácil acceso desde host para debugging

### Agregar Nuevas Fuentes de Datos

1. Crear función en `datadl.R`:
```r
new_source_get <- function(url, filename) {
  # Lógica de descarga
}
```

2. Integrar en `plumber.R` dentro de `ensure_data()`

3. Usar en análisis (agregar a `numdata.R` o `spdata.R`)

### Agregar Nuevas Visualizaciones

En `plumber.R`:
```r
fplot.custom <- ggplot() +
  geom_sf(data = citydata$geometry, aes(fill = ...)) +
  ...
suppressMessages(ggsave(filenames$custom, plot = fplot.custom))
```

---

## 📈 Ejemplos de Uso

### Análisis Completo de Sevilla

```bash
# 1. Crear análisis
JOB=$(curl -s -X POST http://localhost:8080/jobs \
  -H "Content-Type: application/json" \
  -d '{"city_name":"Sevilla","locations":"parks","dist_type":"mean","bias_var":2}' \
  | jq -r '.job_id')

# 2. Monitorear progreso
curl http://localhost:8080/jobs/$JOB | jq

# 3. Descargar resultados
curl -O http://localhost:8080/jobs/$JOB/zip
unzip $(basename $JOB).zip
```

### Comparar Variables de Bias

```bash
# Análisis con Variable 1 (Renta)
curl -X POST http://localhost:8080/jobs \
  -H "Content-Type: application/json" \
  -d '{"city_code":"41091","bias_var":1}'

# Análisis con Variable 5 (Desempleo)
curl -X POST http://localhost:8080/jobs \
  -H "Content-Type: application/json" \
  -d '{"city_code":"41091","bias_var":5}'

# Comparar outputs en /backend/results/
```

### Procesar Múltiples Municipios

```bash
# Script bash
for city in "Sevilla" "Córdoba" "Granada" "Cádiz"; do
  curl -X POST http://localhost:8080/jobs \
    -H "Content-Type: application/json" \
    -d "{\"city_name\":\"$city\",\"locations\":\"parks\",\"dist_type\":\"mean\",\"bias_var\":2}" \
    -s | jq '.job_id'
  
  sleep 120  # Esperar entre jobs
done
```

---

## 🐛 Troubleshooting

### "OSRM Backend no está disponible"

```bash
# Verificar
curl http://localhost:5001/route/v1/driving/0,0;1,1?overview=false

# Si falla, reconstruir
docker-compose up -d --build andalucia-osrm
```

### Datos incompletos después de inicio

```bash
# R está descargando (primera vez es lento)
docker-compose logs -f r-plumber | grep -i download

# Puede tardar 10-15 minutos en completarse
```

### Puerto en uso

```bash
# Cambiar puertos en docker-compose.yml
ports:
  - "9081:80"    # Frontend (en lugar de 8081)
  - "9080:8080"  # API (en lugar de 8080)
```

### "Cannot find file IECA/..."

```bash
# Forzar descarga
docker exec unfair-urban-r Rscript -e "source('datadl.R')"

# Verificar contenido
docker exec unfair-urban-r ls -lh /app/IECA/
```

---

## 📚 Referencias Externas

### Documentación Oficial

- [Plumber Documentation](https://www.rplumber.io/)
- [FastAPI](https://fastapi.tiangolo.com/)
- [React Documentation](https://react.dev/)
- [OSRM API](http://project-osrm.org/docs/v5.5.1/api/overview/)

### Datos Públicos Españoles

- [IECA - Instituto Andaluz de Estadística](https://www.juntadeandalucia.es/institutodeestadisticaycartografia/)
- [INE - Instituto Nacional de Estadística](https://www.ine.es/)
- [OpenStreetMap](https://www.openstreetmap.org/)

### Librerías R

- [sf - Simple Features](https://r-spatial.github.io/sf/)
- [ggplot2 - Visualización](https://ggplot2.tidyverse.org/)
- [osrm - Cliente OSRM](https://github.com/riatelab/osrm)

---

## 📄 Licencia

Este proyecto está disponible bajo licencia **[Especificar Licencia]**.

**Copyright © 2023-2024 JoseCarlos1611**

---

## 🤝 Contribuciones

Las contribuciones son bienvenidas. Para cambios significativos, abre un issue primero.

1. Fork el repositorio
2. Crea una rama (`git checkout -b feature/AmazingFeature`)
3. Commit cambios (`git commit -m 'Add AmazingFeature'`)
4. Push a la rama (`git push origin feature/AmazingFeature`)
5. Abre un Pull Request

---

## 📞 Contacto y Soporte

- **Autor**: JoseCarlos1611
- **Issues**: [GitHub Issues](https://github.com/JoseCarlos1611/UnfairUrbanDataset/issues)
- **Documentación**: [Wiki del Proyecto](https://github.com/JoseCarlos1611/UnfairUrbanDataset/wiki)

---

## 📊 Estadísticas del Proyecto

| Métrica | Valor |
|---------|-------|
| **Lenguajes Principales** | TypeScript (72.5%), R (15.6%), Python (9.3%) |
| **Líneas de Código Backend** | ~1,500 |
| **Líneas de Código Frontend** | TBD |
| **Cobertura Geográfica** | Andalucía (8 provincias, 786 municipios) |
| **Fuentes de Datos** | 2 principales (IECA, INE) |
| **Variables Analizadas** | 7 indicadores |
| **Contenedores Docker** | 4 servicios |

---

## 🙏 Agradecimientos

- Instituto Andaluz de Estadística y Cartografía (IECA)
- Instituto Nacional de Estadística (INE)
- Proyecto OpenStreetMap y OSRM
- Comunidad de R geoespacial

---

**Última actualización**: 3 de Abril de 2026

**Estado**: ✅ En desarrollo activo
