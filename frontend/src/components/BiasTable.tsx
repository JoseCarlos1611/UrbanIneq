import { useEffect, useState } from "react";
import type { BiasTableResponse, DistType, LocationsType } from "@/types/api";
import { DIST_TYPE_LABELS, LOCATIONS_LABELS } from "@/types/api";
import { Button } from "@/components/ui/button";
import { ArrowUpDown, Calculator, Loader2 } from "lucide-react";
import { fetchBiasTable } from "@/lib/api";

interface Props {
  cityCode: string;
  locations: LocationsType;
  distType: DistType;
  value: number | null;
  onChange: (v: number | null) => void;
  onCacheIdChange?: (cacheId: string | null) => void;
}

type SortKey = "variation" | "median" | "greater" | "lower" | null;

function getAttributeLabel(key: string): string {
  const normalized = key.toLowerCase();
  const varNum = Number.parseInt(normalized.replace("x", ""), 10);

  const labels: Record<number, string> = {
    1: "X_1 (Population)",
    2: "X_2 (Income)",
    3: "X_3 (Prop. of children)",
    4: "X_4 (Prop. of elderly population)",
    5: "X_5 (Unemployment rate)",
    6: "X_6 (Prop. of foreign population)",
    7: "X_7 (Loneliness index)",
  };

  return labels[varNum] ?? key;
}

export function BiasTable({
  cityCode,
  locations,
  distType,
  value,
  onChange,
  onCacheIdChange,
}: Props) {
  const [data, setData] = useState<BiasTableResponse | null>(null);
  const [loading, setLoading] = useState(false);
  const [sortKey, setSortKey] = useState<SortKey>(null);
  const [sortAsc, setSortAsc] = useState(false);

  useEffect(() => {
    setData(null);
    onChange(null);
    onCacheIdChange?.(null);
  }, [cityCode, locations, distType, onChange, onCacheIdChange]);

  const handleFetch = async () => {
    setLoading(true);

    try {
      const result = await fetchBiasTable(cityCode, locations, distType);
      setData(result);
      onCacheIdChange?.(result.cache_id ?? null);
    } finally {
      setLoading(false);
    }
  };

  const toggleSort = (key: SortKey) => {
    if (sortKey === key) {
      setSortAsc(!sortAsc);
    } else {
      setSortKey(key);
      setSortAsc(false);
    }
  };

  const sortedRows = data
    ? [...data.rows].sort((a, b) => {
        if (!sortKey) return 0;
        const diff = a[sortKey] - b[sortKey];
        return sortAsc ? diff : -diff;
      })
    : [];

  return (
    <div>
      <label className="block text-sm font-medium mb-3">Sensitive attribute</label>

      <div className="mb-4 rounded-lg border bg-muted/20 p-3 text-xs text-muted-foreground">
        The table will be calculated for {LOCATIONS_LABELS[locations].toLowerCase()}
        {" "}using the {DIST_TYPE_LABELS[distType].toLowerCase()} distance. Select the
        variable manually after reviewing the calculation.
      </div>

      {!data && (
        <div className="space-y-3">
          <Button onClick={handleFetch} disabled={loading} variant="outline" className="w-full">
            {loading ? (
              <Loader2 className="w-4 h-4 mr-2 animate-spin" />
            ) : (
              <Calculator className="w-4 h-4 mr-2" />
            )}
            {loading ? "Computing variable table..." : "Calculate variable table"}
          </Button>

          {loading && (
            <div className="border rounded-lg p-4 bg-muted/20 space-y-3">
              <div className="w-full h-2 bg-muted rounded-full overflow-hidden">
                <div className="h-full w-1/2 bg-primary animate-pulse rounded-full" />
              </div>

              <div className="space-y-1 text-xs text-muted-foreground">
                <p>Loading municipality data...</p>
                <p>Computing selected accessibility distances...</p>
                <p>Building the sensitive-variable comparison table...</p>
              </div>
            </div>
          )}
        </div>
      )}

      {data && (
        <div className="space-y-4">
          <div className="flex items-center justify-between gap-3 flex-wrap">
            <p className="text-xs text-muted-foreground">
              Select the sensitive attribute defining the sensitive and non-sensitive groups.
            </p>

            <Button onClick={handleFetch} disabled={loading} variant="outline" size="sm">
              {loading && <Loader2 className="w-4 h-4 mr-2 animate-spin" />}
              Recalculate
            </Button>
          </div>

          <div className="overflow-x-auto border rounded-lg">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-muted/50">
                  <th className="text-left p-3 font-medium">Attribute</th>

                  <th
                    className="text-right p-3 font-medium cursor-pointer select-none"
                    onClick={() => toggleSort("median")}
                  >
                    <span className="inline-flex items-center gap-1">
                      Sample median <ArrowUpDown className="w-3 h-3" />
                    </span>
                  </th>

                  <th
                    className="text-right p-3 font-medium cursor-pointer select-none"
                    onClick={() => toggleSort("greater")}
                  >
                    <span className="inline-flex items-center gap-1">
                      Avg. distance above median <ArrowUpDown className="w-3 h-3" />
                    </span>
                  </th>

                  <th
                    className="text-right p-3 font-medium cursor-pointer select-none"
                    onClick={() => toggleSort("lower")}
                  >
                    <span className="inline-flex items-center gap-1">
                      Avg. distance below median <ArrowUpDown className="w-3 h-3" />
                    </span>
                  </th>

                  <th
                    className="text-right p-3 font-medium cursor-pointer select-none"
                    onClick={() => toggleSort("variation")}
                  >
                    <span className="inline-flex items-center gap-1">
                      Relative difference (%) <ArrowUpDown className="w-3 h-3" />
                    </span>
                  </th>

                  <th className="p-3" />
                </tr>
              </thead>

              <tbody>
                {sortedRows.map((row) => {
                  const varNum = Number.parseInt(row.key.replace("x", ""), 10);
                  const isSelected = value === varNum;

                  return (
                    <tr
                      key={row.key}
                      className={`border-t transition-colors cursor-pointer ${
                        isSelected ? "bg-primary/5" : "hover:bg-muted/30"
                      }`}
                      onClick={() => onChange(varNum)}
                    >
                      <td className="p-3 font-medium">
                        {getAttributeLabel(row.key)}
                      </td>

                      <td className="text-right p-3 font-mono text-xs">
                        {row.median.toFixed(2)}
                      </td>

                      <td className="text-right p-3 font-mono text-xs">
                        {row.greater.toFixed(2)}
                      </td>

                      <td className="text-right p-3 font-mono text-xs">
                        {row.lower.toFixed(2)}
                      </td>

                      <td className="text-right p-3">
                        <span
                          className={`font-mono text-xs font-semibold ${
                            row.variation > 40
                              ? "text-destructive"
                              : row.variation > 25
                                ? "text-warning"
                                : "text-success"
                          }`}
                        >
                          {row.variation.toFixed(1)}%
                        </span>
                      </td>

                      <td className="p-3 text-center">
                        <div
                          className={`w-4 h-4 rounded-full border-2 ${
                            isSelected
                              ? "border-primary bg-primary"
                              : "border-muted-foreground/30"
                          }`}
                        />
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}
