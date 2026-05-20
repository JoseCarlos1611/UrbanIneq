import { useEffect, useMemo, useState } from "react";
import { fetchJobDatasetInspect, type DatasetInspectResponse } from "@/lib/api";
import { Button } from "@/components/ui/button";

type TabKey = "summary" | "variables" | "distributions";

function formatValue(value: unknown) {
  if (value === null || value === undefined) return "—";
  if (typeof value === "number") return Number.isFinite(value) ? value.toFixed(3) : "—";
  return String(value);
}

function MiniHistogram({
  breaks,
  counts,
}: {
  breaks: number[];
  counts: number[];
}) {
  const maxCount = Math.max(...counts, 1);

  return (
    <div className="space-y-2">
      {counts.map((count, i) => {
        const left = breaks[i];
        const right = breaks[i + 1];
        const widthPct = `${(count / maxCount) * 100}%`;

        return (
          <div key={`${left}-${right}-${i}`} className="grid grid-cols-[160px_1fr_48px] gap-3 items-center text-xs">
            <div className="font-mono text-muted-foreground truncate">
              {left.toFixed(2)} – {right.toFixed(2)}
            </div>
            <div className="h-3 bg-muted rounded overflow-hidden">
              <div className="h-full bg-primary" style={{ width: widthPct }} />
            </div>
            <div className="text-right font-medium">{count}</div>
          </div>
        );
      })}
    </div>
  );
}

export function JobDatasetInspector({ jobId }: { jobId: string }) {
  const [data, setData] = useState<DatasetInspectResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [tab, setTab] = useState<TabKey>("summary");
  const [selectedTable, setSelectedTable] = useState<string>("");
  const [selectedVariable, setSelectedVariable] = useState<string>("");

  useEffect(() => {
    let mounted = true;

    const load = async () => {
      try {
        const result = await fetchJobDatasetInspect(jobId);
        if (!mounted) return;

        setData(result);
        setSelectedTable(result.preferred_table);

        const firstDistributionKey = Object.keys(result.distributions)[0] ?? "";
        setSelectedVariable(firstDistributionKey);
      } finally {
        if (mounted) setLoading(false);
      }
    };

    load();

    return () => {
      mounted = false;
    };
  }, [jobId]);

  const previewRows = useMemo(() => {
    if (!data || !selectedTable) return [];
    return data.table_previews[selectedTable] ?? [];
  }, [data, selectedTable]);

  const previewColumns = useMemo(() => {
    if (!previewRows.length) return [];
    return Object.keys(previewRows[0]);
  }, [previewRows]);

  const selectedDistribution = data?.distributions?.[selectedVariable]?.distribution ?? null;

  if (loading) {
    return (
      <div className="bg-card border rounded-xl p-6 shadow-sm">
        <h2 className="font-semibold mb-2">Dataset</h2>
        <p className="text-sm text-muted-foreground">Inspecting .rds...</p>
      </div>
    );
  }

  if (!data) {
    return (
      <div className="bg-card border rounded-xl p-6 shadow-sm">
        <h2 className="font-semibold mb-2">Dataset</h2>
        <p className="text-sm text-muted-foreground">The .rds inspection could not be loaded.</p>
      </div>
    );
  }

  return (
    <div className="bg-card border rounded-xl p-6 shadow-sm space-y-6">
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h2 className="font-semibold">Dataset</h2>
          <p className="text-sm text-muted-foreground">
            Archivo: {data.file}
          </p>
        </div>

        <div className="flex gap-2">
          <Button
            variant={tab === "summary" ? "default" : "outline"}
            size="sm"
            onClick={() => setTab("summary")}
          >
            summary
          </Button>
          <Button
            variant={tab === "variables" ? "default" : "outline"}
            size="sm"
            onClick={() => setTab("variables")}
          >
            attributes
          </Button>
          <Button
            variant={tab === "distributions" ? "default" : "outline"}
            size="sm"
            onClick={() => setTab("distributions")}
          >
            Frequency table
          </Button>
        </div>
      </div>

      {tab === "summary" && (
        <div className="space-y-5">
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4 text-sm">
            <div className="border rounded-lg p-4">
              <div className="text-muted-foreground text-xs mb-1">Municipality</div>
              <div className="font-medium">{data.municipality ?? "—"}</div>
            </div>
            <div className="border rounded-lg p-4">
              <div className="text-muted-foreground text-xs mb-1">Available tables</div>
              <div className="font-medium">{data.available_tables.join(", ")}</div>
            </div>
            <div className="border rounded-lg p-4">
              <div className="text-muted-foreground text-xs mb-1">Main table</div>
              <div className="font-medium">{data.preferred_table}</div>
            </div>
          </div>

          <div className="border rounded-lg p-4">
            <h3 className="font-medium mb-3">Dimensions</h3>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-3 text-sm">
              {Object.entries(data.table_dimensions).map(([name, dims]) => (
                <div key={name} className="flex items-center justify-between border rounded-md px-3 py-2">
                  <span className="font-medium">{name}</span>
                  <span className="text-muted-foreground">
                    {dims.rows} rows · {dims.cols} columns
                  </span>
                </div>
              ))}
            </div>
          </div>

          <div className="border rounded-lg p-4 space-y-3">
            <div className="flex items-center justify-between gap-3 flex-wrap">
              <h3 className="font-medium">Preview</h3>
              <select
                className="border rounded-md px-3 py-2 text-sm bg-background"
                value={selectedTable}
                onChange={(e) => setSelectedTable(e.target.value)}
              >
                {data.available_tables.map((tableName) => (
                  <option key={tableName} value={tableName}>
                    {tableName}
                  </option>
                ))}
              </select>
            </div>

            <div className="overflow-auto border rounded-md">
              <table className="w-full text-xs">
                <thead className="bg-muted/50">
                  <tr>
                    {previewColumns.map((col) => (
                      <th key={col} className="text-left px-3 py-2 font-medium whitespace-nowrap">
                        {col}
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {previewRows.map((row, i) => (
                    <tr key={i} className="border-t">
                      {previewColumns.map((col) => (
                        <td key={col} className="px-3 py-2 whitespace-nowrap">
                          {formatValue(row[col])}
                        </td>
                      ))}
                    </tr>
                  ))}
                  {!previewRows.length && (
                    <tr>
                      <td className="px-3 py-4 text-muted-foreground" colSpan={previewColumns.length || 1}>
                        No preview available.
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
          </div>
        </div>
      )}

      {tab === "variables" && (
        <div className="overflow-auto border rounded-lg">
          <table className="w-full text-xs">
            <thead className="bg-muted/50">
              <tr>
                <th className="text-left px-3 py-2 font-medium">Attribute</th>
                <th className="text-right px-3 py-2 font-medium">Min</th>
                <th className="text-right px-3 py-2 font-medium">Average</th>
                <th className="text-right px-3 py-2 font-medium">Median</th>
                <th className="text-right px-3 py-2 font-medium">Max</th>
                <th className="text-right px-3 py-2 font-medium">SD</th>
              </tr>
            </thead>
            <tbody>
              {data.variables.map((v) => (
                <tr key={v.name} className="border-t">
                  <td className="px-3 py-2 font-medium">{v.name}</td>
                  <td className="px-3 py-2 text-right">{formatValue(v.min)}</td>
                  <td className="px-3 py-2 text-right">{formatValue(v.mean)}</td>
                  <td className="px-3 py-2 text-right">{formatValue(v.median)}</td>
                  <td className="px-3 py-2 text-right">{formatValue(v.max)}</td>
                  <td className="px-3 py-2 text-right">{formatValue(v.sd)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {tab === "distributions" && (
        <div className="space-y-4">
          <div className="flex items-center gap-3 flex-wrap">
            <label className="text-sm font-medium">Numeric attribute</label>
            <select
              className="border rounded-md px-3 py-2 text-sm bg-background"
              value={selectedVariable}
              onChange={(e) => setSelectedVariable(e.target.value)}
            >
              {Object.keys(data.distributions).map((key) => (
                <option key={key} value={key}>
                  {key}
                </option>
              ))}
            </select>
          </div>

          {selectedDistribution ? (
            <div className="space-y-4">
              <div className="grid grid-cols-2 md:grid-cols-4 gap-3 text-sm">
                <div className="border rounded-md p-3">
                  <div className="text-muted-foreground text-xs mb-1">Min</div>
                  <div className="font-medium">{selectedDistribution.min.toFixed(3)}</div>
                </div>
                <div className="border rounded-md p-3">
                  <div className="text-muted-foreground text-xs mb-1">Average</div>
                  <div className="font-medium">{selectedDistribution.mean.toFixed(3)}</div>
                </div>
                <div className="border rounded-md p-3">
                  <div className="text-muted-foreground text-xs mb-1">Median</div>
                  <div className="font-medium">{selectedDistribution.median.toFixed(3)}</div>
                </div>
                <div className="border rounded-md p-3">
                  <div className="text-muted-foreground text-xs mb-1">Max</div>
                  <div className="font-medium">{selectedDistribution.max.toFixed(3)}</div>
                </div>
              </div>

              <div className="border rounded-lg p-4">
                <MiniHistogram
                  breaks={selectedDistribution.breaks}
                  counts={selectedDistribution.counts}
                />
              </div>
            </div>
          ) : (
            <p className="text-sm text-muted-foreground">
              No frequency tables are available.
            </p>
          )}
        </div>
      )}
    </div>
  );
}
