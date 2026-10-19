import type { ContactPreferences, ContactInput } from "@/types";

export function contactFormInput(
  name: string,
  email: string,
  phone: string,
  setup: ContactPreferences,
): ContactInput {
  return { name, email: email || null, phone: phone || null, setup };
}

export function maskPhone(value: string): string {
  const digits = value
    .replace(/[^0-9]/g, "")
    .replace(/^0+/, "")
    .slice(0, 15);
  if (digits) return `+${digits}`;
  if (value.includes("+")) return "+";
  return "";
}
