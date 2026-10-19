import { queryOptions } from "@tanstack/react-query";
import { request } from "@/api";
import { alertsKey } from "@/queryKeys";
import type { AlertsResponse } from "@/types";

export const alertsQuery = (brandId: number, page: string) =>
  queryOptions({
    queryKey: [...alertsKey, brandId, "list", page],
    refetchInterval: 5_000,
    queryFn: ({ signal }) =>
      request<AlertsResponse>(`/alerts?page=${encodeURIComponent(page)}`, { signal }),
  });
