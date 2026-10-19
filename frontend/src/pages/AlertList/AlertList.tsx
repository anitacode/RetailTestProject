import AlertListContent from "@/pages/AlertList/components/AlertListContent";

export default function AlertList({ brandId }: { brandId: number }) {
  return (
    <section className="flex min-h-0 flex-1 flex-col overflow-hidden rounded-xl border border-solid border-slate-200 bg-white">
      <div className="flex shrink-0 items-center justify-between gap-5 px-3 py-3">
        <h2 className="m-0 text-lg">Alerts</h2>
        <span className="text-xs text-slate-500 max-md:text-xs">
          Updates automatically every 5 seconds while this tab is active.
        </span>
      </div>
      <AlertListContent brandId={brandId} />
    </section>
  );
}
