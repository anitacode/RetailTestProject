import type { TrackingEvent } from "@/types";
import { observationValue, observationTime } from "@/pages/TrackingEvents/utils";

import type { ObservedOrder } from "@/pages/TrackingEvents/utils";

const eventLabels = { price_tracker: "Price", inventory_presence: "Inventory" };

interface Props {
  events: TrackingEvent[];
  order: ObservedOrder;
  onOrderChange: () => void;
}

export default function TrackingEventsTable({ events, order, onOrderChange }: Props) {
  return (
    <div
      className="min-h-0 flex-1 overflow-x-auto overflow-y-auto"
      tabIndex={0}
      role="region"
      aria-label="Tracking events table"
    >
      <table className="w-full border-collapse text-left text-sm">
        <thead className="sticky top-0 z-10 bg-slate-50 text-slate-600">
          <tr>
            {["Product", "Store", "Type", "Observation"].map((label) => (
              <th key={label} className="p-3 font-medium">
                {label}
              </th>
            ))}
            <th
              className="p-3 font-medium"
              aria-sort={order === "desc" ? "descending" : "ascending"}
            >
              <button
                type="button"
                onClick={onOrderChange}
                className="inline-flex items-center gap-2 rounded border-0 bg-transparent hover:text-teal-700 focus-visible:outline-2 focus-visible:outline-teal-700"
                aria-label={
                  order === "desc" ? "Observed: sort oldest first" : "Observed: sort newest first"
                }
              >
                Observed <span aria-hidden="true">{order === "desc" ? "↓" : "↑"}</span>
              </button>
            </th>
          </tr>
        </thead>
        <tbody>
          {events.map((event) => (
            <tr key={event.id} className="border-b border-slate-100">
              <td className="p-3">
                <strong className="block">{event.product.name}</strong>
                <small className="text-slate-500">#{event.id}</small>
              </td>
              <td className="p-3">{event.store.address}</td>
              <td className="p-3">{eventLabels[event.event_type]}</td>
              <td className="p-3 whitespace-nowrap">{observationValue(event)}</td>
              <td className="p-3 whitespace-nowrap">{observationTime(event.event_time)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
