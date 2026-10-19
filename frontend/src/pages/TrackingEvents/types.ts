import type { Pagination } from "@/types";

interface TrackingEventBase {
  id: number;
  event_time: string | null;
  product: { id: number; name: string };
  store: { id: number; address: string };
}

export type TrackingEvent = TrackingEventBase &
  (
    | { event_type: "inventory_presence"; value: { quantity: number } }
    | { event_type: "price_tracker"; value: { amount: number; currency: string } }
  );

export interface TrackingEventsResponse {
  tracking_events: TrackingEvent[];
  pagination: Pagination;
}

export type ObservedOrder = "asc" | "desc";
