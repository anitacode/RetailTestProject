import React from "react";
import { describe, it, expect, vi } from "vitest";
import { act, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router-dom";
import App from "@/App";
import { QueryClientProvider } from "@tanstack/react-query";
import { createQueryClient } from "@/queryClient";
import type { Brand } from "@/types";
import type { InventoryAlert, PriceAlert } from "@/pages/AlertList/types";

const brand: Brand = { id: 1, name: "The Prancing Pony" };
const alert: InventoryAlert = {
  alert_type: "alert_no_inventory",
  id: 42,
  seen_at: null,
  product: { id: 1, name: "Bree-Brewed Ale" },
  store: { id: 1, address: "Bree Market" },
  observed_at: "2026-10-19T12:00:00Z",
  observations: [
    { id: 1, quantity: 0, event_time: "2026-10-18T12:00:00Z" },
    { id: 2, quantity: -1, event_time: "2026-10-19T12:00:00Z" },
  ],
};
const response = (data: unknown, status = 200): Promise<Response> =>
  Promise.resolve(new Response(JSON.stringify(data), { status }));
function mount(path = "/") {
  const client = createQueryClient();
  client.setDefaultOptions({ queries: { retry: false, gcTime: 0 } });
  render(
    <QueryClientProvider client={client}>
      <MemoryRouter initialEntries={[path]}>
        <App />
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

describe("brand alert workspace", () => {
  it("shows login immediately but waits for the session before allowing submission", async () => {
    let resolveSession!: (response: Response) => void;
    const fetch = vi.spyOn(globalThis, "fetch").mockReturnValue(
      new Promise<Response>((resolve) => {
        resolveSession = resolve;
      }),
    );
    mount();
    await userEvent.type(screen.getByLabelText("Brand name"), brand.name);
    const submit = screen.getByRole("button", { name: /Continue to alerts/ });
    expect(submit).toBeDisabled();
    await userEvent.click(submit);
    expect(fetch).toHaveBeenCalledTimes(1);
    await act(async () => {
      resolveSession(await response({ brand: null, csrf_token: "token" }));
    });
    await waitFor(() => expect(submit).toBeEnabled());
  });

  it("retries a failed session request from the login page", async () => {
    vi.spyOn(globalThis, "fetch")
      .mockImplementationOnce(() => response({ error: "Session unavailable." }, 503))
      .mockImplementationOnce(() => response({ brand: null, csrf_token: "token" }));
    mount();
    await userEvent.type(screen.getByLabelText("Brand name"), brand.name);
    expect(await screen.findByRole("alert")).toHaveTextContent("Session unavailable.");
    expect(screen.getByRole("button", { name: /Continue to alerts/ })).toBeDisabled();
    await userEvent.click(screen.getByRole("button", { name: "Try again" }));
    await waitFor(() =>
      expect(screen.getByRole("button", { name: /Continue to alerts/ })).toBeEnabled(),
    );
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  });

  it("signs in by brand name, renders empty state, and sends a CSRF token", async () => {
    const fetch = vi.spyOn(globalThis, "fetch").mockImplementation((url, options) => {
      if (url === "/api/session")
        return response({ brand: options?.method === "POST" ? brand : null, csrf_token: "token" });
      return response({ alerts: [], pagination: { total: 0, page: 1, pages: 0 } });
    });
    mount();
    await userEvent.type(await screen.findByLabelText("Brand name"), brand.name);
    await userEvent.click(screen.getByRole("button", { name: /Continue to alerts/ }));
    expect(await screen.findByText("Nothing needs your attention yet")).toBeInTheDocument();
    expect(fetch).toHaveBeenCalledWith(
      "/api/session",
      expect.objectContaining({
        method: "POST",
        body: JSON.stringify({ name: brand.name }),
      }),
    );
    const loginCall = fetch.mock.calls.find(([, options]) => options?.method === "POST");
    expect(new Headers(loginCall?.[1]?.headers).get("X-CSRF-Token")).toBe("token");
  });

  it("keeps the alerts header while loading, then offers retry for a failed inbox request", async () => {
    let finishRequest!: (response: Response) => void;
    let retry = false;
    vi.spyOn(globalThis, "fetch").mockImplementation((url) => {
      if (url === "/api/session") return response({ brand, csrf_token: "token" });
      if (retry) return response({ alerts: [], pagination: { total: 0, page: 1, pages: 0 } });
      return new Promise<Response>((resolve) => {
        finishRequest = resolve;
      });
    });
    mount();
    expect(await screen.findByText("Loading your alerts…")).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "Alerts" })).toBeInTheDocument();
    await act(async () => {
      finishRequest(await response({ error: "Inbox unavailable" }, 503));
    });
    expect(await screen.findByRole("alert")).toHaveTextContent("Inbox unavailable");
    expect(screen.queryByText("Loading your alerts…")).not.toBeInTheDocument();
    retry = true;
    await userEvent.click(screen.getByRole("button", { name: "Try again" }));
    expect(await screen.findByText("Nothing needs your attention yet")).toBeInTheDocument();
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  });

  it("shows login errors without pretending login succeeded", async () => {
    vi.spyOn(globalThis, "fetch").mockImplementation((url, options) =>
      options?.method === "POST"
        ? response({ error: "Brand not found." }, 422)
        : response({ brand: null, csrf_token: "token" }),
    );
    mount();
    await userEvent.type(await screen.findByLabelText("Brand name"), "Missing");
    await userEvent.click(screen.getByRole("button", { name: /Continue/ }));
    expect(await screen.findByRole("alert")).toHaveTextContent("Brand not found.");
  });

  it("navigates from a paginated inbox to observation details", async () => {
    vi.spyOn(globalThis, "fetch").mockImplementation((url) => {
      if (url === "/api/session") return response({ brand, csrf_token: "token" });
      if (url === "/api/alerts/42/seen") return response({ seen_at: "2026-10-19T13:00:00Z" });
      if (url === "/api/alerts/42") return response({ alert });
      return response({
        alerts: [alert],
        pagination: { total: 21, page: String(url).includes("page=2") ? 2 : 1, pages: 2 },
      });
    });
    mount();
    await screen.findByText("Bree-Brewed Ale");
    await userEvent.click(screen.getByRole("button", { name: "Next →" }));
    expect(await screen.findByText("Page 2 of 2")).toBeInTheDocument();
    await userEvent.click(screen.getByText("Bree-Brewed Ale"));
    expect(await screen.findByText("What triggered this alert")).toBeInTheDocument();
    expect(screen.getByText("(-1)")).toBeInTheDocument();
  });

  it("marks a visited detail and removes its New badge without removing it from the inbox", async () => {
    let seenAt: string | null = null;
    const fetch = vi.spyOn(globalThis, "fetch").mockImplementation((url) => {
      if (url === "/api/session") return response({ brand, csrf_token: "token" });
      if (url === "/api/alerts/42/seen") {
        seenAt = "2026-10-19T13:00:00Z";
        return response({ seen_at: seenAt });
      }
      if (url === "/api/alerts/42") return response({ alert: { ...alert, seen_at: seenAt } });
      return response({
        alerts: [{ ...alert, seen_at: seenAt }],
        unseen_count: seenAt ? 0 : 1,
        pagination: { total: 21, page: 1, pages: 2 },
      });
    });
    mount();
    await screen.findByText("Bree-Brewed Ale");
    expect(screen.getByText("New", { exact: true })).toBeInTheDocument();
    expect(fetch.mock.calls.some(([url]) => String(url).endsWith("/seen"))).toBe(false);
    await userEvent.click(screen.getByText("Bree-Brewed Ale"));
    await waitFor(() => expect(seenAt).not.toBeNull());
    const seenCall = fetch.mock.calls.find(([url]) => String(url).endsWith("/seen"));
    expect(seenCall?.[1]?.method).toBe("PATCH");
    expect(new Headers(seenCall?.[1]?.headers).get("X-CSRF-Token")).toBe("token");
    await userEvent.click(screen.getByRole("link", { name: /all alerts/i }));
    await waitFor(() => expect(screen.queryByText("New", { exact: true })).not.toBeInTheDocument());
    expect(screen.getByText("Bree-Brewed Ale")).toBeInTheDocument();
    expect(screen.queryByText("New", { exact: true })).not.toBeInTheDocument();
    await userEvent.click(screen.getByText("Bree-Brewed Ale"));
    await screen.findByText("What triggered this alert");
    expect(fetch.mock.calls.filter(([url]) => String(url).endsWith("/seen"))).toHaveLength(1);
  });

  it("shows price alerts in the inbox with old and new prices and marks them seen", async () => {
    const priceAlert: PriceAlert = {
      ...alert,
      alert_type: "alert_price_change",
      observations: [
        { id: 1, event_time: "2026-10-18T12:00:00Z", amount: 10, currency: "USD" },
        { id: 2, event_time: "2026-10-19T12:00:00Z", amount: 12, currency: "USD" },
      ],
    };
    let seenAt: string | null = null;
    vi.spyOn(globalThis, "fetch").mockImplementation((url) => {
      if (url === "/api/session") return response({ brand, csrf_token: "token" });
      if (url === "/api/alerts/42/seen") {
        seenAt = "2026-10-19T13:00:00Z";
        return response({ seen_at: seenAt });
      }
      if (url === "/api/alerts/42") return response({ alert: { ...priceAlert, seen_at: seenAt } });
      return response({
        alerts: [{ ...priceAlert, seen_at: seenAt }],
        unseen_count: seenAt ? 0 : 1,
        pagination: { total: 1, page: 1, pages: 1 },
      });
    });
    mount();
    expect(await screen.findByText("Price change")).toBeInTheDocument();
    await userEvent.click(screen.getByText("Bree-Brewed Ale"));
    expect(await screen.findByText("PREVIOUS PRICE")).toBeInTheDocument();
    expect(screen.getByText("NEW PRICE")).toBeInTheDocument();
    expect(screen.getByText("10 USD")).toBeInTheDocument();
    expect(screen.getByText("12 USD")).toBeInTheDocument();
    expect(screen.queryByText(/Out of stock/)).not.toBeInTheDocument();
    await waitFor(() => expect(seenAt).not.toBeNull());
    await userEvent.click(screen.getByRole("link", { name: /all alerts/i }));
    await waitFor(() => expect(screen.queryByText("New", { exact: true })).not.toBeInTheDocument());
  });

  it("shows a retry when marking a detail as seen fails", async () => {
    let attempts = 0;
    vi.spyOn(globalThis, "fetch").mockImplementation((url) => {
      if (url === "/api/session") return response({ brand, csrf_token: "token" });
      if (url === "/api/alerts/42/seen") {
        attempts++;
        return attempts === 1
          ? response({ error: "Temporary failure" }, 503)
          : response({ seen_at: "2026-10-19T13:00:00Z" });
      }
      return response({ alert });
    });
    mount("/42");
    expect(await screen.findByRole("alert")).toHaveTextContent("Could not mark this alert as seen");
    expect(screen.getByText("What triggered this alert")).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: "Retry marking as seen" }));
    await waitFor(() => expect(screen.queryByRole("alert")).not.toBeInTheDocument());
    expect(attempts).toBe(2);
  });

  it("returns to login if the API session expires", async () => {
    vi.spyOn(globalThis, "fetch").mockImplementation((url) =>
      url === "/api/session"
        ? response({ brand, csrf_token: "token" })
        : response({ error: "Sign in." }, 401),
    );
    mount();
    await screen.findByRole("button", { name: /Sign out/ });
    expect(await screen.findByLabelText("Brand name")).toBeInTheDocument();
  });

  it("shows unavailable detail and handles logout", async () => {
    vi.spyOn(globalThis, "fetch").mockImplementation((url, options) =>
      url === "/api/session"
        ? response({ brand: options?.method === "DELETE" ? null : brand, csrf_token: "token" })
        : response({ error: "Record not found." }, 404),
    );
    mount("/999");
    expect(await screen.findByRole("alert")).toHaveTextContent("This alert is unavailable");
    await userEvent.click(screen.getByRole("button", { name: /Sign out/ }));
    expect(await screen.findByLabelText("Brand name")).toBeInTheDocument();
  });
});
