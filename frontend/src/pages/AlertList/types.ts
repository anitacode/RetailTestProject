import type { Pagination } from "@/types";

export interface InventoryObservation {
  id: number;
  event_time: string;
  quantity: number;
}

export type AlertType = "alert_no_inventory" | "alert_price_change";

interface AlertBase {
  seen_at: string | null;
  id: number;
  observed_at: string;
  product: { id: number; name: string };
  store: { id: number; address: string };
}

export interface InventoryAlert extends AlertBase {
  alert_type: "alert_no_inventory";
  observations: InventoryObservation[];
}

export interface PriceObservation {
  id: number;
  event_time: string;
  amount: number;
  currency: string;
}

export interface PriceAlert extends AlertBase {
  alert_type: "alert_price_change";
  observations: PriceObservation[];
}

export type Alert = InventoryAlert | PriceAlert;

export interface AlertsResponse {
  unseen_count: number;
  alerts: Alert[];
  pagination: Pagination;
}
