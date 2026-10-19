import ContactRow from "@/pages/NotificationSettings/components/ContactRow";
import type { Contact } from "@/pages/NotificationSettings/types";

interface ContactTableProps {
  contacts: Contact[];
  onEdit: (contact: Contact) => void;
}

export default function ContactTable({ contacts, onEdit }: ContactTableProps) {
  return (
    <div
      className="min-h-0 flex-1 overflow-x-auto overflow-y-auto"
      tabIndex={0}
      role="region"
      aria-label="Notification contacts"
    >
      <table className="w-full border-collapse text-left text-sm">
        <thead className="sticky top-0 z-10 bg-slate-50 text-slate-600">
          <tr>
            {["Name", "Email", "Phone", "Alert preferences", "Actions"].map((label) => (
              <th key={label} scope="col" className="p-3 font-medium">
                {label}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {contacts.map((contact) => (
            <ContactRow key={contact.id} contact={contact} onEdit={() => onEdit(contact)} />
          ))}
        </tbody>
      </table>
    </div>
  );
}
