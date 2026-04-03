import { useState } from "react";
import type { JobImages } from "@/types/api";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import { Download, Maximize2 } from "lucide-react";

interface Props {
  images: JobImages;
}

const IMAGE_LABELS: Record<string, string> = {
  greenzones: "Zonas Verdes",
  clinics_public: "Centros Públicos",
  clinics_any: "Todos los Centros",
  y: "Mapa de Distancias (Y)",
  svar: "Variable Sensible",
};

const API_BASE = import.meta.env.VITE_API_BASE_URL ?? "http://localhost:8080";

function resolveImageUrl(url: string): string {
  if (!url) return "";
  if (url.startsWith("http://") || url.startsWith("https://")) return url;
  return `${API_BASE}${url}`;
}

export function ResultsGallery({ images }: Props) {
  const [fullscreen, setFullscreen] = useState<string | null>(null);

  const entries = Object.entries(images)
    .filter(([, url]) => !!url)
    .map(([key, url]) => [key, resolveImageUrl(url as string)] as [string, string]);

  return (
    <>
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
        {entries.map(([key, url]) => (
          <div key={key} className="bg-card border rounded-lg overflow-hidden card-hover">
            <div className="aspect-[4/3] bg-muted relative group">
              <img
                src={url}
                alt={IMAGE_LABELS[key] || key}
                className="w-full h-full object-cover"
              />
              <div className="absolute inset-0 bg-foreground/0 group-hover:bg-foreground/20 transition-all flex items-center justify-center gap-2 opacity-0 group-hover:opacity-100">
                <button
                  onClick={() => setFullscreen(url)}
                  className="p-2 bg-card rounded-md shadow-md hover:bg-muted transition-colors"
                >
                  <Maximize2 className="w-4 h-4" />
                </button>
                <a
                  href={url}
                  download
                  className="p-2 bg-card rounded-md shadow-md hover:bg-muted transition-colors"
                >
                  <Download className="w-4 h-4" />
                </a>
              </div>
            </div>
            <div className="p-3">
              <h4 className="font-medium text-sm">{IMAGE_LABELS[key] || key}</h4>
            </div>
          </div>
        ))}
      </div>

      <Dialog open={!!fullscreen} onOpenChange={() => setFullscreen(null)}>
        <DialogContent className="w-full max-w-7xl px-6 lg:px-8 p-2">
          <DialogTitle className="sr-only">Vista ampliada del mapa</DialogTitle>
          {fullscreen && (
            <img
              src={fullscreen}
              alt="Mapa ampliado"
              className="w-full rounded"
            />
          )}
        </DialogContent>
      </Dialog>
    </>
  );
}