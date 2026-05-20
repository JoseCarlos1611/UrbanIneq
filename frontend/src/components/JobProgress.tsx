import type { Job } from "@/types/api";
import { STAGE_LABELS } from "@/types/api";

interface JobProgressProps {
  job: Partial<Job>;
}

export function JobProgress({ job }: JobProgressProps) {
  const progress = job.progress ?? 0;
  const status = job.status ?? "queued";
  const stage = job.stage;
  const logs = job.logs ?? [];

  return (
    <div className="space-y-4">
      <div>
        <div className="flex items-center justify-between mb-2 text-sm">
          <span className="font-medium">Status: {status}</span>
          <span>{progress}%</span>
        </div>

        <div className="w-full h-3 bg-muted rounded-full overflow-hidden">
          <div
            className="h-full bg-primary transition-all"
            style={{ width: `${Math.max(0, Math.min(progress, 100))}%` }}
          />
        </div>
      </div>

      <div className="text-sm">
        <span className="text-muted-foreground">Current stage: </span>
        <span className="font-medium">
          {stage ? STAGE_LABELS[stage] ?? stage : "-"}
        </span>
      </div>

      {!!logs.length && (
        <div className="border rounded-lg p-3 bg-muted/20">
          <h3 className="text-sm font-medium mb-2">Logs</h3>
          <div className="space-y-2 max-h-64 overflow-auto">
            {logs.map((log, index) => (
              <div key={`${log.ts}-${index}`} className="text-xs">
                <span className="font-mono text-muted-foreground">
                  [{log.ts}]
                </span>{" "}
                <span className="uppercase font-medium">{log.level}</span>{" "}
                <span>{log.msg}</span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
