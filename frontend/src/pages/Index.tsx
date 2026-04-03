import { useState, useCallback, useEffect } from "react";
import type { Municipality, LocationsType, DistType, Job } from "@/types/api";
import { BIAS_VAR_LABELS, LOCATIONS_LABELS, DIST_TYPE_LABELS } from "@/types/api";
import { MunicipalitySearch } from "@/components/MunicipalitySearch";
import { AccessibilityOptions } from "@/components/AccessibilityOptions";
import { DistanceTypeOptions } from "@/components/DistanceTypeOptions";
import { BiasTable } from "@/components/BiasTable";
import { JobProgress } from "@/components/JobProgress";
import { ResultsGallery } from "@/components/ResultsGallery";
import { Button } from "@/components/ui/button";
import { createJob, subscribeToJob, getJobById } from "@/lib/api";
import { useNavigate } from "react-router-dom";
import {
  ArrowRight,
  ArrowLeft,
  Rocket,
  Download,
  FileArchive,
  CheckCircle2,
} from "lucide-react";

const Index = () => {
  const navigate = useNavigate();
  const [step, setStep] = useState(0);
  const [municipality, setMunicipality] = useState<Municipality | null>(null);
  const [locations, setLocations] = useState<LocationsType>("parks");
  const [distType, setDistType] = useState<DistType>("mean");
  const [biasVar, setBiasVar] = useState<number | null>(null);
  const [jobId, setJobId] = useState<string | null>(null);
  const [jobState, setJobState] = useState<Partial<Job>>({});
  const [finishedJob, setFinishedJob] = useState<Job | null>(null);

  const canNext = [!!municipality, true, true, biasVar !== null];

  const handleSubmit = useCallback(async () => {
    if (!municipality || biasVar === null) return;

    const id = await createJob({
      city_code: municipality.city_code,
      city_name: municipality.name,
      locations,
      dist_type: distType,
      bias_var: biasVar,
    });

    setJobId(id);
    setFinishedJob(null);
    setJobState({
      status: "queued",
      stage: "queued",
      progress: 0,
      logs: [],
    });
    setStep(4);

    subscribeToJob(id, (partial) => {
      setJobState((prev) => ({ ...prev, ...partial }));
    });
  }, [municipality, locations, distType, biasVar]);

  useEffect(() => {
    const loadFinishedJob = async () => {
      if (!jobId || jobState.status !== "succeeded") return;

      try {
        const job = await getJobById(jobId);
        setFinishedJob(job);
      } catch (error) {
        console.error("Error loading finished job:", error);
      }
    };

    loadFinishedJob();
  }, [jobId, jobState.status]);

  const steps = [
    { title: "Municipio", desc: "Selecciona el municipio de Andalucía" },
    { title: "Accesibilidad", desc: "Elige el tipo de localización" },
    { title: "Distancia", desc: "Selecciona cómo calcular la distancia" },
    { title: "Variable sensible", desc: "Elige la variable de desigualdad" },
  ];

  return (
    <div className="max-w-2xl mx-auto" px-6>
      <div className="mb-8">
        <h1 className="text-3xl font-bold mb-2">
          <span className="gradient-text">Unfair Urban Data</span>
        </h1>
        <p className="text-muted-foreground">
          Genera datasets de desigualdades urbanas para municipios de Andalucía.
          Selecciona las opciones y lanza el pipeline de procesamiento.
        </p>
      </div>

      {step < 4 && (
        <>
          <div className="flex items-center gap-2 mb-8">
            {steps.map((s, i) => (
              <div key={i} className="flex items-center gap-2">
                <button
                  onClick={() => i < step && setStep(i)}
                  className={`${
                    i < step
                      ? "step-badge-done"
                      : i === step
                      ? "step-badge"
                      : "step-badge-inactive"
                  }`}
                >
                  {i < step ? <CheckCircle2 className="w-4 h-4" /> : i + 1}
                </button>
                {i < steps.length - 1 && (
                  <div
                    className={`h-px w-8 ${
                      i < step ? "bg-success" : "bg-border"
                    }`}
                  />
                )}
              </div>
            ))}
          </div>

          <div className="bg-card border rounded-xl p-6 shadow-sm">
            <h2 className="text-lg font-semibold mb-1">{steps[step].title}</h2>
            <p className="text-sm text-muted-foreground mb-6">
              {steps[step].desc}
            </p>

            {step === 0 && (
              <MunicipalitySearch
                value={municipality}
                onChange={setMunicipality}
              />
            )}
            {step === 1 && (
              <AccessibilityOptions value={locations} onChange={setLocations} />
            )}
            {step === 2 && (
              <DistanceTypeOptions value={distType} onChange={setDistType} />
            )}
            {step === 3 && municipality && (
              <BiasTable
                cityCode={municipality.city_code}
                value={biasVar}
                onChange={setBiasVar}
              />
            )}

            <div className="flex justify-between mt-8">
              <Button
                variant="ghost"
                onClick={() => setStep(step - 1)}
                disabled={step === 0}
              >
                <ArrowLeft className="w-4 h-4 mr-1" /> Atrás
              </Button>

              {step < 3 ? (
                <Button
                  onClick={() => setStep(step + 1)}
                  disabled={!canNext[step]}
                >
                  Siguiente <ArrowRight className="w-4 h-4 ml-1" />
                </Button>
              ) : (
                <Button onClick={handleSubmit} disabled={!canNext[step]}>
                  <Rocket className="w-4 h-4 mr-1" /> Generar dataset
                </Button>
              )}
            </div>
          </div>
        </>
      )}

      {step === 4 && (
        <div className="space-y-6">
          <div className="bg-card border rounded-xl p-6 shadow-sm">
            <h2 className="text-lg font-semibold mb-4">Configuración</h2>
            <div className="grid grid-cols-2 gap-3 text-sm">
              <div>
                <span className="text-muted-foreground">Municipio:</span>
                <span className="ml-2 font-medium">
                  {municipality?.name} ({municipality?.city_code})
                </span>
              </div>
              <div>
                <span className="text-muted-foreground">Localizaciones:</span>
                <span className="ml-2 font-medium">
                  {LOCATIONS_LABELS[locations]}
                </span>
              </div>
              <div>
                <span className="text-muted-foreground">Distancia:</span>
                <span className="ml-2 font-medium">
                  {DIST_TYPE_LABELS[distType]}
                </span>
              </div>
              <div>
                <span className="text-muted-foreground">
                  Variable sensible:
                </span>
                <span className="ml-2 font-medium">
                  {biasVar !== null ? BIAS_VAR_LABELS[biasVar] : ""}
                </span>
              </div>
            </div>
          </div>

          <div className="bg-card border rounded-xl p-6 shadow-sm">
            <h2 className="text-lg font-semibold mb-4">Progreso</h2>
            <JobProgress job={jobState} />
          </div>

          {jobState.status === "succeeded" && finishedJob?.result && (
            <div className="bg-card border rounded-xl p-6 shadow-sm space-y-6">
              <div className="flex items-center justify-between">
                <h2 className="text-lg font-semibold">Resultados</h2>
                <div className="flex gap-2">
                  {finishedJob.result.rds_url && (
                    <Button variant="outline" size="sm" asChild>
                      <a href={finishedJob.result.rds_url} download>
                        <Download className="w-4 h-4 mr-1" /> .rds
                      </a>
                    </Button>
                  )}
                  {finishedJob.result.zip_url && (
                    <Button size="sm" asChild>
                      <a href={finishedJob.result.zip_url} download>
                        <FileArchive className="w-4 h-4 mr-1" /> .zip completo
                      </a>
                    </Button>
                  )}
                </div>
              </div>

              {finishedJob.result.images && (
                <ResultsGallery images={finishedJob.result.images} />
              )}

              <div className="flex gap-3">
                <Button
                  variant="outline"
                  onClick={() => navigate(`/jobs/${jobId}`)}
                >
                  Ver detalles completos
                </Button>
                <Button
                  variant="ghost"
                  onClick={() => {
                    setStep(0);
                    setJobId(null);
                    setJobState({});
                    setFinishedJob(null);
                  }}
                >
                  Nuevo dataset
                </Button>
              </div>
            </div>
          )}

          {jobState.status === "failed" && (
            <div className="bg-destructive/5 border border-destructive/20 rounded-xl p-6">
              <h3 className="font-semibold text-destructive mb-2">
                Error en el procesamiento
              </h3>
              <p className="text-sm text-muted-foreground mb-4">
                Puede deberse a que OSRM no está disponible o a un error en los
                datos de entrada.
              </p>
              <Button
                variant="outline"
                onClick={() => {
                  setStep(3);
                  setJobId(null);
                  setJobState({});
                  setFinishedJob(null);
                }}
              >
                Reintentar
              </Button>
            </div>
          )}
        </div>
      )}
    </div>
  );
};

export default Index;