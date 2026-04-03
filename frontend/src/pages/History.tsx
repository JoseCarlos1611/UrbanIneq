import { useEffect, useState } from "react";
import type { Job } from "@/types/api";
import { fetchJobs } from "@/lib/api";
import { JobHistoryTable } from "@/components/JobHistoryTable";

export default function HistoryPage() {
  const [jobs, setJobs] = useState<Job[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchJobs()
      .then(setJobs)
      .finally(() => setLoading(false));
  }, []);

  if (loading) {
    return <div>Cargando historial...</div>;
  }

  return (
    <div className="w-full max-w-7xl mx-auto px-6 lg:px-8">
      <h1 className="text-2xl font-bold mb-6">Historial de Jobs</h1>
      <JobHistoryTable jobs={jobs} />
    </div>
  );
}