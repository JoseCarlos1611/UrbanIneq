import { useState, useEffect, useRef, useMemo } from "react";
import { Input } from "@/components/ui/input";
import { searchMunicipalities, getAllMunicipalities } from "@/lib/api";
import type { Municipality } from "@/types/api";
import { MapPin, Search, Loader2 } from "lucide-react";

interface Props {
  value: Municipality | null;
  onChange: (m: Municipality | null) => void;
}

export function MunicipalitySearch({ value, onChange }: Props) {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<Municipality[]>([]);
  const [allMunicipalities, setAllMunicipalities] = useState<Municipality[]>([]);
  const [loading, setLoading] = useState(false);
  const [prefetching, setPrefetching] = useState(true);
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    let mounted = true;
    getAllMunicipalities()
      .then((data) => {
        if (mounted) setAllMunicipalities(data);
      })
      .catch(() => {
        // silent fallback to remote search
      })
      .finally(() => {
        if (mounted) setPrefetching(false);
      });

    return () => {
      mounted = false;
    };
  }, []);

  const localResults = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (q.length < 2 || allMunicipalities.length === 0) return [];
    return allMunicipalities
      .filter((m) => m.name.toLowerCase().includes(q) || m.city_code.includes(q))
      .slice(0, 12);
  }, [query, allMunicipalities]);

  useEffect(() => {
    if (query.length < 2) {
      setResults([]);
      setOpen(false);
      return;
    }

    if (allMunicipalities.length > 0) {
      setResults(localResults);
      setOpen(true);
      return;
    }

    setLoading(true);
    const timeout = setTimeout(async () => {
      try {
        const data = await searchMunicipalities(query);
        setResults(data);
        setOpen(true);
      } finally {
        setLoading(false);
      }
    }, 250);

    return () => clearTimeout(timeout);
  }, [query, allMunicipalities, localResults]);

  useEffect(() => {
    const handler = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, []);

  return (
    <div ref={ref} className="relative">
      <label className="block text-sm font-medium mb-2">Municipality</label>

      {value ? (
        <div className="flex items-center gap-3 p-3 bg-card border rounded-lg">
          <MapPin className="w-5 h-5 text-primary" />
          <div className="flex-1">
            <span className="font-medium">{value.name}</span>
            <span className="text-muted-foreground ml-2 text-sm">({value.city_code})</span>
          </div>
          <button
            onClick={() => {
              onChange(null);
              setQuery("");
              setOpen(false);
            }}
            className="text-sm text-muted-foreground hover:text-foreground transition-colors"
          >
            Change
          </button>
        </div>
      ) : (
        <>
          <div className="relative">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
            <Input
              placeholder="Search municipality (e.g., Seville, Málaga...)"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              onFocus={() => {
                if ((results.length > 0 || query.length >= 2) && !value) setOpen(true);
              }}
              className="pl-10"
            />
            {(loading || prefetching) && (
              <Loader2 className="absolute right-3 top-1/2 -translate-y-1/2 w-4 h-4 animate-spin text-muted-foreground" />
            )}
          </div>

          {open && results.length > 0 && (
            <div className="absolute z-50 w-full mt-1 bg-popover border rounded-lg shadow-lg max-h-72 overflow-y-auto">
              {results.map((m) => (
                <button
                  key={m.city_code}
                  className="w-full text-left px-4 py-3 hover:bg-accent/10 transition-colors flex items-center gap-3"
                  onClick={() => {
                    onChange(m);
                    setOpen(false);
                    setQuery("");
                  }}
                >
                  <MapPin className="w-4 h-4 text-primary/60" />
                  <span>{m.name}</span>
                  <span className="text-muted-foreground text-sm ml-auto">{m.city_code}</span>
                </button>
              ))}
            </div>
          )}

          {open && query.length >= 2 && !loading && !prefetching && results.length === 0 && (
            <div className="absolute z-50 w-full mt-1 bg-popover border rounded-lg shadow-lg p-4 text-sm text-muted-foreground">
              No municipalities found
            </div>
          )}
        </>
      )}
    </div>
  );
}
