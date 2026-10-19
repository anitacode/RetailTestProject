import { trackingEventsQuery } from "@/pages/TrackingEvents/queries";
import { jobsQuery } from "@/pages/QueueStatus/queries";
import { contactsQuery } from "@/pages/NotificationSettings/queries";
import type { ReactNode } from "react";
import { QueryClientProvider, QueryObserver } from "@tanstack/react-query";
import { act, renderHook } from "@testing-library/react";
import { afterEach, expect, it, vi } from "vitest";
import { alertsQuery } from "@/pages/AlertList/queries";
import { createQueryClient } from "@/queryClient";
import { sessionKey } from "@/queryKeys";
import { useSessionMutation } from "@/session/queries";
import type { SessionResponse } from "@/types";

const clients: ReturnType<typeof createQueryClient>[] = [];
function makeClient() {
  const client = createQueryClient();
  clients.push(client);
  return client;
}
afterEach(() => {
  clients.forEach((client) => client.clear());
  clients.length = 0;
  vi.useRealTimers();
});
const session: SessionResponse = { brand: { id: 1, name: "Brand one" }, csrf_token: "token" };
const result = {
  unseen_count: 0,
  alerts: [],
  pagination: { page: 1, per_page: 20, total: 0, pages: 0 },
};

it("deduplicates simultaneous reads and reuses fresh page data", async () => {
  const fetch = vi
    .spyOn(globalThis, "fetch")
    .mockResolvedValue(new Response(JSON.stringify(result)));
  const client = makeClient();
  await Promise.all([
    client.fetchQuery(alertsQuery(1, "1")),
    client.fetchQuery(alertsQuery(1, "1")),
  ]);
  await client.fetchQuery(alertsQuery(1, "1"));
  expect(fetch).toHaveBeenCalledTimes(1);
});

it("keeps separate caches for each brand and page", async () => {
  const fetch = vi
    .spyOn(globalThis, "fetch")
    .mockImplementation(async () => new Response(JSON.stringify(result)));
  const client = makeClient();
  await client.fetchQuery(alertsQuery(1, "1"));
  await client.fetchQuery(alertsQuery(1, "2"));
  await client.fetchQuery(alertsQuery(2, "1"));
  expect(fetch).toHaveBeenCalledTimes(3);
});

it("cancels fetches when a query is cancelled", async () => {
  let signal: AbortSignal | null | undefined;
  vi.spyOn(globalThis, "fetch").mockImplementation((_url, options) => {
    signal = options?.signal;
    return new Promise((_resolve, reject) =>
      signal?.addEventListener("abort", () => reject(new DOMException("Aborted", "AbortError"))),
    );
  });
  const client = makeClient();
  const pending = client.fetchQuery(alertsQuery(1, "1"));
  const assertion = expect(pending).rejects.toThrow();
  await client.cancelQueries({ queryKey: ["alerts"] });
  await assertion;
  expect(signal?.aborted).toBe(true);
});

it("clears alerts and signs out on 401 without retrying", async () => {
  const fetch = vi
    .spyOn(globalThis, "fetch")
    .mockResolvedValue(new Response(JSON.stringify({ error: "Sign in." }), { status: 401 }));
  const client = makeClient();
  client.setQueryData(sessionKey, session);
  client.setQueryData(alertsQuery(1, "2").queryKey, result);
  await expect(client.fetchQuery(alertsQuery(1, "1"))).rejects.toMatchObject({ status: 401 });
  expect(client.getQueryData<SessionResponse>(sessionKey)?.brand).toBeNull();
  expect(client.getQueriesData({ queryKey: ["alerts"] })).toHaveLength(0);
  expect(fetch).toHaveBeenCalledTimes(1);
});

it.each(["POST", "DELETE"] as const)(
  "clears previous brand data after a successful %s session mutation",
  async (method) => {
    const client = makeClient();
    client.setQueryData(sessionKey, session);
    client.setQueryData(alertsQuery(1, "1").queryKey, result);
    client.setQueryData(["contacts", 1, 1], { contacts: [] });
    client.setQueryData(["jobs", 1, 1], { jobs: [] });
    client.setQueryData(trackingEventsQuery(1, 1).queryKey, {
      tracking_events: [],
      pagination: result.pagination,
    });
    const next: SessionResponse = {
      csrf_token: "new-token",
      brand: method === "POST" ? { id: 2, name: "Brand two" } : null,
    };
    vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response(JSON.stringify(next)));
    const wrapper = ({ children }: { children: ReactNode }) => (
      <QueryClientProvider client={client}>{children}</QueryClientProvider>
    );
    const { result: mutation } = renderHook(() => useSessionMutation(method), { wrapper });
    await act(async () => {
      await mutation.current.mutateAsync("Brand two");
    });
    expect(client.getQueryData(sessionKey)).toEqual(next);
    expect(client.getQueriesData({ queryKey: ["alerts"] })).toHaveLength(0);
    expect(client.getQueriesData({ queryKey: ["contacts"] })).toHaveLength(0);
    expect(client.getQueriesData({ queryKey: ["jobs"] })).toHaveLength(0);
    expect(client.getQueriesData({ queryKey: ["trackingEvents"] })).toHaveLength(0);
  },
);

it("refetches active alerts every five seconds and stops after leaving the page", async () => {
  vi.useFakeTimers();
  const fetch = vi
    .spyOn(globalThis, "fetch")
    .mockImplementation(async () => new Response(JSON.stringify(result)));
  const client = makeClient();
  const observer = new QueryObserver(client, alertsQuery(1, "1"));
  const unsubscribe = observer.subscribe(() => {});
  await vi.advanceTimersByTimeAsync(0);
  expect(fetch).toHaveBeenCalledTimes(1);
  await vi.advanceTimersByTimeAsync(4_999);
  expect(fetch).toHaveBeenCalledTimes(1);
  await vi.advanceTimersByTimeAsync(1);
  expect(fetch).toHaveBeenCalledTimes(2);
  await vi.advanceTimersByTimeAsync(5_000);
  expect(fetch).toHaveBeenCalledTimes(3);
  unsubscribe();
  await vi.advanceTimersByTimeAsync(5_000);
  expect(fetch).toHaveBeenCalledTimes(3);
});

it("clears brand contact data when the contacts API reports an expired session", async () => {
  const client = makeClient();
  client.setQueryData(sessionKey, session);
  client.setQueryData(["contacts", 1, 2], { contacts: [{ name: "Private contact" }] });
  client.setQueryData(alertsQuery(1, "1").queryKey, result);
  vi.spyOn(globalThis, "fetch").mockImplementation(
    async () => new Response(JSON.stringify({ error: "Sign in." }), { status: 401 }),
  );
  await expect(client.fetchQuery(contactsQuery(1, 1))).rejects.toMatchObject({ status: 401 });
  expect(client.getQueryData<SessionResponse>(sessionKey)?.brand).toBeNull();
  expect(client.getQueriesData({ queryKey: ["contacts"] })).toHaveLength(0);
  expect(client.getQueriesData({ queryKey: ["alerts"] })).toHaveLength(0);
});

it("polls job status every five seconds while mounted and stops after leaving", async () => {
  vi.useFakeTimers();
  const fetch = vi
    .spyOn(globalThis, "fetch")
    .mockImplementation(
      async () => new Response(JSON.stringify({ jobs: [], pagination: result.pagination })),
    );
  const client = makeClient();
  const observer = new QueryObserver(client, jobsQuery(1, 1));
  const unsubscribe = observer.subscribe(() => {});
  await vi.advanceTimersByTimeAsync(0);
  expect(fetch).toHaveBeenCalledTimes(1);
  await vi.advanceTimersByTimeAsync(4999);
  expect(fetch).toHaveBeenCalledTimes(1);
  await vi.advanceTimersByTimeAsync(1);
  expect(fetch).toHaveBeenCalledTimes(2);
  unsubscribe();
  await vi.advanceTimersByTimeAsync(5000);
  expect(fetch).toHaveBeenCalledTimes(2);
});

it("clears tracking events and session after the tracking API returns 401", async () => {
  const client = makeClient();
  client.setQueryData(sessionKey, session);
  client.setQueryData(trackingEventsQuery(1, 2).queryKey, {
    tracking_events: [],
    pagination: result.pagination,
  });
  vi.spyOn(globalThis, "fetch").mockResolvedValue(
    new Response(JSON.stringify({ error: "Sign in." }), { status: 401 }),
  );
  await expect(client.fetchQuery(trackingEventsQuery(1, 1))).rejects.toMatchObject({ status: 401 });
  expect(client.getQueryData<SessionResponse>(sessionKey)?.brand).toBeNull();
  expect(client.getQueriesData({ queryKey: ["trackingEvents"] })).toHaveLength(0);
});
