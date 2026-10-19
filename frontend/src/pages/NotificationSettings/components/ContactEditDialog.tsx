import InfoMessage from "@/ui/InfoMessage";
import { useQuery } from "@tanstack/react-query";
import { contactQuery } from "@/pages/NotificationSettings/queries";
import { errorMessage } from "@/api";
import Dialog from "@/component/Dialog";
import ContactForm from "@/pages/NotificationSettings/components/ContactForm";

export default function ContactEditDialog({
  brandId,
  contactId,
  onClose,
  onSaved,
}: {
  brandId: number;
  contactId: string;
  onClose: () => void;
  onSaved: () => void;
}) {
  const query = useQuery(contactQuery(brandId, contactId));
  if (query.error) {
    return (
      <Dialog title="Edit contact" onClose={onClose}>
        <InfoMessage message={errorMessage(query.error)} variant="error" />
        <button
          type="button"
          onClick={() => void query.refetch()}
          disabled={query.isFetching}
          className="rounded-lg border border-solid border-slate-200 bg-white px-4 py-2"
        >
          Try again
        </button>
      </Dialog>
    );
  }

  if (!query.data) {
    return (
      <Dialog title="Edit contact" onClose={onClose}>
        <p role="status">Loading contact…</p>
      </Dialog>
    );
  }

  return (
    <ContactForm
      key={query.data.contact.id}
      brandId={brandId}
      contact={query.data.contact}
      onCancel={onClose}
      onSaved={onSaved}
      renderLayout={({ form, actions }) => (
        <Dialog title="Edit contact" onClose={onClose} footer={actions}>
          {form}
        </Dialog>
      )}
    />
  );
}
