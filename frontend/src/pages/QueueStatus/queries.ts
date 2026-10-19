import { queryOptions, useMutation, useQueryClient } from "@tanstack/react-query";
import { request } from "@/api";
import { sessionKey } from "@/queryKeys";
import type { AlertsResponse, SessionResponse } from "@/types";

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
  pagination: AlertsResponse["pagination"];
}

export const jobsQuery = (brandId: number, page: number) =>
  queryOptions({
    queryKey: ["jobs", brandId, page],
    queryFn: ({ signal }) => request<JobsResponse>(`/queued_jobs?page=${page}`, { signal }),
    refetchInterval: 5_000,
  });

export function useRetryJob(brandId: number) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (id: string) =>
      request<{ status: "accepted" }>(`/queued_jobs/${encodeURIComponent(id)}/retry`, {
        method: "POST",
      }),
    onSettled: async () => {
      if (client.getQueryData<SessionResponse>(sessionKey)?.brand?.id !== brandId) return;
      await client.invalidateQueries({ queryKey: ["jobs", brandId] });
    },
  });
}
