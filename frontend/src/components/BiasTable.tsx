import { useMemo, useState } from "react";
import type { BiasTableResponse } from "@/types/api";
import { BIAS_ATTRIBUTE_LABELS, BIAS_VAR_LABELS } from "@/types/api";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { ArrowUpDown, Sparkles, Loader2 } from "lucide-react";
import { fetchBiasTable } from "@/lib/api";

interface Props {
  cityCode: string;
  value: number | null;
  onChange: (v: number) => void;
}

type SortKey = "variation" | "median" | "greater" | "lower" | null;

function getAttributeNumber(key: string): number {
  return parseInt(key.replace(/[^0-9]/g, ""), 10);
}

function isEligibleSuggestedAttribute(attributeNumber: number, aboveMedian: number, belowMedian: number): boolean {
  if (attributeNumber === 2) return aboveMedian < belowMedian;
  return [1, 3, 4, 5, 6, 7].includes(attributeNumber) && aboveMedian > belowMedian;
}

function getSuggestedAttribute(data: BiasTableResponse): number | null {
  const eligibleRows = data.rows
    .map((row) => ({ ...row, attributeNumber: getAttributeNumber(row.key) }))
    .filter((row) => isEligibleSuggestedAttribute(row.attributeNumber, row.greater, row.lower));

  const rowsToRank = eligibleRows.length > 0
    ? eligibleRows
    : data.rows.map((row) => ({ ...row, attributeNumber: getAttributeNumber(row.key) }));

  const suggestedRow = rowsToRank.reduce<typeof rowsToRank[number] | null>((best, row) => {
    if (!best) return row;
    return row.variation > best.variation ? row : best;
  }, null);

  return suggestedRow?.attributeNumber ?? data.suggested ?? null;
}

export function BiasTable({ cityCode, value, onChange }: Props) {
  const [data, setData] = useState<BiasTableResponse | null>(null);
  const [loading, setLoading] = useState(false);
  const [sortKey, setSortKey] = useState<SortKey>("variation");
  const [sortAsc, setSortAsc] = useState(false);

  const handleFetch = async () => {
    setLoading(true);
    const result = await fetchBiasTable(cityCode);
    setData(result);
    setLoading(false);
  };

  const toggleSort = (key: SortKey) => {
    if (sortKey === key) setSortAsc(!sortAsc);
    else {
      setSortKey(key);
      setSortAsc(false);
    }
  };

  const suggestedAttribute = useMemo(() => (data ? getSuggestedAttribute(data) : null), [data]);

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
      <p className="text-xs text-muted-foreground mb-3">
        Select the sensitive attribute defining the sensitive and non-sensitive groups.
      </p>

      {!data && (
        <Button onClick={handleFetch} disabled={loading} variant="outline" className="w-full">
          {loading ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : <Sparkles className="w-4 h-4 mr-2" />}
          Get a recommendation
        </Button>
      )}

      {data && (
        <div className="space-y-4">
          <div className="overflow-x-auto border rounded-lg">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-muted/50">
                  <th className="text-left p-3 font-medium">Attribute</th>
                  <th className="text-right p-3 font-medium cursor-pointer select-none" onClick={() => toggleSort("median")}>
                    <span className="inline-flex items-center gap-1">Sample median <ArrowUpDown className="w-3 h-3" /></span>
                  </th>
                  <th className="text-right p-3 font-medium cursor-pointer select-none" onClick={() => toggleSort("greater")}>
                    <span className="inline-flex items-center gap-1">Avg. distance (above median) <ArrowUpDown className="w-3 h-3" /></span>
                  </th>
                  <th className="text-right p-3 font-medium cursor-pointer select-none" onClick={() => toggleSort("lower")}>
                    <span className="inline-flex items-center gap-1">Avg. distance (below median) <ArrowUpDown className="w-3 h-3" /></span>
                  </th>
                  <th className="text-right p-3 font-medium cursor-pointer select-none" onClick={() => toggleSort("variation")}>
                    <span className="inline-flex items-center gap-1">Relative difference (%) <ArrowUpDown className="w-3 h-3" /></span>
                  </th>
                  <th className="p-3"></th>
                </tr>
              </thead>
              <tbody>
                {sortedRows.map((row) => {
                  const attributeNumber = getAttributeNumber(row.key);
                  const isSuggested = attributeNumber === suggestedAttribute;
                  const isSelected = value === attributeNumber;
                  return (
                    <tr
                      key={row.key}
                      className={`border-t transition-colors cursor-pointer ${
                        isSelected ? "bg-primary/5" : "hover:bg-muted/30"
                      }`}
                      onClick={() => onChange(attributeNumber)}
                    >
                      <td className="p-3 font-medium">
                        <span className="flex items-center gap-2">
                          {BIAS_ATTRIBUTE_LABELS[attributeNumber] ?? row.label}
                          {isSuggested && (
                            <Badge className="bg-accent text-accent-foreground text-[10px] px-1.5 py-0">
                              suggested
                            </Badge>
                          )}
                        </span>
                      </td>
                      <td className="text-right p-3 font-mono text-xs">{row.median.toFixed(2)}</td>
                      <td className="text-right p-3 font-mono text-xs">{row.greater.toFixed(2)}</td>
                      <td className="text-right p-3 font-mono text-xs">{row.lower.toFixed(2)}</td>
                      <td className="text-right p-3">
                        <span className={`font-mono text-xs font-semibold ${
                          row.variation > 40 ? "text-destructive" : row.variation > 25 ? "text-warning" : "text-success"
                        }`}>
                          {row.variation.toFixed(1)}%
                        </span>
                      </td>
                      <td className="p-3 text-center">
                        <div className={`w-4 h-4 rounded-full border-2 ${
                          isSelected ? "border-primary bg-primary" : "border-muted-foreground/30"
                        }`} />
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>

          {suggestedAttribute && !value && (
            <Button onClick={() => onChange(suggestedAttribute)} className="w-full">
              <Sparkles className="w-4 h-4 mr-2" />
              Use suggested variable: {BIAS_VAR_LABELS[suggestedAttribute]}
            </Button>
          )}
        </div>
      )}
    </div>
  );
}
