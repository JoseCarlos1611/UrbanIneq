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
import { createJob, subscribeToJob, getJobById, resolveApiUrl } from "@/lib/api";
import { useNavigate } from "react-router-dom";
import {
  ArrowRight,
  ArrowLeft,
  Rocket,
  Download,
  FileArchive,
  CheckCircle2,
  Loader2,
} from "lucide-react";

const Index = () => {
  const navigate = useNavigate();

  const [step, setStep] = useState(0);
  const [municipality, setMunicipality] = useState<Municipality | null>(null);
  const [locations, setLocations] = useState<LocationsType>("parks");
  const [distType, setDistType] = useState<DistType>("mean");
  const [biasVar, setBiasVar] = useState<number | null>(null);
  const [biasCacheId, setBiasCacheId] = useState<string | null>(null);
  const [jobId, setJobId] = useState<string | null>(null);
  const [jobState, setJobState] = useState<Partial<Job>>({});
  const [finishedJob, setFinishedJob] = useState<Job | null>(null);
  const [creatingJob, setCreatingJob] = useState(false);

  const canNext = [!!municipality, true, true, biasVar !== null];

  const handleSubmit = useCallback(async () => {
    if (!municipality || biasVar === null || creatingJob) return;

    setCreatingJob(true);

    try {
      const id = await createJob({
        city_code: municipality.city_code,
        city_name: municipality.name,
        locations,
        dist_type: distType,
        bias_var: biasVar,
        cache_id: biasCacheId,
      });

      setJobId(id);
      setFinishedJob(null);
      setJobState({
        job_id: id,
        status: "queued",
        stage: "queued",
        progress: 0,
        logs: [
          {
            ts: new Date().toISOString(),
            level: "info",
            msg: "Job submitted. Waiting for processing to start.",
          },
        ],
      });
      setStep(4);

      subscribeToJob(id, (partial) => {
        setJobState((prev) => ({ ...prev, ...partial }));
      });
    } finally {
      setCreatingJob(false);
    }
  }, [municipality, locations, distType, biasVar, biasCacheId, creatingJob]);

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
    {
      title: "Municipality",
      desc: "Select the Andalusian municipality",
    },
    {
      title: "Accessibility",
      desc: "Select the type of urban facility or location",
    },
    {
      title: "Distance",
      desc: "Select how distances should be computed",
    },
    {
      title: "Sensitive attribute",
      desc: "Select the sensitive attribute defining the sensitive and non-sensitive groups",
    },
  ];

  return (
    <div className="max-w-2xl mx-auto px-6">
      <div className="mb-8">
        <h1 className="text-3xl font-bold mb-2">
          <span className="gradient-text">Urban inequality data</span>
        </h1>

        <p className="text-muted-foreground">
          Access and download urban inequality datasets for municipalities in
          Andalusia. Select the desired options and run the processing pipeline.
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
                locations={locations}
                distType={distType}
                value={biasVar}
                onChange={setBiasVar}
                onCacheIdChange={setBiasCacheId}
              />
            )}

            <div className="flex justify-between mt-8">
              <Button
                variant="ghost"
                onClick={() => setStep(step - 1)}
                disabled={step === 0 || creatingJob}
              >
                <ArrowLeft className="w-4 h-4 mr-1" />
                Back
              </Button>

              {step < 3 ? (
                <Button
                  onClick={() => setStep(step + 1)}
                  disabled={!canNext[step]}
                >
                  Next
                  <ArrowRight className="w-4 h-4 ml-1" />
                </Button>
              ) : (
                <Button
                  onClick={handleSubmit}
                  disabled={!canNext[step] || creatingJob}
                >
                  {creatingJob ? (
                    <Loader2 className="w-4 h-4 mr-1 animate-spin" />
                  ) : (
                    <Rocket className="w-4 h-4 mr-1" />
                  )}
                  {creatingJob ? "Starting job..." : "Get dataset"}
                </Button>
              )}
            </div>
          </div>
        </>
      )}

      {step === 4 && (
        <div className="space-y-6">
          <div className="bg-card border rounded-xl p-6 shadow-sm">
            <h2 className="text-lg font-semibold mb-4">Configuration</h2>

            <div className="grid grid-cols-2 gap-3 text-sm">
              <div>
                <span className="text-muted-foreground">Municipality:</span>
                <span className="ml-2 font-medium">
                  {municipality?.name} ({municipality?.city_code})
                </span>
              </div>

              <div>
                <span className="text-muted-foreground">Locations:</span>
                <span className="ml-2 font-medium">
                  {LOCATIONS_LABELS[locations]}
                </span>
              </div>

              <div>
                <span className="text-muted-foreground">Distance:</span>
                <span className="ml-2 font-medium">
                  {DIST_TYPE_LABELS[distType]}
                </span>
              </div>

              <div>
                <span className="text-muted-foreground">
                  Sensitive attribute:
                </span>
                <span className="ml-2 font-medium">
                  {biasVar !== null ? BIAS_VAR_LABELS[biasVar] : ""}
                </span>
              </div>
            </div>
          </div>

          <div className="bg-card border rounded-xl p-6 shadow-sm">
            <h2 className="text-lg font-semibold mb-4">Progress</h2>
            <JobProgress job={jobState} />
          </div>

          {jobState.status === "succeeded" && finishedJob?.result && (
            <div className="bg-card border rounded-xl p-6 shadow-sm space-y-6">
              <div className="flex items-center justify-between">
                <h2 className="text-lg font-semibold">Results</h2>

                <div className="flex gap-2">
                  {finishedJob.result.rds_url && (
                    <Button variant="outline" size="sm" asChild>
                      <a href={resolveApiUrl(finishedJob.result.rds_url)} download>
                        <Download className="w-4 h-4 mr-1" />
                        .rds
                      </a>
                    </Button>
                  )}

                  {finishedJob.result.zip_url && (
                    <Button size="sm" asChild>
                      <a href={resolveApiUrl(finishedJob.result.zip_url)} download>
                        <FileArchive className="w-4 h-4 mr-1" />
                        Complete .zip
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
                  View full details
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
                  New dataset
                </Button>
              </div>
            </div>
          )}

          {jobState.status === "failed" && (
            <div className="bg-destructive/5 border border-destructive/20 rounded-xl p-6">
              <h3 className="font-semibold text-destructive mb-2">
                Processing error
              </h3>

              <p className="text-sm text-muted-foreground mb-4">
                This may be caused by OSRM not being available or by an error in
                the input data.
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
                Retry
              </Button>
            </div>
          )}
        </div>
      )}
    </div>
  );
};

export default Index;
