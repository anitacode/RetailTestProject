import InfoMessage from "@/ui/InfoMessage";
import QueueContent from "@/pages/QueueStatus/components/QueueContent";
import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { jobsQuery, useRetryJob } from "@/pages/QueueStatus/queries";
import { errorMessage } from "@/api";

export default function QueueStatus({ brandId }: { brandId: number }) {
  const [page, setPage] = useState(1);
  const retry = useRetryJob(brandId);
  const query = useQuery(jobsQuery(brandId, page));
  return (
    <section className="flex min-h-0 flex-1 flex-col overflow-hidden rounded-xl border border-solid border-slate-200 bg-white px-3 pt-3">
      <div className="shrink-0">
        <h2 className="mb-0 text-lg">Queue status</h2>
        <p className="text-sm text-slate-500">
          Your brand’s retained jobs. Updates every 5 seconds while this tab is active. Global
          import jobs and deleted sources are excluded.
        </p>
        {retry.error && <InfoMessage message={errorMessage(retry.error)} variant="error" />}
        {retry.isSuccess && (
          <p role="status" className="text-sm text-teal-700">
            Retry requested. The worker will process the job.
          </p>
        )}
        {query.error && (
          <div className="text-center">
            <InfoMessage message={errorMessage(query.error)} variant="error" />
            <button
              type="button"
              onClick={() => void query.refetch()}
              disabled={query.isFetching}
              className="underline"
            >
              Try again
            </button>
          </div>
        )}
      </div>
      <QueueContent
        data={query.data}
        hasError={query.isError}
        page={page}
        onPageChange={setPage}
        onRetry={(id) => retry.mutate(id)}
        retryingId={retry.isPending ? retry.variables : undefined}
      />
    </section>
  );
}
