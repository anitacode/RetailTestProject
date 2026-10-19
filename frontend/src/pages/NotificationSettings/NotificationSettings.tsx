import InfoMessage from "@/ui/InfoMessage";
import { useNavigate, useParams } from "react-router-dom";
import ContactEditDialog from "@/pages/NotificationSettings/components/ContactEditDialog";
import { useEffect, useState } from "react";
import ContactCreateDialog from "@/pages/NotificationSettings/components/ContactCreateDialog";
import ContactList from "@/pages/NotificationSettings/components/ContactList";

export default function NotificationSettings({ brandId }: { brandId: number }) {
  const navigate = useNavigate();
  const { contactId } = useParams();
  const [creating, setCreating] = useState(false);
  const [search, setSearch] = useState("");
  const [filter, setFilter] = useState({ keyword: "", page: 1 });
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    if (search.trim() === filter.keyword) return;
    const timer = window.setTimeout(() => setFilter({ keyword: search.trim(), page: 1 }), 500);
    return () => window.clearTimeout(timer);
  }, [search, filter.keyword]);

  return (
    <section className="flex min-h-0 flex-1 flex-col overflow-hidden rounded-xl border border-solid border-slate-200 bg-white px-3 pt-3">
      <div className="mb-5 flex shrink-0 flex-wrap items-center justify-between gap-4">
        <div>
          <h2 className="mb-0 text-lg">Notification settings</h2>
          <p className="shrink-0 text-sm text-slate-500">
            SMS and email delivery are simulated in this demo. Preferences apply to future
            notifications.
          </p>
        </div>
        <div className="flex">
          <input
            id="contact-search"
            aria-label="Search contacts"
            type="search"
            maxLength={200}
            placeholder="Search by name, email, or phone"
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            className="block w-full min-w-[280px] rounded-lg border border-slate-300 bg-white p-3 focus:outline-teal-700"
          />
        </div>
        <button
          type="button"
          onClick={() => {
            setCreating(true);
            setSaved(false);
          }}
          className="rounded-lg border-0 bg-teal-700 px-4 py-3 font-semibold text-white hover:bg-teal-800"
        >
          Add contact
        </button>
      </div>
      {contactId && (
        <ContactEditDialog
          key={contactId}
          brandId={brandId}
          contactId={contactId}
          onClose={() => navigate("/settings")}
          onSaved={() => {
            navigate("/settings", { replace: true });
            setSaved(true);
          }}
        />
      )}
      {saved && <InfoMessage message="Contact saved." variant="success" compact />}
      {creating && !contactId && (
        <ContactCreateDialog
          brandId={brandId}
          onClose={() => setCreating(false)}
          onSaved={() => {
            setSearch("");
            setFilter({ keyword: "", page: 1 });
            setCreating(false);
            setSaved(true);
          }}
        />
      )}

      <ContactList
        brandId={brandId}
        page={filter.page}
        keyword={filter.keyword}
        onEdit={(contact) => {
          setCreating(false);
          navigate(`/settings/${contact.id}`);
          setSaved(false);
        }}
        onPageChange={(next) => {
          setFilter((current) => ({ ...current, page: next }));
          setCreating(false);
        }}
      />
    </section>
  );
}
