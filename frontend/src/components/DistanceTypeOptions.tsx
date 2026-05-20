import type { DistType } from "@/types/api";
import { DIST_TYPE_LABELS } from "@/types/api";

interface Props {
  value: DistType;
  onChange: (v: DistType) => void;
}

const descriptions: Record<DistType, string> = {
  mean: "Average distance to all selected locations",
  min: "Distance to the nearest location",
  max: "Distance to the farthest location",
};

export function DistanceTypeOptions({ value, onChange }: Props) {
  return (
    <div>
      <label className="block text-sm font-medium mb-3">Distance type</label>
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
