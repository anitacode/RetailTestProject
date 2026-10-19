import type { Pagination } from "@/types";

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
  pagination: Pagination;
}
