export type LocationsType = "parks" | "clinics_public" | "clinics_any";
export type DistType = "mean" | "min" | "max";

export interface Municipality {
  city_code: string;
  name: string;
}

export interface BiasRow {
  key: string;
  label: string;
  lower: number;
  greater: number;
  u: number;
  variation: number;
  median: number;
}

export interface BiasTableResponse {
  suggested: number;
  rows: BiasRow[];
}

export type JobStatus = "queued" | "running" | "succeeded" | "failed";

export type JobStage =
  | "queued"
  | "downloading_ieca"
  | "downloading_ine"
  | "reading_shapefiles"
  | "routing"
  | "building_dataset"
  | "plotting"
  | "exporting"
  | "done";

export interface JobLog {
  ts: string;
  level: "info" | "warn" | "error";
  msg: string;
}

export interface JobConfig {
  city_code: string;
  city_name: string;
  locations: LocationsType;
  dist_type: DistType;
  bias_var: number;
}

export interface JobImages {
  greenzones?: string;
  clinics_public?: string;
  clinics_any?: string;
  y?: string;
  svar?: string;
  [key: string]: string | undefined;
}

export interface JobResult {
  rds_url?: string;
  zip_url?: string;
  images?: JobImages;
}

export interface Job {
  job_id: string;
  status: JobStatus;
  stage: JobStage;
  progress: number;
  created_at: string;
  config: JobConfig;
  logs: JobLog[];
  images?: JobImages;
  result?: JobResult;
}

export const LOCATIONS_LABELS: Record<LocationsType, string> = {
  parks: "Parques",
  clinics_public: "Centros públicos",
  clinics_any: "Todos los centros",
};

export const DIST_TYPE_LABELS: Record<DistType, string> = {
  mean: "Media",
  min: "Mínima",
  max: "Máxima",
};

export const BIAS_VAR_LABELS: Record<number, string> = {
  1: "Renta",
  2: "Desempleo",
  3: "Edad",
  4: "Educación",
  5: "Densidad",
  6: "Hogares",
  7: "Población extranjera",
};

export const STAGE_LABELS: Record<JobStage, string> = {
  queued: "En cola",
  downloading_ieca: "Descargando IECA",
  downloading_ine: "Descargando INE",
  reading_shapefiles: "Leyendo shapefiles",
  routing: "Calculando rutas",
  building_dataset: "Construyendo dataset",
  plotting: "Generando mapas",
  exporting: "Exportando resultados",
  done: "Completado",
};