import { useState } from "react";
import type { BiasTableResponse, BiasRow } from "@/types/api";
import { BIAS_VAR_LABELS } from "@/types/api";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { ArrowUpDown, Sparkles, Loader2 } from "lucide-react";
import { fetchBiasTable } from "@/lib/api";

interface Props {
  cityCode: string;
  value: number | null;
  onChange: (v: number) => void;
}

type SortKey = "variation" | "u" | null;

export function BiasTable({ cityCode, value, onChange }: Props) {
  const [data, setData] = useState<BiasTableResponse | null>(null);
  const [loading, setLoading] = useState(false);
  const [sortKey, setSortKey] = useState<SortKey>(null);
  const [sortAsc, setSortAsc] = useState(false);

  const handleFetch = async () => {
    setLoading(true);
    const result = await fetchBiasTable(cityCode);
    setData(result);
    setLoading(false);
  };

  const toggleSort = (key: SortKey) => {
    if (sortKey === key) setSortAsc(!sortAsc);
    else { setSortKey(key); setSortAsc(false); }
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
      <label className="block text-sm font-medium mb-3">Variable sensible (bias)</label>

      {!data && (
        <Button onClick={handleFetch} disabled={loading} variant="outline" className="w-full">
          {loading ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : <Sparkles className="w-4 h-4 mr-2" />}
          Calcular recomendación
        </Button>
      )}

      {data && (
        <div className="space-y-4">
          <div className="overflow-x-auto border rounded-lg">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-muted/50">
                  <th className="text-left p-3 font-medium">Variable</th>
                  <th className="text-right p-3 font-medium">Lower</th>
                  <th className="text-right p-3 font-medium">Greater</th>
                  <th className="text-right p-3 font-medium cursor-pointer select-none" onClick={() => toggleSort("u")}>
                    <span className="inline-flex items-center gap-1">U <ArrowUpDown className="w-3 h-3" /></span>
                  </th>
                  <th className="text-right p-3 font-medium cursor-pointer select-none" onClick={() => toggleSort("variation")}>
                    <span className="inline-flex items-center gap-1">Variación (%) <ArrowUpDown className="w-3 h-3" /></span>
                  </th>
                  <th className="text-right p-3 font-medium">Mediana</th>
                  <th className="p-3"></th>
                </tr>
              </thead>
              <tbody>
                {sortedRows.map((row) => {
                  const varNum = parseInt(row.key.replace("x", ""));
                  const isSuggested = varNum === data.suggested;
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
                        <span className="flex items-center gap-2">
                          {row.label}
                          {isSuggested && (
                            <Badge className="bg-accent text-accent-foreground text-[10px] px-1.5 py-0">
                              sugerida
                            </Badge>
                          )}
                        </span>
                      </td>
                      <td className="text-right p-3 font-mono text-xs">{row.lower.toFixed(2)}</td>
                      <td className="text-right p-3 font-mono text-xs">{row.greater.toFixed(2)}</td>
                      <td className="text-right p-3 font-mono text-xs">{row.u.toFixed(3)}</td>
                      <td className="text-right p-3">
                        <span className={`font-mono text-xs font-semibold ${
                          row.variation > 40 ? "text-destructive" : row.variation > 25 ? "text-warning" : "text-success"
                        }`}>
                          {row.variation.toFixed(1)}%
                        </span>
                      </td>
                      <td className="text-right p-3 font-mono text-xs">{row.median.toFixed(2)}</td>
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

          {data.suggested && !value && (
            <Button onClick={() => onChange(data.suggested)} className="w-full">
              <Sparkles className="w-4 h-4 mr-2" />
              Usar variable sugerida: {BIAS_VAR_LABELS[data.suggested]}
            </Button>
          )}
        </div>
      )}
    </div>
  );
}
