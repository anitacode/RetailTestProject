import { dateTime } from "@/api";

export function jobTime(value: string | null): string {
  return value ? dateTime(value) : "—";
}
