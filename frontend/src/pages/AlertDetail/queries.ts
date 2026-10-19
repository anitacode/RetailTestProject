import { queryOptions, useMutation, useQueryClient } from "@tanstack/react-query";
import { request } from "@/api";
import { sessionKey, alertsKey } from "@/queryKeys";
import type { AlertResponse, SessionResponse } from "@/types";

export const alertQuery = (brandId: number, id: string) =>
  queryOptions({
    queryKey: [...alertsKey, brandId, "detail", id],
    refetchInterval: 5_000,
    queryFn: ({ signal }) =>
      request<AlertResponse>(`/alerts/${encodeURIComponent(id)}`, { signal }),
  });

export function useMarkAlertSeen(brandId: number) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (id: number) =>
      request<{ seen_at: string }>(`/alerts/${id}/seen`, { method: "PATCH" }),
    onSuccess: async ({ seen_at }, id) => {
      const detailKey = alertQuery(brandId, String(id)).queryKey;
      await client.cancelQueries({ queryKey: detailKey });
      // A request completing after logout must not recreate the old brand's cache.
      if (client.getQueryData<SessionResponse>(sessionKey)?.brand?.id !== brandId) return;
      client.setQueryData<AlertResponse>(detailKey, (data) =>
        data ? { alert: { ...data.alert, seen_at } } : undefined,
      );
      await client.invalidateQueries({ queryKey: [...alertsKey, brandId, "list"] });
    },
  });
}
