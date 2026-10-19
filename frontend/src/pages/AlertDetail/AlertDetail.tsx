import InfoMessage from "@/ui/InfoMessage";
import { alertDetailError, observationTags } from "@/pages/AlertDetail/utils";
import MarkAlertSeen from "@/pages/AlertDetail/components/MarkAlertSeen";
import { useQuery } from "@tanstack/react-query";
import { Link, useParams } from "react-router-dom";
import { alertQuery } from "@/pages/AlertDetail/queries";
import { dateTime } from "@/api";
import AlertTypeBadge from "@/ui/AlertTypeBadge";

export default function AlertDetail({ brandId }: { brandId: number }) {
  const { id = "" } = useParams();
  const query = useQuery(alertQuery(brandId, id));
  const alert = query.data?.alert;
  const error = alertDetailError(query.error);

  if (error) {
    return (
      <div className="px-[25px] py-7.5 text-[14px] text-slate-500">
        <InfoMessage message={error} variant="error" />
        <button
          className="rounded-[7px] border border-slate-200 bg-white px-[15px] py-[9px] text-[13px] text-slate-700 hover:enabled:bg-slate-100"
          onClick={() => void query.refetch()}
          disabled={query.isFetching}
        >
          Try again
        </button>
      </div>
    );
  }

  if (!alert) {
    return <p role="status">Loading alert…</p>;
  }

  return (
    <>
      {alert.seen_at === null && (
        <MarkAlertSeen key={alert.id} brandId={brandId} alertId={alert.id} />
      )}

      <div className="grid grid-cols-[1.3fr_1fr] gap-[25px] max-lg:grid-cols-[1fr] max-md:gap-[15px]">
        <section className="rounded-xl border border-slate-200 bg-white p-7.5 max-md:p-[23px]">
          <div className="flex items-center justify-between gap-5">
            <h1 className="mb-3.5 text-[36px] max-md:text-[28px]">{alert.product.name}</h1>
            <AlertTypeBadge type={alert.alert_type} />
          </div>
          <p className="mb-3 text-xs font-bold tracking-wider text-slate-500">THE OBSERVATIONS</p>
          <h2 className="text-xl">What triggered this alert</h2>
          <div className="mt-8">
            {alert.observations.map((event, index) => (
              <div
                className="relative flex gap-5 pb-8.5 first:before:absolute first:before:top-7.5 first:before:bottom-0 first:before:left-4 first:before:border-1 first:before:border-l first:before:border-dashed first:before:border-l-slate-200 first:before:content-[''] last:pb-0"
                key={event.id}
              >
                <span className="relative z-1 grid h-8 w-8 shrink-0 place-items-center rounded-full border border-solid border-teal-200 bg-teal-50 text-[12px] text-teal-700">
                  {index + 1}
                </span>
                <div>
                  <span className="mx-0 mt-1 mb-2 text-xs font-bold tracking-[1.8px] text-slate-500">
                    {observationTags[alert.alert_type][index]}
                  </span>
                  <h3 className="mx-0 mt-0 mb-[5px] text-[17px]">
                    {"amount" in event ? (
                      <>
                        {event.amount.toLocaleString(undefined, { maximumFractionDigits: 20 })}{" "}
                        {event.currency}
                      </>
                    ) : (
                      <>
                        Out of stock{" "}
                        <span className="font-normal text-slate-500">({event.quantity})</span>
                      </>
                    )}
                  </h3>
                  <time className="text-[11px] text-slate-500" dateTime={event.event_time}>
                    {dateTime(event.event_time)}
                  </time>
                </div>
              </div>
            ))}
            <Link className="inline-block text-[12px] text-teal-700" to="/">
              ← Back to all alerts
            </Link>
          </div>
        </section>
      </div>
    </>
  );
}
