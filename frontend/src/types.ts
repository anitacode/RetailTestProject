export interface Brand {
  id: number;
  name: string;
}

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

export interface SessionResponse {
  brand: Brand | null;
  csrf_token: string;
}

export interface AlertsResponse {
  unseen_count: number;
  alerts: Alert[];
  pagination: { page: number; per_page: number; total: number; pages: number };
}

export interface AlertResponse {
  alert: Alert;
}

export interface ContactPreferences {
  alert_no_inventory: boolean;
  alert_price_change: boolean;
}

export interface ContactInput {
  name: string;
  email: string | null;
  phone: string | null;
  setup: ContactPreferences;
}

export interface Contact extends ContactInput {
  id: number;
}

export interface ContactsResponse {
  contacts: Contact[];
  pagination: AlertsResponse["pagination"];
}

interface TrackingEventBase {
  id: number;
  event_time: string | null;
  product: { id: number; name: string };
  store: { id: number; address: string };
}

export type TrackingEvent = TrackingEventBase &
  (
    | { event_type: "inventory_presence"; value: { quantity: number } }
    | { event_type: "price_tracker"; value: { amount: number; currency: string } }
  );

export interface TrackingEventsResponse {
  tracking_events: TrackingEvent[];
  pagination: AlertsResponse["pagination"];
}
