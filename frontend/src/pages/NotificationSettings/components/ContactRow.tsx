import type { Contact } from "@/types";

export default function ContactRow({ contact, onEdit }: { contact: Contact; onEdit: () => void }) {
  return (
    <tr className="border-b border-slate-100">
      <td className="p-3 font-medium wrap-anywhere">{contact.name}</td>
      <td className="p-3 wrap-anywhere text-slate-600">{contact.email || "—"}</td>
      <td className="p-3 whitespace-nowrap text-slate-600">{contact.phone || "—"}</td>
      <td className="p-3">
        <div className="flex flex-wrap gap-2 text-xs">
          {contact.setup.alert_no_inventory && (
            <span className="rounded-full bg-teal-50 px-3 py-1 text-teal-800">Out of stock</span>
          )}
          {contact.setup.alert_price_change && (
            <span className="rounded-full bg-teal-50 px-3 py-1 text-teal-800">Price changes</span>
          )}
          {!contact.setup.alert_no_inventory && !contact.setup.alert_price_change && (
            <span className="text-slate-500">Notifications paused</span>
          )}
        </div>
      </td>
      <td className="p-3">
        <button
          type="button"
          onClick={onEdit}
          aria-label={`Edit ${contact.name}`}
          className="rounded-lg border border-solid border-slate-200 bg-white px-4 py-2 text-sm text-slate-700 hover:bg-slate-50"
        >
          Edit
        </button>
      </td>
    </tr>
  );
}
