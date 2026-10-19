import type { ComponentPropsWithoutRef } from "react";

const variants = {
  error: "border-red-200 bg-red-50 text-red-800",
  info: "border-sky-200 bg-sky-50 text-sky-800",
  warning: "border-amber-200 bg-amber-50 text-amber-800",
  success: "border-teal-200 bg-teal-50 text-teal-800",
};

export type BadgeVariant = keyof typeof variants;

type BadgeProps = ComponentPropsWithoutRef<"span"> & {
  variant?: BadgeVariant;
};

export default function Badge({
  variant = "info",
  className = "",
  children,
  ...props
}: BadgeProps) {
  return (
    <span
      {...props}
      className={`inline-block rounded-[5px] border border-solid px-[9px] py-[5px] text-[10px] whitespace-nowrap ${variants[variant]} ${className}`}
    >
      {children}
    </span>
  );
}
