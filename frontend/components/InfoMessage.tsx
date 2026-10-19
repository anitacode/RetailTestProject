import type { BadgeVariant } from "@/ui/Badge";

const variants = {
  error: {
    colors: "border-red-200 bg-red-50 text-red-800",
    icon: <path d="m9 9 6 6m0-6-6 6" />,
  },
  info: {
    colors: "border-sky-200 bg-sky-50 text-sky-800",
    icon: <path d="M12 11v6m0-10v.01" />,
  },
  warning: {
    colors: "border-amber-200 bg-amber-50 text-amber-800",
    icon: <path d="M12 7v6m0 4v.01" />,
  },
  success: {
    colors: "border-teal-200 bg-teal-50 text-teal-800",
    icon: <path d="m8 12 3 3 5-6" />,
  },
};

interface InfoMessageProps {
  title?: string;
  compact?: boolean;
  message: string;
  variant: BadgeVariant;
}

export default function InfoMessage({
  title,
  message,
  variant,
  compact = false,
}: InfoMessageProps) {
  const { colors, icon } = variants[variant];

  return (
    <div
      role={variant === "error" ? "alert" : "status"}
      className={
        compact
          ? `mb-2 flex shrink-0 items-center gap-3 rounded-lg border p-2 text-left ${colors}`
          : "m-auto flex max-w-127.5 flex-col items-center px-6 py-15 text-center"
      }
    >
      <span
        className={`inline-grid shrink-0 place-items-center rounded-full border ${colors} ${compact ? "h-8 w-8" : "mb-4.5 h-11 w-11"}`}
      >
        <svg
          aria-hidden="true"
          className="h-6 w-6"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
          strokeLinecap="round"
          strokeLinejoin="round"
        >
          <circle cx="12" cy="12" r="9" />
          {icon}
        </svg>
      </span>
      <div className="min-w-0">
        {title && (
          <h3
            className={
              compact
                ? "mb-1 text-sm font-semibold wrap-anywhere"
                : "mb-2.5 text-base wrap-anywhere"
            }
          >
            {title}
          </h3>
        )}
        <p
          className={
            compact ? "m-0 text-sm wrap-anywhere" : "m-0 text-base wrap-anywhere text-slate-500"
          }
        >
          {message}
        </p>
      </div>
    </div>
  );
}
