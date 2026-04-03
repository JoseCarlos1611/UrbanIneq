import type { LocationsType } from "@/types/api";
import { LOCATIONS_LABELS } from "@/types/api";
import { Trees, Building2, Hospital } from "lucide-react";

interface Props {
  value: LocationsType;
  onChange: (v: LocationsType) => void;
}

const icons: Record<LocationsType, React.ReactNode> = {
  parks: <Trees className="w-5 h-5" />,
  clinics_public: <Building2 className="w-5 h-5" />,
  clinics_any: <Hospital className="w-5 h-5" />,
};

const descriptions: Record<LocationsType, string> = {
  parks: "Parques y zonas verdes urbanas",
  clinics_public: "Solo centros sanitarios públicos",
  clinics_any: "Centros públicos y privados",
};

export function AccessibilityOptions({ value, onChange }: Props) {
  return (
    <div>
      <label className="block text-sm font-medium mb-3">Variable de accesibilidad</label>
      <div className="grid gap-3">
        {(Object.keys(LOCATIONS_LABELS) as LocationsType[]).map((key) => (
          <button
            key={key}
            onClick={() => onChange(key)}
            className={`flex items-center gap-4 p-4 rounded-lg border-2 transition-all text-left ${
              value === key
                ? "border-primary bg-primary/5"
                : "border-border hover:border-primary/30"
            }`}
          >
            <div className={`p-2 rounded-md ${value === key ? "bg-primary/10 text-primary" : "bg-muted text-muted-foreground"}`}>
              {icons[key]}
            </div>
            <div>
              <div className="font-medium text-sm">{LOCATIONS_LABELS[key]}</div>
              <div className="text-xs text-muted-foreground">{descriptions[key]}</div>
            </div>
          </button>
        ))}
      </div>
    </div>
  );
}
