import { useEffect, useState } from "react";
import { useParams } from "react-router-dom";
import type { Job } from "@/types/api";
import { fetchJob } from "@/lib/api";
import { ResultsGallery } from "@/components/ResultsGallery";
import { JobProgress } from "@/components/JobProgress";

export default function JobDetailPage() {
  const { jobId = "" } = useParams();
  const [job, setJob] = useState<Job | null>(null);

  useEffect(() => {
    let timer: number | undefined;

    const load = async () => {
      const data = await fetchJob(jobId);
      setJob(data);

      if (data.status === "queued" || data.status === "running") {
        timer = window.setTimeout(load, 2000);
      }
    };

    load();

    return () => {
      if (timer) window.clearTimeout(timer);
    };
  }, [jobId]);

  if (!job) return <div>Cargando...</div>;

  return (
    <div className="space-y-6">
      <JobProgress job={job} />
      {job.status === "succeeded" && job.images && (
        <ResultsGallery images={job.images} />
      )}
    </div>
  );
}