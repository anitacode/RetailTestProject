import { useQuery } from "@tanstack/react-query";
import Pagination from "@/component/Pagination";
import { errorMessage } from "@/api";
import { trackingEventsQuery } from "@/pages/TrackingEvents/queries";
import TrackingEventsTable from "@/pages/TrackingEvents/components/TrackingEventsTable";

import type { ObservedOrder } from "@/pages/TrackingEvents/types";
import InfoMessage from "@/ui/InfoMessage";

interface Props {
  brandId: number;
  page: number;
  order: ObservedOrder;
  onOrderChange: () => void;
  onPageChange: (page: number) => void;
}

export default function TrackingEventsContent({
  brandId,
  page,
  order,
  onOrderChange,
  onPageChange,
}: Props) {
  const query = useQuery(trackingEventsQuery(brandId, page, order));
  if (query.error) {
    return (
      <div>
        <InfoMessage message={errorMessage(query.error)} variant="error" />
        <button
          type="button"
          onClick={() => void query.refetch()}
          disabled={query.isFetching}
          className="rounded border border-slate-300 px-3 py-2"
        >
          Try again
        </button>
      </div>
    );
  }
  if (!query.data) return <p role="status">Loading tracking events…</p>;
  const { tracking_events: events, pagination } = query.data;
  const controls = (
    <div className="mt-auto shrink-0">
      <Pagination page={page} pages={Math.max(1, pagination.pages)} onPageChange={onPageChange} />
    </div>
  );
  if (events.length === 0) {
    return (
      <>
        <InfoMessage message="No tracking events on this page." variant="info" />
        {controls}
      </>
    );
  }
  return (
    <>
      <TrackingEventsTable events={events} order={order} onOrderChange={onOrderChange} />
      {controls}
    </>
  );
}
