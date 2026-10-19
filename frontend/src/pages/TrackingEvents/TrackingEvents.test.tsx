import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { QueryClientProvider } from "@tanstack/react-query";
import { MemoryRouter } from "react-router-dom";
import { expect, it, vi } from "vitest";
import App from "@/App";
import { createQueryClient } from "@/queryClient";

const response = (data: unknown, status = 200) => new Response(JSON.stringify(data), { status });
function mount(path = "/tracking-events") {
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

it("opens tracking events from the sidebar and paginates inventory and prices", async () => {
  vi.spyOn(globalThis, "fetch").mockImplementation(async (url) => {
    if (url === "/api/session")
      return response({ brand: { id: 1, name: "Brand" }, csrf_token: "token" });
    if (String(url).startsWith("/api/tracking_events")) {
      const page =
        new URL(String(url), "http://localhost").searchParams.get("page") === "2" ? 2 : 1;
      const event = {
        id: page,
        product: { id: 1, name: "Tea" },
        store: { id: 1, address: "Shared shop" },
        event_time: null,
      };
      const observation =
        page === 1
          ? { event_type: "inventory_presence", value: { quantity: 7 } }
          : { event_type: "price_tracker", value: { amount: 11.99, currency: "USD" } };
      return response({
        tracking_events: [{ ...event, ...observation }],
        pagination: { page, pages: 2, total: 21, per_page: 20 },
      });
    }
    return response({ alerts: [], unseen_count: 0, pagination: { page: 1, pages: 0, total: 0 } });
  });
  mount("/");
  const link = await screen.findByRole("link", { name: "Tracking events" });
  await userEvent.click(link);
  expect(await screen.findByText("In stock (7)")).toBeInTheDocument();
  expect(screen.getByText("Shared shop")).toBeInTheDocument();
  expect(screen.getByText("Undated")).toBeInTheDocument();
  expect(link).toHaveAttribute("aria-current", "page");
  await userEvent.click(screen.getByRole("button", { name: "Next →" }));
  expect(await screen.findByText("11.99 USD")).toBeInTheDocument();
  expect(screen.getByRole("button", { name: "Next →" })).toBeDisabled();
});

it("retries failed loading and handles an empty collection", async () => {
  let failed = true;
  vi.spyOn(globalThis, "fetch").mockImplementation(async (url) => {
    if (url === "/api/session")
      return response({ brand: { id: 1, name: "Brand" }, csrf_token: "token" });
    if (failed) return response({ error: "Events unavailable" }, 503);
    return response({
      tracking_events: [],
      pagination: { page: 1, pages: 0, total: 0, per_page: 20 },
    });
  });
  mount();
  expect(await screen.findByRole("alert")).toHaveTextContent("Events unavailable");
  failed = false;
  await userEvent.click(screen.getByRole("button", { name: "Try again" }));
  expect(await screen.findByText("No tracking events on this page.")).toBeInTheDocument();
  expect(screen.getByRole("button", { name: "Next →" })).toBeDisabled();
});

it("toggles observed sorting from page three, resets the page and preserves order during pagination", async () => {
  const fetch = vi.spyOn(globalThis, "fetch").mockImplementation(async (url) => {
    if (url === "/api/session")
      return response({ brand: { id: 1, name: "Brand" }, csrf_token: "token" });
    const params = new URL(String(url), "http://localhost").searchParams;
    return response({
      tracking_events: [
        {
          id: 1,
          product: { id: 1, name: "Tea" },
          store: { id: 1, address: "Shop" },
          event_time: null,
          event_type: "inventory_presence",
          value: { quantity: 7 },
        },
      ],
      pagination: { page: Number(params.get("page")), pages: 3, total: 41, per_page: 20 },
    });
  });
  mount("/tracking-events?page=3");
  const sort = await screen.findByRole("button", { name: "Observed: sort oldest first" });
  expect(sort.closest("th")).toHaveAttribute("aria-sort", "descending");
  await userEvent.click(sort);
  const ascending = await screen.findByRole("button", { name: "Observed: sort newest first" });
  expect(ascending.closest("th")).toHaveAttribute("aria-sort", "ascending");
  expect(fetch).toHaveBeenCalledWith("/api/tracking_events?page=1&order=asc", expect.anything());
  await userEvent.click(screen.getByRole("button", { name: "Next →" }));
  await screen.findByText("Page 2 of 3");
  expect(fetch).toHaveBeenCalledWith("/api/tracking_events?page=2&order=asc", expect.anything());
  await userEvent.click(screen.getByRole("button", { name: "Observed: sort newest first" }));
  await screen.findByRole("button", { name: "Observed: sort oldest first" });
  expect(fetch).toHaveBeenCalledWith("/api/tracking_events?page=1&order=desc", expect.anything());
});
