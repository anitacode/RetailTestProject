import { render, screen, within, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { QueryClientProvider } from "@tanstack/react-query";
import { MemoryRouter } from "react-router-dom";
import { expect, it, vi } from "vitest";
import App from "@/App";
import { createQueryClient } from "@/queryClient";
import { sessionKey } from "@/queryKeys";

it("handles logout in the sidebar, disables pending requests and allows retry after an error", async () => {
  let finishLogout!: (response: Response) => void;
  const fetch = vi.spyOn(globalThis, "fetch").mockImplementation(async (_url, init) => {
    if (init?.method === "DELETE")
      return new Promise<Response>((resolve) => {
        finishLogout = resolve;
      });
    return new Response(
      JSON.stringify({
        alerts: [],
        unseen_count: 0,
        pagination: { page: 1, pages: 0, total: 0 },
      }),
    );
  });
  const client = createQueryClient();
  client.setQueryData(sessionKey, { brand: { id: 1, name: "Brand" }, csrf_token: "token" });
  render(
    <QueryClientProvider client={client}>
      <MemoryRouter>
        <App />
      </MemoryRouter>
    </QueryClientProvider>,
  );
  const sidebar = screen.getByRole("complementary");

  await userEvent.click(within(sidebar).getByRole("button", { name: "Sign out ↗" }));
  expect(within(sidebar).getByRole("button", { name: "Signing out…" })).toBeDisabled();
  expect(fetch).toHaveBeenCalledWith("/api/session", expect.objectContaining({ method: "DELETE" }));
  finishLogout(new Response(JSON.stringify({ error: "Sign out failed" }), { status: 503 }));
  expect(await within(sidebar).findByRole("alert")).toHaveTextContent("Sign out failed");
  await userEvent.click(within(sidebar).getByRole("button", { name: "Sign out ↗" }));
  finishLogout(new Response(JSON.stringify({ brand: null, csrf_token: "token" })));
  await waitFor(() => expect(screen.queryByRole("complementary")).not.toBeInTheDocument());
  expect(await screen.findByLabelText("Brand name")).toBeInTheDocument();
  client.clear();
});
