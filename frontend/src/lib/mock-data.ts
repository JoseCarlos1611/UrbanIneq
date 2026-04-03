import type { Municipality, BiasTableResponse, Job, JobStage, LogEntry } from "@/types/api";

export const MOCK_MUNICIPALITIES: Municipality[] = [
  { city_code: "41091", name: "Sevilla" },
  { city_code: "41004", name: "Alcalá de Guadaíra" },
  { city_code: "29067", name: "Málaga" },
  { city_code: "14021", name: "Córdoba" },
  { city_code: "18087", name: "Granada" },
  { city_code: "23050", name: "Jaén" },
  { city_code: "04013", name: "Almería" },
  { city_code: "11012", name: "Cádiz" },
  { city_code: "21041", name: "Huelva" },
  { city_code: "41038", name: "Dos Hermanas" },
  { city_code: "29069", name: "Marbella" },
  { city_code: "11020", name: "Jerez de la Frontera" },
];

export const MOCK_BIAS_TABLE: BiasTableResponse = {
  suggested: 2,
  rows: [
    { key: "x1", label: "Población total", lower: 312, greater: 1504, u: 0.42, variation: 18.3, median: 856 },
    { key: "x2", label: "Renta media", lower: 8200, greater: 24500, u: 0.67, variation: 45.2, median: 14300 },
    { key: "x3", label: "% Menores", lower: 8.1, greater: 22.4, u: 0.31, variation: 28.7, median: 15.2 },
    { key: "x4", label: "% Mayores", lower: 12.3, greater: 31.8, u: 0.38, variation: 22.1, median: 20.4 },
    { key: "x5", label: "% Desempleo", lower: 5.2, greater: 28.9, u: 0.55, variation: 38.4, median: 14.7 },
    { key: "x6", label: "% Extranjera", lower: 1.1, greater: 18.7, u: 0.29, variation: 32.6, median: 7.3 },
    { key: "x7", label: "Índice de soledad", lower: 0.12, greater: 0.67, u: 0.44, variation: 25.8, median: 0.38 },
  ],
};

const STAGES_ORDER: JobStage[] = [
  "queued",
  "downloading_ieca",
  "downloading_ine",
  "reading_shapefiles",
  "routing",
  "building_dataset",
  "plotting",
  "exporting",
  "done",
];

export function simulateJobProgress(
  jobId: string,
  onUpdate: (job: Partial<Job>) => void,
  onComplete: () => void
) {
  let stageIndex = 0;
  const logs: LogEntry[] = [];

  const msgs: Record<JobStage, string[]> = {
    queued: ["Job encolado, esperando recursos..."],
    downloading_ieca: ["Conectando con IECA...", "Descargando límites administrativos...", "Descargando secciones censales...", "Descargando zonas verdes..."],
    downloading_ine: ["Conectando con INE...", "Descargando renta 2021 por sección censal..."],
    reading_shapefiles: ["Leyendo shapefiles DERA...", "Procesando geometrías...", "Uniendo datos espaciales..."],
    routing: ["Conectando con OSRM...", "Calculando rutas a pie desde centroides...", "Procesando matriz de distancias...", "Agregando resultados por sección censal..."],
    building_dataset: ["Construyendo variables x1-x7...", "Calculando variable y (distancias)...", "Unificando citydata..."],
    plotting: ["Generando mapa de zonas verdes...", "Generando mapa de distancias (y)...", "Generando mapa de variable sensible..."],
    exporting: ["Exportando .rds...", "Empaquetando archivos en .zip..."],
    done: ["¡Proceso completado!"],
  };

  const interval = setInterval(() => {
    const stage = STAGES_ORDER[stageIndex];
    const stageMsgs = msgs[stage];
    
    stageMsgs.forEach((msg) => {
      logs.push({ ts: new Date().toISOString(), level: "info", msg });
    });

    const progress = stageIndex / (STAGES_ORDER.length - 1);

    onUpdate({
      status: stage === "done" ? "succeeded" : "running",
      stage,
      progress,
      logs: [...logs],
    });

    if (stage === "done") {
      clearInterval(interval);
      onComplete();
    }

    stageIndex++;
  }, 1500);

  return () => clearInterval(interval);
}

// Stored jobs for history
const STORAGE_KEY = "unfair_urban_jobs";

export function getStoredJobs(): Job[] {
  try {
    return JSON.parse(localStorage.getItem(STORAGE_KEY) || "[]");
  } catch {
    return [];
  }
}

export function storeJob(job: Job) {
  const jobs = getStoredJobs();
  const idx = jobs.findIndex((j) => j.job_id === job.job_id);
  if (idx >= 0) jobs[idx] = job;
  else jobs.unshift(job);
  localStorage.setItem(STORAGE_KEY, JSON.stringify(jobs.slice(0, 50)));
}
