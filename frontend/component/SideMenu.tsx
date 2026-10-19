import InfoMessage from "@/ui/InfoMessage";
import { Link, NavLink } from "react-router-dom";
import { errorMessage } from "@/api";
import { useSessionMutation } from "@/session/queries";
import { Mark } from "@/components/Feedback";
import { useBrand } from "@/hooks/useBrand";

export default function SideMenu() {
  const { data: brand } = useBrand();
  const logout = useSessionMutation("DELETE");
  if (!brand) return null;

  return (
    <aside className="sticky top-0 flex h-screen flex-col bg-slate-900 px-5.5 py-8.5 text-slate-50 max-lg:px-4 max-lg:py-7 max-md:static max-md:h-auto max-md:flex-row max-md:flex-wrap max-md:items-center max-md:justify-between max-md:px-5 max-md:py-4.5">
      <Link
        className="mx-0.5 my-0 flex items-center gap-2.5 font-heading text-[23px] font-bold tracking-[-1px] max-lg:text-[20px] max-md:text-[20px]"
        to="/"
      >
        <Mark /> stockroom
      </Link>
      <p className="mx-3 mt-12 mb-3 text-xs tracking-widest text-slate-300 max-md:hidden">
        WORKSPACE
      </p>
      <nav
        aria-label="Workspace"
        className="flex flex-col gap-1 max-md:order-last max-md:mt-4 max-md:w-full max-md:flex-row max-md:flex-wrap"
      >
        <NavLink
          end
          className="rounded-sm p-3 text-sm text-slate-100 hover:bg-slate-800 aria-[current=page]:bg-slate-800 aria-[current=page]:text-teal-200"
          to="/"
        >
          Alerts
        </NavLink>
        <NavLink
          className="rounded-sm p-3 text-sm text-slate-100 hover:bg-slate-800 aria-[current=page]:bg-slate-800 aria-[current=page]:text-teal-200"
          to="/settings"
        >
          Notification settings
        </NavLink>
        <NavLink
          className="rounded-sm p-3 text-sm text-slate-100 hover:bg-slate-800 aria-[current=page]:bg-slate-800 aria-[current=page]:text-teal-200"
          to="/jobs"
        >
          Queue status ↗
        </NavLink>
        <NavLink
          to="/tracking-events"
          className="rounded-sm p-3 text-sm text-slate-100 hover:bg-slate-800 aria-[current=page]:bg-slate-800 aria-[current=page]:text-teal-200"
        >
          Tracking events
        </NavLink>
      </nav>
      <div className="gap-2.5px-0 mt-auto flex w-full flex-col items-start gap-4">
        <div className="w-full">
          <strong className="block text-sm wrap-anywhere max-md:max-w-32.5 max-md:text-right max-md:text-[10px]">
            {brand.name}
          </strong>
          <button
            type="button"
            className="mt-2 rounded-sm border border-slate-600 bg-transparent p-2 text-xs text-slate-100 hover:enabled:bg-slate-800 disabled:opacity-50"
            onClick={() => logout.mutate(undefined)}
            disabled={logout.isPending}
          >
            {logout.isPending ? "Signing out…" : "Sign out ↗"}
          </button>
          {logout.error && <InfoMessage message={errorMessage(logout.error)} variant="error" />}
        </div>
      </div>
    </aside>
  );
}
