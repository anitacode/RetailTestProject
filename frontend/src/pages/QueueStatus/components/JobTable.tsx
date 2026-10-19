import type { QueuedJob } from "@/pages/QueueStatus/queries";
import { jobTime } from "@/pages/QueueStatus/utils";

interface JobTableProps {
  jobs: QueuedJob[];
  onRetry: (id: string) => void;
  retryingId?: string;
}

export default function JobTable({ jobs, onRetry, retryingId }: JobTableProps) {
  return (
    <div
      className="min-h-0 flex-1 overflow-x-auto overflow-y-auto"
      tabIndex={0}
      role="region"
      aria-label="Queue jobs"
    >
      <table className="w-full border-collapse text-left text-sm">
        <thead className="sticky top-0 z-10 bg-slate-50 text-slate-600">
          <tr>
            {["Job", "Queue", "Status", "Attempts", "Scheduled", "Finished", "Actions"].map(
              (label) => (
                <th key={label} className="p-3 font-medium">
                  {label}
                </th>
              ),
            )}
          </tr>
        </thead>
        <tbody>
          {jobs.map((job) => (
            <tr key={job.id} className="border-b border-slate-100">
              <td className="p-3">
                <span className="block">{job.job_class}</span>
                <small className="text-slate-500">{job.id}</small>
              </td>
              <td className="p-3">{job.queue}</td>
              <td className="p-3">
                <span
                  className={
                    job.status === "failed"
                      ? "rounded bg-red-50 px-2 py-1 text-red-700"
                      : "rounded bg-slate-100 px-2 py-1 text-slate-700"
                  }
                >
                  {job.status}
                </span>
              </td>
              <td className="p-3">{job.attempts}</td>
              <td className="p-3 whitespace-nowrap">{jobTime(job.scheduled_at)}</td>
              <td className="p-3 whitespace-nowrap">{jobTime(job.finished_at)}</td>
              <td className="p-3">
                {job.status === "failed" && (
                  <button
                    type="button"
                    className="rounded border border-slate-300 px-3 py-1 text-teal-700 hover:enabled:bg-teal-50 disabled:opacity-50"
                    onClick={() => onRetry(job.id)}
                    disabled={retryingId !== undefined}
                    aria-label={`Retry ${job.job_class} ${job.id}`}
                  >
                    {retryingId === job.id ? "Retrying…" : "Retry"}
                  </button>
                )}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
