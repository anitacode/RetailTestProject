import InfoMessage from "@/ui/InfoMessage";
import Pagination from "@/component/Pagination";
import JobTable from "@/pages/QueueStatus/components/JobTable";
import type { JobsResponse } from "@/pages/QueueStatus/queries";

interface QueueContentProps {
  data: JobsResponse | undefined;
  hasError: boolean;
  page: number;
  onPageChange: (page: number) => void;
  onRetry: (id: string) => void;
  retryingId?: string;
}

export default function QueueContent({
  data,
  hasError,
  page,
  onPageChange,
  onRetry,
  retryingId,
}: QueueContentProps) {
  if (!data && hasError) return null;

  if (!data) return <p role="status">Loading jobs…</p>;

  if (data.jobs.length === 0) {
    return <InfoMessage message="No retained jobs for this brand." variant="info" />;
  }

  return (
    <>
      <JobTable jobs={data.jobs} onRetry={onRetry} retryingId={retryingId} />
      <div className="mt-auto shrink-0">
        <Pagination page={page} pages={data.pagination.pages} onPageChange={onPageChange} />
      </div>
    </>
  );
}
