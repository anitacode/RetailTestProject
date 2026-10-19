import type { Pagination } from "@/types";

export interface QueuedJob {
  id: string;
  job_class: string;
  queue: string;
  status: "queued" | "scheduled" | "running" | "retrying" | "completed" | "failed";
  attempts: number;
  created_at: string;
  scheduled_at: string | null;
  finished_at: string | null;
}

export interface JobsResponse {
  jobs: QueuedJob[];
  pagination: Pagination;
}
