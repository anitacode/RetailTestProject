import Dialog from "@/component/Dialog";
import ContactForm from "@/pages/NotificationSettings/components/ContactForm";

interface ContactCreateDialogProps {
  brandId: number;
  onClose: () => void;
  onSaved: () => void;
}

export default function ContactCreateDialog({
  brandId,
  onClose,
  onSaved,
}: ContactCreateDialogProps) {
  return (
    <ContactForm
      brandId={brandId}
      contact={null}
      onCancel={onClose}
      onSaved={onSaved}
      renderLayout={({ form, actions }) => (
        <Dialog title="Add contact" onClose={onClose} footer={actions}>
          {form}
        </Dialog>
      )}
    />
  );
}
