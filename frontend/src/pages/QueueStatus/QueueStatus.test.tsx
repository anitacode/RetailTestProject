import { act, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { QueryClientProvider } from "@tanstack/react-query";
import { MemoryRouter } from "react-router-dom";
import { expect, it, vi } from "vitest";
import App from "@/App";
import { createQueryClient } from "@/queryClient";

const response = (data: unknown, status = 200) => new Response(JSON.stringify(data), { status });

function mount() {
  const client = createQueryClient();
  client.setDefaultOptions({ queries: { retry: false, gcTime: 0 } });
  render(
    <QueryClientProvider client={client}>
      <MemoryRouter initialEntries={["/jobs"]}>
        <App />
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

it("retries failed jobs with CSRF, prevents duplicate clicks, and refreshes the list", async () => {
  let status = "failed";
  let resolveRetry!: (response: Response) => void;
  const fetch = vi.spyOn(globalThis, "fetch").mockImplementation(async (url, options) => {
    if (url === "/api/session")
      return response({ brand: { id: 1, name: "Brand" }, csrf_token: "token" });
    if (options?.method === "POST")
      return new Promise<Response>((resolve) => {
        resolveRetry = resolve;
      });
    return response({
      jobs: [
        { id: "failed-job", job_class: "Alerts::ReconcileJob", status, attempts: 1 },
        {
          id: "completed-job",
          job_class: "Alerts::ReconcileJob",
          status: "completed",
          attempts: 1,
        },
      ],
      pagination: { page: 1, pages: 1, total: 2 },
    });
  });
  mount();
  const retry = await screen.findByRole("button", { name: /Retry Alerts/ });
  expect(screen.getAllByRole("button", { name: /Retry Alerts/ })).toHaveLength(1);
  await userEvent.click(retry);
  expect(retry).toBeDisabled();
  const call = fetch.mock.calls.find(([, options]) => options?.method === "POST");
  expect(call?.[0]).toBe("/api/queued_jobs/failed-job/retry");
  expect(new Headers(call?.[1]?.headers).get("X-CSRF-Token")).toBe("token");
  status = "queued";
  await act(async () => resolveRetry(response({ status: "accepted" }, 202)));
  expect(await screen.findByText("queued")).toBeInTheDocument();
  await waitFor(() =>
    expect(screen.queryByRole("button", { name: /Retry Alerts/ })).not.toBeInTheDocument(),
  );
});

it("shows a failed retry request and lets the user try again", async () => {
  vi.spyOn(globalThis, "fetch").mockImplementation(async (url, options) => {
    if (url === "/api/session")
      return response({ brand: { id: 1, name: "Brand" }, csrf_token: "token" });
    if (options?.method === "POST") return response({ error: "Retry unavailable" }, 409);
    return response({
      jobs: [
        { id: "failed-job", job_class: "Alerts::ReconcileJob", status: "failed", attempts: 1 },
      ],
      pagination: { page: 1, pages: 1, total: 1 },
    });
  });
  mount();
  await userEvent.click(await screen.findByRole("button", { name: /Retry Alerts/ }));
  expect(await screen.findByRole("alert")).toHaveTextContent("Retry unavailable");
  await waitFor(() => expect(screen.getByRole("button", { name: /Retry Alerts/ })).toBeEnabled());
});
