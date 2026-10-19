import { useQuery } from "@tanstack/react-query";
import { errorMessage } from "@/api";
import Pagination from "@/component/Pagination";
import ContactTable from "@/pages/NotificationSettings/components/ContactTable";
import InfoMessage from "@/ui/InfoMessage";
import { contactsQuery } from "@/pages/NotificationSettings/queries";
import type { Contact } from "@/types";

interface ContactListProps {
  brandId: number;
  page: number;
  keyword: string;
  onEdit: (contact: Contact) => void;
  onPageChange: (page: number) => void;
}

export default function ContactList({
  brandId,
  page,
  keyword,
  onEdit,
  onPageChange,
}: ContactListProps) {
  const query = useQuery(contactsQuery(brandId, page, keyword));

  if (query.error) {
    return (
      <div>
        <InfoMessage message={errorMessage(query.error)} variant="error" />
        <button
          type="button"
          onClick={() => void query.refetch()}
          disabled={query.isFetching}
          className="rounded-lg border border-solid border-slate-200 bg-white px-4 py-2 text-sm"
        >
          Try again
        </button>
      </div>
    );
  }

  if (!query.data) {
    return (
      <p role="status" className="text-slate-500">
        Loading contacts…
      </p>
    );
  }

  const { contacts, pagination } = query.data;
  const paginationControls = (
    <div className="mt-auto shrink-0">
      <Pagination page={page} pages={Math.max(1, pagination.pages)} onPageChange={onPageChange} />
    </div>
  );

  if (contacts.length === 0 && keyword) {
    return (
      <>
        <InfoMessage message="No contacts match your search." variant="info" />
        {paginationControls}
      </>
    );
  }

  if (contacts.length === 0) {
    return (
      <>
        <InfoMessage message="No contacts yet. Add a contact to receive alerts." variant="info" />
        {paginationControls}
      </>
    );
  }

  return (
    <>
      <ContactTable contacts={contacts} onEdit={onEdit} />
      {paginationControls}
    </>
  );
}
