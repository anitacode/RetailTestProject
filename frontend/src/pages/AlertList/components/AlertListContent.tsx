import Pagination from "@/component/Pagination";
import { useQuery } from "@tanstack/react-query";
import { useSearchParams } from "react-router-dom";
import AlertRow from "@/pages/AlertList/components/AlertRow";
import { alertsQuery } from "@/pages/AlertList/queries";
import { errorMessage } from "@/api";
import InfoMessage from "@/ui/InfoMessage";

export default function AlertListContent({ brandId }: { brandId: number }) {
  const [params, setParams] = useSearchParams();
  const page = params.get("page") || "1";
  const query = useQuery(alertsQuery(brandId, page));
  const data = query.data;

  if (query.error) {
    return (
      <div className="px-6 py-7.5 text-[14px] text-slate-500">
        <InfoMessage message={errorMessage(query.error)} variant="error" />
        <button
          className="rounded-sm border border-solid border-slate-200 bg-white px-3 py-3 text-base text-slate-700 hover:enabled:bg-slate-100"
          onClick={() => void query.refetch()}
          disabled={query.isFetching}
        >
          Try again
        </button>
      </div>
    );
  }

  if (!data) {
    return (
      <p className="px-6 py-7.5 text-[14px] text-slate-500" role="status">
        Loading your alerts…
      </p>
    );
  }

  if (data.alerts.length === 0) {
    return (
      <InfoMessage
        title="Nothing needs your attention yet"
        variant="info"
        message="You don't have any alerts at the moment."
      />
    );
  }

  return (
    <>
      <div
        className="min-h-0 flex-1 overflow-x-auto overflow-y-auto"
        tabIndex={0}
        role="region"
        aria-label="Alerts table"
      >
        <table className="w-full border-collapse text-left max-md:min-w-142.5">
          <thead className="sticky top-0 z-10 bg-slate-50">
            <tr>
              <th className="bg-slate-50 px-6 py-3 text-xs font-medium tracking-widest text-slate-500 uppercase">
                Product / Store
              </th>
              <th className="bg-slate-50 px-6 py-3 text-xs font-medium tracking-widest text-slate-500 uppercase">
                Signal
              </th>
              <th className="bg-slate-50 px-6 py-3 text-xs font-medium tracking-widest text-slate-500 uppercase">
                Observed
              </th>
              <th className="bg-slate-50 px-6 py-3 text-xs font-medium tracking-widest text-slate-500 uppercase">
                <span className="sr-only">View alert</span>
              </th>
            </tr>
          </thead>
          <tbody>
            {data.alerts.map((alert) => (
              <AlertRow key={alert.id} alert={alert} />
            ))}
          </tbody>
        </table>
      </div>
      <div className="shrink-0">
        <Pagination
          page={data.pagination.page}
          pages={data.pagination.pages}
          onPageChange={(page) => setParams({ page: String(page) })}
        />
      </div>
    </>
  );
}
