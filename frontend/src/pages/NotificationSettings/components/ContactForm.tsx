import InfoMessage from "@/ui/InfoMessage";
import { contactFormInput, maskPhone } from "@/pages/NotificationSettings/utils";
import { useId, useState, type ReactNode, type SubmitEvent } from "react";
import { useSaveContact } from "@/pages/NotificationSettings/queries";
import { errorMessage } from "@/api";
import type { Contact } from "@/pages/NotificationSettings/types";

interface ContactFormProps {
  brandId: number;
  contact: Contact | null;
  onSaved: () => void;
  onCancel: () => void;
  renderLayout?: (content: { form: ReactNode; actions: ReactNode }) => ReactNode;
}

export default function ContactForm({
  brandId,
  contact,
  onSaved,
  onCancel,
  renderLayout,
}: ContactFormProps) {
  const id = useId();
  const [name, setName] = useState(contact?.name ?? "");
  const [email, setEmail] = useState(contact?.email ?? "");
  const [phone, setPhone] = useState(contact?.phone ?? "");
  const [setup, setSetup] = useState(
    contact?.setup ?? {
      alert_no_inventory: false,
      alert_price_change: false,
    },
  );
  const save = useSaveContact(brandId);
  function submit(event: SubmitEvent<HTMLFormElement>) {
    event.preventDefault();
    if (save.isPending) return;
    save.mutate(
      { id: contact?.id, contact: contactFormInput(name, email, phone, setup) },
      { onSuccess: onSaved },
    );
  }
  const form = (
    <form id={`${id}-form`} onSubmit={submit}>
      <fieldset disabled={save.isPending} className="m-0 min-w-0 border-0 p-0">
        <div className="grid gap-4 md:grid-cols-3">
          <label htmlFor={`${id}-name`} className="text-sm font-semibold">
            Name
            <input
              id={`${id}-name`}
              required
              value={name}
              onChange={(event) => setName(event.target.value)}
              className="mt-2 block w-full rounded-lg border border-solid border-slate-300 bg-white p-3 font-normal focus:outline-teal-700"
            />
          </label>
          <label htmlFor={`${id}-email`} className="text-sm font-semibold">
            Email
            <input
              id={`${id}-email`}
              type="email"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              className="mt-2 block w-full rounded-lg border border-solid border-slate-300 bg-white p-3 font-normal focus:outline-teal-700"
            />
          </label>
          <label htmlFor={`${id}-phone`} className="text-sm font-semibold">
            Phone
            <input
              id={`${id}-phone`}
              type="tel"
              inputMode="tel"
              autoComplete="tel"
              title="Use + followed by 8 to 15 digits, including the country code."
              placeholder="+12025550123"
              pattern="\+[1-9][0-9]{7,14}"
              value={phone}
              onChange={(event) => {
                const input = event.currentTarget;
                const raw = input.value;
                const cursor = input.selectionStart;
                const masked = maskPhone(raw);
                input.value = masked;
                if (cursor !== null) {
                  const nextCursor = maskPhone(raw.slice(0, cursor)).length;
                  input.setSelectionRange(nextCursor, nextCursor);
                }
                setPhone(masked);
              }}
              className="mt-2 block w-full rounded-lg border border-solid border-slate-300 bg-white p-3 font-normal focus:outline-teal-700"
            />
          </label>
        </div>
        <p className="mt-3 text-sm text-slate-600">
          Provide an email, a phone number with country code, or both. Each available channel
          receives the selected alerts.
        </p>
        <fieldset className="m-0 flex flex-wrap gap-5 rounded-lg border border-solid border-teal-200 bg-teal-50 p-4">
          <legend className="px-1 text-sm font-semibold">Alert preferences</legend>
          <label className="flex items-center gap-2 text-sm">
            <input
              type="checkbox"
              checked={setup.alert_no_inventory}
              onChange={(event) => setSetup({ ...setup, alert_no_inventory: event.target.checked })}
              className="accent-teal-700"
            />
            Out-of-stock alerts
          </label>
          <label className="flex items-center gap-2 text-sm">
            <input
              type="checkbox"
              checked={setup.alert_price_change}
              onChange={(event) => setSetup({ ...setup, alert_price_change: event.target.checked })}
              className="accent-teal-700"
            />
            Price-change alerts
          </label>
        </fieldset>
        {save.error && <InfoMessage message={errorMessage(save.error)} variant="error" />}
      </fieldset>
    </form>
  );
  const actions = (
    <div className="flex gap-3">
      <button
        type="submit"
        form={`${id}-form`}
        disabled={save.isPending || !name.trim() || (!email.trim() && !phone.trim())}
        className="rounded-lg border-0 bg-teal-700 px-4 py-3 font-semibold text-white hover:enabled:bg-teal-800"
      >
        {save.isPending ? "Saving…" : "Save contact"}
      </button>
      <button
        type="button"
        disabled={save.isPending}
        onClick={onCancel}
        className="rounded-lg border border-solid border-slate-300 bg-white px-4 py-3 text-slate-700"
      >
        Cancel
      </button>
    </div>
  );

  if (renderLayout) return renderLayout({ form, actions });

  return (
    <div className="mb-6">
      {form}
      <div className="mt-5">{actions}</div>
    </div>
  );
}
