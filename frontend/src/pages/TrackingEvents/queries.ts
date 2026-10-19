import { queryOptions } from "@tanstack/react-query";
import { request } from "@/api";
import type { TrackingEventsResponse } from "@/pages/TrackingEvents/types";

import type { ObservedOrder } from "@/pages/TrackingEvents/types";

export const trackingEventsQuery = (brandId: number, page: number, order: ObservedOrder = "desc") =>
  queryOptions({
    queryKey: ["trackingEvents", brandId, page, order],
    queryFn: ({ signal }) =>
      request<TrackingEventsResponse>(`/tracking_events?page=${page}&order=${order}`, { signal }),
  });
