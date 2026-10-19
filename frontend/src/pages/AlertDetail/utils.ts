import { ApiError, errorMessage } from "@/api";
import type { AlertType } from "@/pages/AlertList/types";

export const observationTags = {
  alert_price_change: ["PREVIOUS PRICE", "NEW PRICE"],
  alert_no_inventory: ["FIRST CHECK", "CONFIRMING CHECK"],
} satisfies Record<AlertType, [string, string]>;

export function alertDetailError(error: unknown): string {
  return error instanceof ApiError && error.status === 404
    ? "This alert is unavailable. It may have changed after a historical observation was added."
    : error
      ? errorMessage(error)
      : "";
}
