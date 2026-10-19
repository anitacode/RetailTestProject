import { useSearchParams } from "react-router-dom";
import TrackingEventsContent from "@/pages/TrackingEvents/components/TrackingEventsContent";

export default function TrackingEvents({ brandId }: { brandId: number }) {
  const [params, setParams] = useSearchParams();
  const page = Number(params.get("page") || "1");
  const order = params.get("order") === "asc" ? "asc" : "desc";
  return (
    <section className="flex min-h-0 flex-1 flex-col overflow-hidden rounded-xl border border-slate-200 bg-white p-5 md:p-8">
      <div className="shrink-0">
        <h2 className="mb-0 text-lg">Tracking events</h2>
        <p className="text-sm text-slate-500">
          Inventory and price observations for your brand’s products and their stores.
        </p>
      </div>
      <TrackingEventsContent
        brandId={brandId}
        page={page}
        order={order}
        onOrderChange={() => setParams({ page: "1", order: order === "desc" ? "asc" : "desc" })}
        onPageChange={(next) => setParams({ page: String(next), order })}
      />
    </section>
  );
}
