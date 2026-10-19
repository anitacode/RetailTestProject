import { useEffect, useId, useRef, type ReactNode } from "react";

interface DialogProps {
  title: string;
  children: ReactNode;
  footer?: ReactNode;
  onClose: () => void;
}

export default function Dialog({ title, children, footer, onClose }: DialogProps) {
  const ref = useRef<HTMLDialogElement>(null);
  const titleId = useId();
  useEffect(() => {
    const dialog = ref.current!;
    const overflow = document.body.style.overflow;
    dialog.showModal();
    document.body.style.overflow = "hidden";
    return () => {
      dialog.close();
      document.body.style.overflow = overflow;
    };
  }, []);
  return (
    <dialog
      ref={ref}
      aria-labelledby={titleId}
      onCancel={(event) => {
        event.preventDefault();
        onClose();
      }}
      className="m-auto max-h-[90dvh] w-[calc(100%-2rem)] max-w-3xl overflow-y-auto rounded-xl border border-solid border-slate-200 bg-white p-3 text-slate-800 shadow-xl backdrop:bg-slate-900/50"
    >
      <div className="mb-4 flex items-center justify-between gap-4 border-b border-slate-100 pb-3">
        <h2 id={titleId} className="m-0 text-lg">
          {title}
        </h2>
        <button
          type="button"
          onClick={onClose}
          aria-label="Close dialog"
          className="rounded-lg border-0 bg-slate-100 px-3 py-1 text-slate-600"
        >
          ✕
        </button>
      </div>
      {children}
      {footer && <footer className="mt-6 border-t border-slate-200 pt-3">{footer}</footer>}
    </dialog>
  );
}
