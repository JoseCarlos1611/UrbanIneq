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
  u?: number;
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
  x1?: string;
  x2?: string;
  x3?: string;
  x4?: string;
  x5?: string;
  x6?: string;
  x7?: string;
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
  parks: "Urban green areas",
  clinics_public: "Healthcare facilities (public)",
  clinics_any: "Healthcare facilities (public and private)",
};

export const DIST_TYPE_LABELS: Record<DistType, string> = {
  mean: "Average",
  min: "Minimum",
  max: "Maximum",
};

export const BIAS_VAR_LABELS: Record<number, string> = {
  1: "Population",
  2: "Income",
  3: "Proportion of children",
  4: "Proportion of elderly population",
  5: "Unemployment rate",
  6: "Proportion of foreign population",
  7: "Loneliness index",
};

export const BIAS_ATTRIBUTE_LABELS: Record<number, string> = {
  1: "X_1 (Population)",
  2: "X_2 (Income)",
  3: "X_3 (Prop. of children)",
  4: "X_4 (Prop. of elderly population)",
  5: "X_5 (Unemployment rate)",
  6: "X_6 (Prop. of foreign population)",
  7: "X_7 (Loneliness index)",
};

export const STAGE_LABELS: Record<JobStage, string> = {
  queued: "Queued",
  downloading_ieca: "Downloading IECA data",
  downloading_ine: "Downloading INE data",
  reading_shapefiles: "Reading shapefiles",
  routing: "Calculating routes",
  building_dataset: "Building dataset",
  plotting: "Generating maps",
  exporting: "Exporting results",
  done: "Completed",
};
