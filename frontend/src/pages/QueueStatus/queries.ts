import { queryOptions, useMutation, useQueryClient } from "@tanstack/react-query";
import { request } from "@/api";
import { sessionKey } from "@/queryKeys";
import type { SessionResponse } from "@/types";
import type { JobsResponse } from "@/pages/QueueStatus/types";

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
