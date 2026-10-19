import { Mark } from "@/components/Feedback";

export default function LoginIntro() {
  return (
    <>
      <div className="flex items-center gap-2.5 font-heading text-[23px] font-bold tracking-[-1px]">
        <Mark /> stockroom
      </div>
      <div>
        <p className="mb-3 text-sm font-bold tracking-wider text-teal-200 max-md:hidden">
          A clearer view of your shelves
        </p>
        <h1 className="mx-0 my-6 text-5xl leading-[1.08] tracking-[-3px] max-md:mx-0 max-md:my-6.5 max-md:text-[42px] max-md:tracking-[-1.6px]">
          Know what’s
          <br className="max-md:hidden" />
          missing.
          <br className="max-md:hidden" />
          <em className="text-teal-300 not-italic max-md:block">Act sooner.</em>
        </h1>
        <p className="mb-[55px] max-w-90 text-[15px] leading-[1.9] text-slate-300 max-md:hidden">
          Inventory signals for your brand, in one quiet place. See where products need attention
          and the observations behind every alert.
        </p>
      </div>
      <div className="flex items-center gap-2.5 text-[11px] text-slate-300 max-md:hidden">
        <span className="h-1.5 w-1.5 rounded-full bg-teal-300" /> Two inventory checks. One clear
        signal.
      </div>
    </>
  );
}
