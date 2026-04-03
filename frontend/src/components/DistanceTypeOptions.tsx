import type { DistType } from "@/types/api";
import { DIST_TYPE_LABELS } from "@/types/api";

interface Props {
  value: DistType;
  onChange: (v: DistType) => void;
}

const descriptions: Record<DistType, string> = {
  mean: "Promedio de distancias a todas las localizaciones",
  min: "Distancia al punto más cercano",
  max: "Distancia al punto más lejano",
};

export function DistanceTypeOptions({ value, onChange }: Props) {
  return (
    <div>
      <label className="block text-sm font-medium mb-3">Tipo de distancia</label>
      <div className="grid grid-cols-3 gap-3">
        {(Object.keys(DIST_TYPE_LABELS) as DistType[]).map((key) => (
          <button
            key={key}
            onClick={() => onChange(key)}
            className={`p-4 rounded-lg border-2 transition-all text-center ${
              value === key
                ? "border-primary bg-primary/5"
                : "border-border hover:border-primary/30"
            }`}
          >
            <div className="font-semibold text-lg">{DIST_TYPE_LABELS[key]}</div>
            <div className="text-xs text-muted-foreground mt-1">{descriptions[key]}</div>
          </button>
        ))}
      </div>
    </div>
  );
}
