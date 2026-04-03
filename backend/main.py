from __future__ import annotations

import json
import re
import unicodedata
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional

import httpx
from dbfread import DBF
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field

APP_DIR = Path(__file__).resolve().parent
RESULTS_DIR = APP_DIR / "results"
RESULTS_DIR.mkdir(parents=True, exist_ok=True)

IECA_DIR = APP_DIR / "IECA"
MUNICIPALITIES_DBF = IECA_DIR / "13_01_TerminoMunicipal.dbf"

REGISTRY_PATH = RESULTS_DIR / "jobs_registry.json"
ZIP_DIR = RESULTS_DIR / ".zip_cache"
ZIP_DIR.mkdir(parents=True, exist_ok=True)

PLUMBER_URL = "http://r-plumber:8000"
TIMEOUT_SECONDS = 1800.0

BIAS_LABELS: Dict[int, str] = {
    1: "Población total",
    2: "Renta media",
    3: "Población menor de edad",
    4: "Población mayor",
    5: "Población desempleada",
    6: "Población extranjera",
    7: "Índice de soledad",
}


class RunRequest(BaseModel):
    city_code: Optional[str] = Field(
        default=None, description="Código INE del municipio, por ejemplo 41091"
    )
    city_name: Optional[str] = Field(
        default=None, description="Nombre del municipio, por ejemplo Sevilla"
    )
    locations: str = Field(
        default="parks", pattern="^(parks|clinics_public|clinics_any)$"
    )
    dist_type: str = Field(default="mean", pattern="^(mean|min|max)$")
    biasvar: Optional[str] = Field(
        default=None, description="x1..x7. Si no se indica, se usa la sugerida."
    )


class FrontJobRequest(BaseModel):
    city_code: Optional[str] = None
    city_name: Optional[str] = None
    locations: str = Field(default="parks", pattern="^(parks|clinics_public|clinics_any)$")
    dist_type: str = Field(default="mean", pattern="^(mean|min|max)$")
    bias_var: int = Field(ge=1, le=7)


app = FastAPI(
    title="Unfair Urban Data API",
    version="1.2.0",
    description="API FastAPI que delega el cálculo geoespacial a un servicio R con plumber.",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:8081",
        "http://127.0.0.1:8081",
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

_MUNICIPALITIES_CACHE: Optional[List[Dict[str, str]]] = None


# -------------------------------------------------------------------
# Utilidades generales
# -------------------------------------------------------------------

def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def normalize_text(value: str) -> str:
    value = value.strip().lower()
    value = unicodedata.normalize("NFKD", value)
    value = "".join(ch for ch in value if not unicodedata.combining(ch))
    return value


def safe_json_load(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return default


def safe_json_dump(path: Path, data: Any) -> None:
    path.write_text(
        json.dumps(data, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


# -------------------------------------------------------------------
# Municipios reales desde IECA DBF
# -------------------------------------------------------------------

def load_municipalities() -> List[Dict[str, str]]:
    if not MUNICIPALITIES_DBF.exists():
        raise RuntimeError(
            f"No se encontró el fichero de municipios: {MUNICIPALITIES_DBF}"
        )

    # IECA suele venir bien con latin1/cp1252
    table = DBF(str(MUNICIPALITIES_DBF), load=True, encoding="utf-8")

    municipalities: Dict[str, Dict[str, str]] = {}

    for row in table:
        row_dict = dict(row)
        city_code = row_dict.get("cod_mun") or row_dict.get("COD_MUN")
        name = row_dict.get("nombre") or row_dict.get("NOMBRE")

        if city_code is None or name is None:
            continue

        city_code = str(city_code).strip()
        name = str(name).strip()

        if not city_code or not name:
            continue

        municipalities[city_code] = {
            "city_code": city_code,
            "name": name,
        }

    return sorted(
        municipalities.values(),
        key=lambda x: normalize_text(x["name"]),
    )


def get_municipalities_cached() -> List[Dict[str, str]]:
    global _MUNICIPALITIES_CACHE
    if _MUNICIPALITIES_CACHE is None:
        _MUNICIPALITIES_CACHE = load_municipalities()
    return _MUNICIPALITIES_CACHE


def get_municipality_by_code(city_code: str) -> Optional[Dict[str, str]]:
    city_code = str(city_code).strip()
    for item in get_municipalities_cached():
        if item["city_code"] == city_code:
            return item
    return None


def get_municipality_by_name(city_name: str) -> Optional[Dict[str, str]]:
    q = normalize_text(city_name)
    exact = []
    partial = []

    for item in get_municipalities_cached():
        name_n = normalize_text(item["name"])
        if name_n == q:
            exact.append(item)
        elif q in name_n:
            partial.append(item)

    if exact:
        return exact[0]
    if partial:
        return partial[0]
    return None


def resolve_city(city_code: Optional[str], city_name: Optional[str]) -> Dict[str, str]:
    if city_code:
        muni = get_municipality_by_code(city_code)
        if not muni:
            raise HTTPException(
                status_code=404,
                detail=f"No se encontró el municipio con código {city_code}.",
            )
        return muni

    if city_name:
        muni = get_municipality_by_name(city_name)
        if not muni:
            raise HTTPException(
                status_code=404,
                detail=f"No se encontró el municipio '{city_name}'.",
            )
        return muni

    raise HTTPException(
        status_code=422,
        detail="Debes enviar city_code o city_name.",
    )


# -------------------------------------------------------------------
# Registry de jobs
# -------------------------------------------------------------------

def load_registry() -> List[Dict[str, Any]]:
    data = safe_json_load(REGISTRY_PATH, default=[])
    if isinstance(data, list):
        return data
    return []


def save_registry(entries: List[Dict[str, Any]]) -> None:
    safe_json_dump(REGISTRY_PATH, entries)


def upsert_registry_entry(entry: Dict[str, Any]) -> None:
    entries = load_registry()
    filtered = [e for e in entries if e.get("job_id") != entry.get("job_id")]
    filtered.append(entry)
    filtered.sort(key=lambda x: x.get("created_at", ""), reverse=True)
    save_registry(filtered)


def get_registry_entry(job_id: str) -> Optional[Dict[str, Any]]:
    for entry in load_registry():
        if entry.get("job_id") == job_id:
            return entry
    return None


# -------------------------------------------------------------------
# Ficheros de resultados en plano
# -------------------------------------------------------------------

def is_internal_result_file(path: Path) -> bool:
    if not path.is_file():
        return False
    if path.name == "jobs_registry.json":
        return False
    if path.parent == ZIP_DIR:
        return False
    return True


def collect_city_files(city_code: str) -> List[Path]:
    out: List[Path] = []
    for path in RESULTS_DIR.iterdir():
        if not is_internal_result_file(path):
            continue
        name = path.name
        if name.startswith(f"{city_code}_") or name.startswith(f"{city_code}-"):
            out.append(path)
    return sorted(out, key=lambda p: p.name.lower())


def detect_file_role(filename: str) -> Optional[str]:
    stem = Path(filename).stem

    if stem.endswith("_greenzones"):
        return "greenzones"
    if stem.endswith("_clinics_any"):
        return "clinics_any"
    if stem.endswith("_clinics_public"):
        return "clinics_public"
    if stem.endswith("_y"):
        return "y"

    match = re.search(r"_(x[1-7])$", stem)
    if match:
        return match.group(1)

    if filename.endswith(".rds"):
        return "rds"

    return None


def build_images_map(files: List[Path]) -> Dict[str, str]:
    images: Dict[str, str] = {}
    for path in files:
        if path.suffix.lower() != ".png":
            continue
        role = detect_file_role(path.name)
        if not role or role == "rds":
            continue
        images[role] = f"/files/{path.name}"
    return images


def build_rds_url(files: List[Path]) -> Optional[str]:
    for path in files:
        if path.suffix.lower() == ".rds":
            return f"/files/{path.name}"
    return None


def build_zip_for_job(job_id: str, files: List[Path]) -> Optional[str]:
    if not files:
        return None

    zip_path = ZIP_DIR / f"{job_id}.zip"
    if not zip_path.exists():
        with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
            for path in files:
                zf.write(path, arcname=path.name)

    return f"/jobs/{job_id}/zip"


def file_info(path: Path) -> Dict[str, Any]:
    return {
        "name": path.name,
        "size_bytes": path.stat().st_size,
        "url": f"/files/{path.name}",
    }


def infer_legacy_jobs() -> List[Dict[str, Any]]:
    """
    Intenta reconstruir jobs antiguos a partir de ficheros en results/
    con prefijo numérico de 5 dígitos (código INE).
    """
    by_city: Dict[str, List[Path]] = {}

    for path in RESULTS_DIR.iterdir():
        if not is_internal_result_file(path):
            continue

        match = re.match(r"^(\d{5})[_-].+", path.name)
        if not match:
            continue

        city_code = match.group(1)
        by_city.setdefault(city_code, []).append(path)

    legacy_jobs: List[Dict[str, Any]] = []

    for city_code, files in by_city.items():
        muni = get_municipality_by_code(city_code)
        latest_mtime = max(p.stat().st_mtime for p in files)
        created_at = datetime.fromtimestamp(latest_mtime, tz=timezone.utc).isoformat()
        job_id = f"legacy-{city_code}"

        legacy_jobs.append(
            {
                "job_id": job_id,
                "status": "succeeded",
                "stage": "done",
                "progress": 100,
                "created_at": created_at,
                "config": {
                    "city_code": city_code,
                    "city_name": muni["name"] if muni else city_code,
                    "locations": "parks",
                    "dist_type": "mean",
                    "bias_var": None,
                },
                "logs": [],
                "result": {
                    "images": build_images_map(files),
                    "rds_url": build_rds_url(files),
                    "zip_url": build_zip_for_job(job_id, files),
                },
                "files": [file_info(p) for p in sorted(files, key=lambda x: x.name.lower())],
                "_legacy": True,
            }
        )

    legacy_jobs.sort(key=lambda x: x.get("created_at", ""), reverse=True)
    return legacy_jobs


def normalize_registry_job(entry: Dict[str, Any]) -> Dict[str, Any]:
    city_code = entry["config"]["city_code"]
    files = collect_city_files(city_code)

    # Si el registry ya guardó filenames concretos, filtramos por ellos.
    filenames = entry.get("filenames")
    if filenames:
        name_set = set(filenames)
        files = [p for p in files if p.name in name_set]

    return {
        "job_id": entry["job_id"],
        "status": entry.get("status", "succeeded"),
        "stage": entry.get("stage", "done"),
        "progress": entry.get("progress", 100),
        "created_at": entry.get("created_at", utc_now_iso()),
        "config": entry.get("config", {}),
        "logs": entry.get("logs", []),
        "result": {
            "images": build_images_map(files),
            "rds_url": build_rds_url(files),
            "zip_url": build_zip_for_job(entry["job_id"], files),
        },
        "files": [file_info(p) for p in files],
    }


def get_job_files(job_id: str) -> List[Path]:
    entry = get_registry_entry(job_id)

    if entry:
        city_code = entry["config"]["city_code"]
        files = collect_city_files(city_code)
        filenames = entry.get("filenames")
        if filenames:
            names = set(filenames)
            files = [p for p in files if p.name in names]
        return files

    for legacy in infer_legacy_jobs():
        if legacy["job_id"] == job_id:
            files: List[Path] = []
            for f in legacy.get("files", []):
                path = RESULTS_DIR / f["name"]
                if path.exists() and path.is_file():
                    files.append(path)
            return files

    raise HTTPException(status_code=404, detail="No existe ese job_id.")

# -------------------------------------------------------------------
# Comunicación con plumber
# -------------------------------------------------------------------

async def plumber_get(path: str) -> Dict[str, Any]:
    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.get(f"{PLUMBER_URL}{path}")

    if response.status_code >= 400:
        raise HTTPException(
            status_code=502,
            detail=f"Error del servicio R: {response.text}",
        )

    try:
        return response.json()
    except Exception as exc:
        raise HTTPException(
            status_code=502,
            detail=f"Respuesta JSON inválida del servicio R: {exc}",
        ) from exc


async def plumber_post(path: str, payload: Dict[str, Any]) -> Dict[str, Any]:
    async with httpx.AsyncClient(timeout=TIMEOUT_SECONDS) as client:
        response = await client.post(f"{PLUMBER_URL}{path}", json=payload)

    if response.status_code >= 400:
        detail: Any = response.text
        try:
            detail = response.json()
        except Exception:
            pass
        raise HTTPException(
            status_code=502,
            detail={"message": "Error del servicio R", "upstream": detail},
        )

    try:
        return response.json()
    except Exception as exc:
        raise HTTPException(
            status_code=502,
            detail=f"Respuesta JSON inválida del servicio R: {exc}",
        ) from exc


# -------------------------------------------------------------------
# Endpoints base
# -------------------------------------------------------------------

@app.get("/health")
async def health() -> Dict[str, Any]:
    plumber_health = await plumber_get("/health")
    return {
        "status": "ok",
        "services": {
            "fastapi": "ok",
            "plumber": plumber_health,
        },
    }


@app.get("/options")
async def options() -> Dict[str, Any]:
    return {
        "locations": {
            "parks": "UGS / zonas verdes",
            "clinics_public": "HCF público",
            "clinics_any": "HCF público + privado",
        },
        "dist_type": {
            "mean": "distancia media",
            "min": "distancia mínima",
            "max": "distancia máxima",
        },
        "biasvar": [f"x{i}" for i in range(1, 8)],
    }


# -------------------------------------------------------------------
# Municipios
# -------------------------------------------------------------------

@app.get("/municipalities/all")
async def municipalities_all() -> List[Dict[str, str]]:
    return get_municipalities_cached()


@app.get("/municipalities")
async def municipalities_search(
    q: str = Query(..., min_length=2, description="Texto de búsqueda")
) -> List[Dict[str, str]]:
    query = normalize_text(q)
    municipalities = get_municipalities_cached()

    starts: List[Dict[str, str]] = []
    contains: List[Dict[str, str]] = []

    for m in municipalities:
        name_n = normalize_text(m["name"])
        code = m["city_code"]

        if name_n.startswith(query) or code.startswith(query):
            starts.append(m)
        elif query in name_n or query in code:
            contains.append(m)

    return (starts + contains)[:20]


# -------------------------------------------------------------------
# Bias table
# -------------------------------------------------------------------

@app.get("/bias-table/{city_code}")
async def bias_table(city_code: str) -> Dict[str, Any]:
    """
    Este endpoint intenta delegar el cálculo real a plumber.
    Si tu plumber todavía no expone /bias-table/<city_code>, devolverá 501.
    """
    _ = resolve_city(city_code=city_code, city_name=None)

    try:
        data = await plumber_get(f"/bias-table/{city_code}")
        return data
    except HTTPException as exc:
        detail_text = str(exc.detail)
        if "404" in detail_text or "Cannot GET" in detail_text or "Not Found" in detail_text:
            raise HTTPException(
                status_code=501,
                detail=(
                    "El backend FastAPI ya está listo, pero tu servicio plumber "
                    "todavía no expone /bias-table/{city_code}. "
                    "Ese cálculo sigue viviendo en R."
                ),
            ) from exc
        raise


# -------------------------------------------------------------------
# Jobs
# -------------------------------------------------------------------

@app.get("/jobs/{job_id}/dataset-inspect")
async def inspect_job_dataset(job_id: str) -> Dict[str, Any]:
    files = get_job_files(job_id)
    rds_files = [p for p in files if p.suffix.lower() == ".rds"]

    if not rds_files:
        raise HTTPException(status_code=404, detail="No se encontró el .rds de ese job.")

    rds_path = rds_files[0]

    try:
        relative_path = rds_path.relative_to(RESULTS_DIR).as_posix()
    except ValueError as exc:
        raise HTTPException(status_code=500, detail="Ruta de resultado inválida.") from exc

    return await plumber_post("/inspect-rds", {"relative_path": relative_path})

@app.post("/jobs")
async def create_job(payload: FrontJobRequest) -> Dict[str, Any]:
    municipality = resolve_city(payload.city_code, payload.city_name)

    city_code = municipality["city_code"]
    city_name = municipality["name"]
    biasvar = f"x{payload.bias_var}"

    before_names = {p.name for p in collect_city_files(city_code)}

    plumber_payload = {
        "city_code": city_code,
        "city_name": city_name,
        "locations": payload.locations,
        "dist_type": payload.dist_type,
        "biasvar": biasvar,
    }

    result = await plumber_post("/run", plumber_payload)

    after_files = collect_city_files(city_code)
    after_names = {p.name for p in after_files}
    new_names = sorted(after_names - before_names)

    # Si no detectamos nuevos, asociamos igualmente todos los del municipio.
    associated_names = new_names if new_names else sorted(after_names)

    job_id = result.get("job_id") or f"{city_code}-{payload.locations}-{payload.dist_type}-{biasvar}"

    entry = {
        "job_id": job_id,
        "status": "succeeded",
        "stage": "done",
        "progress": 100,
        "created_at": utc_now_iso(),
        "config": {
            "city_code": city_code,
            "city_name": city_name,
            "locations": payload.locations,
            "dist_type": payload.dist_type,
            "bias_var": payload.bias_var,
        },
        "logs": [
            {
                "ts": utc_now_iso(),
                "level": "info",
                "msg": "Job completado correctamente.",
            }
        ],
        "filenames": associated_names,
    }
    upsert_registry_entry(entry)

    return {
        "job_id": job_id,
        "status": "succeeded",
    }


@app.post("/jobs/execute")
async def execute_job(payload: RunRequest) -> Dict[str, Any]:
    municipality = resolve_city(payload.city_code, payload.city_name)

    biasvar = payload.biasvar or "x1"
    if not re.fullmatch(r"x[1-7]", biasvar):
        raise HTTPException(status_code=422, detail="biasvar debe tener formato x1..x7")

    front_payload = FrontJobRequest(
        city_code=municipality["city_code"],
        city_name=municipality["name"],
        locations=payload.locations,
        dist_type=payload.dist_type,
        bias_var=int(biasvar[1:]),
    )

    created = await create_job(front_payload)
    job = await get_job(created["job_id"])
    return job


@app.get("/jobs")
async def list_jobs() -> List[Dict[str, Any]]:
    registry_jobs = [normalize_registry_job(entry) for entry in load_registry()]
    registry_job_ids = {job["job_id"] for job in registry_jobs}

    legacy_jobs = [
        job for job in infer_legacy_jobs()
        if job["job_id"] not in registry_job_ids
    ]

    jobs = registry_jobs + legacy_jobs
    jobs.sort(key=lambda x: x.get("created_at", ""), reverse=True)
    return jobs


@app.get("/jobs/{job_id}")
async def get_job(job_id: str) -> Dict[str, Any]:
    entry = get_registry_entry(job_id)
    if entry:
        return normalize_registry_job(entry)

    # fallback a legacy job reconstruido
    for legacy in infer_legacy_jobs():
        if legacy["job_id"] == job_id:
            return legacy

    raise HTTPException(status_code=404, detail="No existe ese job_id.")


@app.get("/jobs/{job_id}/zip")
async def download_job_zip(job_id: str):
    entry = get_registry_entry(job_id)

    if entry:
        city_code = entry["config"]["city_code"]
        files = collect_city_files(city_code)
        filenames = entry.get("filenames")
        if filenames:
            names = set(filenames)
            files = [p for p in files if p.name in names]
    else:
        legacy = None
        for item in infer_legacy_jobs():
            if item["job_id"] == job_id:
                legacy = item
                break
        if not legacy:
            raise HTTPException(status_code=404, detail="No existe ese job_id.")
        files = []
        for f in legacy.get("files", []):
            path = RESULTS_DIR / f["name"]
            if path.exists() and path.is_file():
                files.append(path)

    if not files:
        raise HTTPException(status_code=404, detail="No hay archivos para ese job.")

    zip_path = ZIP_DIR / f"{job_id}.zip"
    if not zip_path.exists():
        with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
            for path in files:
                zf.write(path, arcname=path.name)

    return FileResponse(path=zip_path, filename=zip_path.name, media_type="application/zip")


# -------------------------------------------------------------------
# Descarga de ficheros
# -------------------------------------------------------------------

@app.get("/files/{filename:path}")
async def download_file(filename: str):
    # Compatibilidad con la forma antigua /files/{job_id}/{filename}
    # y con la nueva /files/{filename}.
    candidate = (RESULTS_DIR / filename).resolve()
    results_root = RESULTS_DIR.resolve()

    try:
        candidate.relative_to(results_root)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="Ruta de archivo inválida.") from exc

    if not candidate.exists() or not candidate.is_file():
        raise HTTPException(status_code=404, detail="Archivo no encontrado.")

    return FileResponse(path=candidate, filename=candidate.name)