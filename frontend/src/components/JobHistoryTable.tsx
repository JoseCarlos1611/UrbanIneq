import { Link } from "react-router-dom";
import type { Job } from "@/types/api";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { LOCATIONS_LABELS, DIST_TYPE_LABELS, BIAS_VAR_LABELS } from "@/types/api";

interface JobHistoryTableProps {
  jobs: Job[];
}

export function JobHistoryTable({ jobs }: JobHistoryTableProps) {
  if (!jobs.length) {
    return (
      <div className="bg-card border rounded-xl p-6 shadow-sm">
        <p className="text-sm text-muted-foreground">
          There are no jobs in the history.
        </p>
      </div>
    );
  }

  return (
    <div className="bg-card border rounded-xl shadow-sm overflow-hidden">
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead className="border-b bg-muted/40">
            <tr className="text-left">
              <th className="px-4 py-3 font-medium">Municipality</th>
              <th className="px-4 py-3 font-medium">Location</th>
              <th className="px-4 py-3 font-medium">Distance</th>
              <th className="px-4 py-3 font-medium">Attribute</th>
              <th className="px-4 py-3 font-medium">Status</th>
              <th className="px-4 py-3 font-medium">Date</th>
              <th className="px-4 py-3 font-medium">Actions</th>
            </tr>
          </thead>
          <tbody>
            {jobs.map((job) => (
              <tr key={job.job_id} className="border-b last:border-b-0 align-top">
                <td className="px-4 py-3">
                  <div className="font-medium">{job.config?.city_name ?? "-"}</div>
                  <div className="text-xs text-muted-foreground font-mono">
                    {job.job_id}
                  </div>
                </td>

                <td className="px-4 py-3">
                  {job.config?.locations
                    ? LOCATIONS_LABELS[job.config.locations]
                    : "-"}
                </td>

                <td className="px-4 py-3">
                  {job.config?.dist_type
                    ? DIST_TYPE_LABELS[job.config.dist_type]
                    : "-"}
                </td>

                <td className="px-4 py-3">
                  {job.config?.bias_var
                    ? BIAS_VAR_LABELS[job.config.bias_var]
                    : "-"}
                </td>

                <td className="px-4 py-3">
                  <Badge
                    variant={job.status === "failed" ? "destructive" : "default"}
                    className={
                      job.status === "succeeded"
                        ? "bg-success text-success-foreground"
                        : ""
                    }
                  >
                    {job.status}
                  </Badge>
                </td>

                <td className="px-4 py-3 whitespace-nowrap">
                  {job.created_at
                    ? new Date(job.created_at).toLocaleString("en-GB")
                    : "-"}
                </td>

                <td className="px-4 py-3">
                  <Button variant="outline" size="sm" asChild>
                    <Link to={`/jobs/${job.job_id}`}>
                      View details
                    </Link>
                  </Button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
