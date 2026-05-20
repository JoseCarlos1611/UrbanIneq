import type {
  Municipality,
  BiasTableResponse,
  Job,
  JobConfig,
} from "@/types/api";

const API_BASE = import.meta.env.VITE_API_BASE_URL ?? "http://localhost:8080";

async function apiFetch<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${API_BASE}${path}`, {
    headers: {
      "Content-Type": "application/json",
      ...(init?.headers ?? {}),
    },
    ...init,
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(text || `HTTP ${response.status}`);
  }

  return response.json() as Promise<T>;
}

export async function searchMunicipalities(query: string): Promise<Municipality[]> {
  return apiFetch<Municipality[]>(
    `/municipalities?q=${encodeURIComponent(query)}`
  );
}

export async function getAllMunicipalities(): Promise<Municipality[]> {
  return apiFetch<Municipality[]>("/municipalities/all");
}

export async function fetchBiasTable(cityCode: string): Promise<BiasTableResponse> {
  const raw = await apiFetch<{
    suggested: number;
    rows: Array<{
      key: string;
      label?: string;
      lower: number;
      greater: number;
      u?: number;
      variation: number;
      median: number;
    }>;
  }>(`/bias-table/${encodeURIComponent(cityCode)}`);

  return {
    suggested: raw.suggested,
    rows: raw.rows.map((row) => ({
      ...row,
      label: row.label ?? row.key,
    })),
  };
}

export async function createJob(config: JobConfig): Promise<string> {
  const data = await apiFetch<{ job_id: string }>("/jobs", {
    method: "POST",
    body: JSON.stringify(config),
  });

  return data.job_id;
}

export async function fetchJobs(): Promise<Job[]> {
  return apiFetch<Job[]>("/jobs");
}

export async function getJobHistory(): Promise<Job[]> {
  return fetchJobs();
}

export async function fetchJob(jobId: string): Promise<Job> {
  return apiFetch<Job>(`/jobs/${jobId}`);
}

export async function getJobById(jobId: string): Promise<Job> {
  return fetchJob(jobId);
}
export interface DatasetInspectResponse {
  file: string;
  municipality?: string | null;
  available_tables: string[];
  preferred_table: string;
  table_dimensions: Record<string, { rows: number; cols: number }>;
  table_previews: Record<string, Array<Record<string, unknown>>>;
  variables: Array<{
    name: string;
    type: string;
    missing: number;
    non_missing: number;
    unique: number;
    min?: number | null;
    max?: number | null;
    mean?: number | null;
    median?: number | null;
    sd?: number | null;
    sample_values?: string[];
  }>;
  distributions: Record<
    string,
    {
      variable: string;
      table: string;
      distribution: {
        min: number;
        max: number;
        mean: number;
        median: number;
        breaks: number[];
        counts: number[];
      } | null;
    }
  >;
}

export async function fetchJobDatasetInspect(
  jobId: string
): Promise<DatasetInspectResponse> {
  return apiFetch<DatasetInspectResponse>(`/jobs/${jobId}/dataset-inspect`);
}
export function subscribeToJob(
  jobId: string,
  onMessage: (partial: Partial<Job>) => void,
  intervalMs = 2000
): () => void {
  let cancelled = false;
  let timer: number | null = null;

  const tick = async () => {
    if (cancelled) return;

    try {
      const job = await fetchJob(jobId);
      onMessage(job);

      if (!cancelled && (job.status === "queued" || job.status === "running")) {
        timer = window.setTimeout(tick, intervalMs);
      }
    } catch (error) {
      console.error("subscribeToJob error:", error);
    }
  };

  void tick();

  return () => {
    cancelled = true;
    if (timer !== null) {
      window.clearTimeout(timer);
    }
  };
}
