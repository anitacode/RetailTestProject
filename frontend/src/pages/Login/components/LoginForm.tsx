import InfoMessage from "@/ui/InfoMessage";
import { useState, type SubmitEvent } from "react";
import { useBrand } from "@/hooks/useBrand";
import { useLogin } from "@/pages/Login/queries";
import { canSubmitLogin } from "@/pages/Login/utils";
import { errorMessage } from "@/api";

export default function LoginForm() {
  const [name, setName] = useState("");
  const session = useBrand();
  const sessionReady = session.data !== undefined;
  const login = useLogin();
  const busy = login.isPending;
  const error = session.error
    ? errorMessage(session.error)
    : login.error
      ? errorMessage(login.error)
      : "";
  function submit(event: SubmitEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!canSubmitLogin(name, sessionReady, busy)) return;
    login.mutate(name);
  }
  return (
    <form onSubmit={submit} className="w-full max-w-92.5 max-md:max-w-107.5">
      <label className="mx-0 mt-7.5 mb-[9px] block text-[14px] font-semibold" htmlFor="brand-name">
        Brand name
      </label>
      <input
        className="block w-full rounded-lg border border-solid border-slate-300 bg-white px-4 py-[15px] text-slate-800 outline-none focus:border-teal-700 focus:ring-3 focus:ring-teal-700/10"
        id="brand-name"
        autoComplete="organization"
        placeholder="e.g. The Prancing Pony"
        required
        maxLength={200}
        value={name}
        onChange={(e) => setName(e.target.value)}
      />
      {error && <InfoMessage message={error} variant="error" />}
      {session.error && (
        <button
          type="button"
          className="rounded-[7px] border border-solid border-slate-200 bg-white px-[15px] py-[9px] text-[13px] text-slate-700 hover:enabled:bg-slate-100"
          onClick={() => void session.refetch()}
          disabled={session.isFetching}
        >
          Try again
        </button>
      )}
      <button
        className="mt-4.5 flex w-full items-center justify-between rounded-lg border border-solid border-brand bg-brand px-5 py-3.5 font-semibold text-white hover:bg-brand-dark"
        disabled={!canSubmitLogin(name, sessionReady, busy)}
      >
        {busy ? "Opening your inbox…" : "Continue to alerts"} <span aria-hidden="true">↗</span>
      </button>
      <p className="mt-4 text-left text-sm leading-[1.7] text-slate-500">
        An existing brand name is all you need. No password or identity verification.
      </p>
    </form>
  );
}
