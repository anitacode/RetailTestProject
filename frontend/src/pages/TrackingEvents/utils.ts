import { dateTime } from "@/api";
import type { TrackingEvent } from "@/pages/TrackingEvents/types";

export function observationValue(event: TrackingEvent): string {
  if (event.event_type === "price_tracker") {
    return `${event.value.amount.toLocaleString(undefined, { maximumFractionDigits: 20 })} ${event.value.currency}`;
  }
  const status = event.value.quantity > 0 ? "In stock" : "Out of stock";
  return `${status} (${event.value.quantity.toLocaleString()})`;
}

export function observationTime(time: string | null): string {
  if (!time) return "Undated";
  return dateTime(time);
}
