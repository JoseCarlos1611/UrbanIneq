import { useEffect, useState } from "react";
import { useParams, Link } from "react-router-dom";
import { getJobById } from "@/lib/api";
import type { Job } from "@/types/api";
import { LOCATIONS_LABELS, DIST_TYPE_LABELS, BIAS_VAR_LABELS } from "@/types/api";
import { ResultsGallery } from "@/components/ResultsGallery";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Download, FileArchive, ArrowLeft } from "lucide-react";
import { JobDatasetInspector } from "@/components/JobDatasetInspector";

const JobResultsPage = () => {
  const { jobId } = useParams<{ jobId: string }>();
  const [job, setJob] = useState<Job | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let mounted = true;

    const load = async () => {
      if (!jobId) {
        if (mounted) {
          setJob(null);
          setLoading(false);
        }
        return;
      }

      try {
        const data = await getJobById(jobId);
        if (mounted) {
          setJob(data);
        }
      } catch (error) {
        console.error("Error loading job:", error);
        if (mounted) {
          setJob(null);
        }
      } finally {
        if (mounted) {
          setLoading(false);
        }
      }
    };

    void load();

    return () => {
      mounted = false;
    };
  }, [jobId]);

  if (loading) {
    return <div className="text-center py-20">Loading...</div>;
  }

  if (!job) {
    return (
      <div className="text-center py-20">
        <h2 className="text-xl font-semibold mb-2">Job not found</h2>
        <p className="text-muted-foreground mb-4">
          The job "{jobId}" does not exist or has expired.
        </p>
        <Button variant="outline" asChild>
          <Link to="/">
            <ArrowLeft className="w-4 h-4 mr-1" /> Back
          </Link>
        </Button>
      </div>
    );
  }

  return (
    <div className="w-full max-w-7xl px-6 lg:px-8 mx-auto space-y-6">
      <div className="bg-card border rounded-xl p-6 shadow-sm">
        <div className="flex items-start justify-between gap-4 flex-wrap">
          <div>
            <div className="flex items-center gap-3 mb-2">
              <Button variant="ghost" size="sm" asChild>
                <Link to="/history">
                  <ArrowLeft className="w-4 h-4" />
                </Link>
              </Button>
              <h1 className="text-2xl font-bold">{job.config.city_name}</h1>
              <Badge
                variant={job.status === "failed" ? "destructive" : "default"}
                className={job.status === "succeeded" ? "bg-success text-success-foreground" : ""}
              >
                {job.status}
              </Badge>
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 text-sm mt-4">
              <div>
                <div className="text-muted-foreground text-xs mb-1">Locations</div>
                <div>{LOCATIONS_LABELS[job.config.locations]}</div>
              </div>
              <div>
                <div className="text-muted-foreground text-xs mb-1">Distance</div>
                <div>{DIST_TYPE_LABELS[job.config.dist_type]}</div>
              </div>
              <div>
                <div className="text-muted-foreground text-xs mb-1">Sensitive attribute</div>
                <div>{BIAS_VAR_LABELS[job.config.bias_var]}</div>
              </div>
              <div>
                <div className="text-muted-foreground text-xs mb-1">Date</div>
                <div>{new Date(job.created_at).toLocaleString("en-GB")}</div>
              </div>
              <div>
                <div className="text-muted-foreground text-xs mb-1">Job ID</div>
                <div className="font-mono text-xs">{job.job_id}</div>
              </div>
              <div>
                <div className="text-muted-foreground text-xs mb-1">Status</div>
                <div className="capitalize">{job.status}</div>
              </div>
            </div>
          </div>
        </div>
      </div>

      {job.result && (
        <>
          <div className="flex gap-3 flex-wrap">
            {job.result.rds_url && (
              <Button variant="outline" asChild>
                <a href={job.result.rds_url} download>
                  <Download className="w-4 h-4 mr-2" /> Download .rds
                </a>
              </Button>
            )}

            {job.result.zip_url && (
              <Button asChild>
                <a href={job.result.zip_url} download>
                  <FileArchive className="w-4 h-4 mr-2" /> Download full .zip
                </a>
              </Button>
            )}
          </div>

          {job.result.images && (
            <div className="bg-card border rounded-xl p-6 shadow-sm">
              <h2 className="font-semibold mb-4">Generated maps</h2>
              <ResultsGallery images={job.result.images} />
            </div>
          )}

          <JobDatasetInspector jobId={job.job_id} />
        </>
      )}
    </div>
  );
};

export default JobResultsPage;
