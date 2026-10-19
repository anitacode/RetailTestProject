import { act, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { QueryClientProvider } from "@tanstack/react-query";
import { MemoryRouter } from "react-router-dom";
import { expect, it, vi } from "vitest";
import App from "@/App";
import { createQueryClient } from "@/queryClient";
import type { Contact, ContactInput } from "@/types";

const session = { brand: { id: 1, name: "Demo brand" }, csrf_token: "token" };
const response = (data: unknown, status = 200) =>
  Promise.resolve(new Response(JSON.stringify(data), { status }));
function mount(path = "/settings") {
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

it("adds and edits contact channels and preferences from notification settings", async () => {
  let contacts: Contact[] = [];
  const fetch = vi.spyOn(globalThis, "fetch").mockImplementation((url, options) => {
    if (url === "/api/session") return response(session);
    if (options?.method === "POST" || options?.method === "PATCH") {
      const { contact } = JSON.parse(String(options.body)) as { contact: ContactInput };
      contacts = [{ id: 1, ...contact }];
      return response({ contact: contacts[0] }, options.method === "POST" ? 201 : 200);
    }
    if (url === "/api/contacts/1") return response({ contact: contacts[0] });
    return response({
      contacts,
      pagination: { page: 1, pages: 1, per_page: 20, total: contacts.length },
    });
  });
  mount();
  await screen.findByText("No contacts yet. Add a contact to receive alerts.");
  await userEvent.click(screen.getByRole("button", { name: "Add contact" }));
  const createDialog = screen.getByRole("dialog", { name: "Add contact" });
  expect(
    within(createDialog).getByRole("group", { name: "Alert preferences" }),
  ).toBeInTheDocument();
  expect(within(createDialog).getByLabelText("Out-of-stock alerts")).not.toBeChecked();
  expect(within(createDialog).getByLabelText("Price-change alerts")).not.toBeChecked();
  const save = within(createDialog.querySelector("footer")!).getByRole("button", {
    name: "Save contact",
  });
  expect(save).toBeDisabled();
  await userEvent.type(screen.getByLabelText("Name"), "Alice");
  expect(save).toBeDisabled();
  await userEvent.type(screen.getByLabelText("Email"), "alice@example.com");
  await userEvent.type(screen.getByLabelText("Phone"), "+12025550123");
  await userEvent.click(screen.getByLabelText("Out-of-stock alerts"));
  await userEvent.click(save);
  expect(await screen.findByText("Contact saved.")).toBeInTheDocument();
  expect(contacts[0].setup).toEqual({ alert_no_inventory: true, alert_price_change: false });
  const create = fetch.mock.calls.find(([, options]) => options?.method === "POST");
  expect(new Headers(create?.[1]?.headers).get("X-CSRF-Token")).toBe("token");
  const edit = await screen.findByRole("button", { name: "Edit Alice" });
  const table = screen.getByRole("table");
  expect(within(table).getByRole("columnheader", { name: "Email" })).toBeInTheDocument();
  const row = edit.closest("tr")!;
  expect(within(row).getByRole("cell", { name: "alice@example.com" })).toBeInTheDocument();
  expect(within(row).getByRole("cell", { name: "+12025550123" })).toBeInTheDocument();
  expect(within(table).queryByRole("button", { name: "Next →" })).not.toBeInTheDocument();
  expect(screen.getByText("Page 1 of 1")).toBeInTheDocument();
  await userEvent.click(edit);
  expect(await screen.findByLabelText("Out-of-stock alerts")).toBeChecked();
  await userEvent.click(screen.getByLabelText("Out-of-stock alerts"));
  await userEvent.click(screen.getByLabelText("Price-change alerts"));
  await userEvent.clear(screen.getByLabelText("Phone"));
  await userEvent.click(screen.getByRole("button", { name: "Save contact" }));
  await screen.findByText("Contact saved.");
  expect(contacts[0].phone).toBeNull();
  expect(contacts[0].setup).toEqual({ alert_no_inventory: false, alert_price_change: true });
  expect(await screen.findByText("Price changes")).toBeInTheDocument();
});

it("keeps entered values when the server rejects a contact and allows cancel", async () => {
  vi.spyOn(globalThis, "fetch").mockImplementation((url, options) => {
    if (url === "/api/session") return response(session);
    if (options?.method === "POST") return response({ error: "Email is invalid" }, 422);
    return response({ contacts: [], pagination: { page: 1, pages: 0, per_page: 20, total: 0 } });
  });
  mount();
  await userEvent.click(await screen.findByRole("button", { name: "Add contact" }));
  await userEvent.type(screen.getByLabelText("Name"), "Alice");
  await userEvent.type(screen.getByLabelText("Email"), "alice@example.com");
  await userEvent.click(screen.getByRole("button", { name: "Save contact" }));
  expect(await screen.findByRole("alert")).toHaveTextContent("Email is invalid");
  expect(screen.getByLabelText("Name")).toHaveValue("Alice");
  await userEvent.click(screen.getByRole("button", { name: "Cancel" }));
  expect(screen.queryByLabelText("Name")).not.toBeInTheDocument();
});

it("offers a retry for failed contact loading and paginates contacts", async () => {
  let failed = true;
  vi.spyOn(globalThis, "fetch").mockImplementation((url) => {
    if (url === "/api/session") return response(session);
    if (failed) return response({ error: "Contacts unavailable" }, 503);
    const page = String(url).includes("page=2") ? 2 : 1;
    return response({
      contacts: [
        {
          id: page,
          name: `Person ${page}`,
          email: "person@example.com",
          phone: null,
          setup: { alert_no_inventory: false, alert_price_change: false },
        },
      ],
      pagination: { page, pages: 2, per_page: 20, total: 21 },
    });
  });
  mount();
  expect(await screen.findByRole("alert")).toHaveTextContent("Contacts unavailable");
  failed = false;
  await userEvent.click(screen.getByRole("button", { name: "Try again" }));
  await screen.findByText("Person 1");
  await userEvent.click(screen.getByRole("button", { name: "Next →" }));
  expect(await screen.findByText("Person 2")).toBeInTheDocument();
  expect(screen.getByRole("button", { name: "Next →" })).toBeDisabled();
});

it("opens notification settings from the workspace navigation", async () => {
  vi.spyOn(globalThis, "fetch").mockImplementation((url) => {
    if (url === "/api/session") return response(session);
    if (String(url).startsWith("/api/contacts"))
      return response({ contacts: [], pagination: { page: 1, pages: 0, per_page: 20, total: 0 } });
    return response({ alerts: [], unseen_count: 0, pagination: { total: 0, page: 1, pages: 0 } });
  });
  mount("/");
  expect(await screen.findByRole("link", { name: "Alerts" })).toHaveAttribute(
    "aria-current",
    "page",
  );
  await userEvent.click(await screen.findByRole("link", { name: "Notification settings" }));
  await waitFor(() =>
    expect(screen.getByRole("heading", { name: "Notification settings" })).toBeInTheDocument(),
  );
});

it("opens a contact dialog from a direct URL and returns to settings on Escape", async () => {
  const contact = {
    id: 7,
    name: "Direct contact",
    email: "direct@example.com",
    phone: null,
    setup: { alert_no_inventory: true, alert_price_change: false },
  };
  vi.spyOn(globalThis, "fetch").mockImplementation((url) => {
    if (url === "/api/session") return response(session);
    if (url === "/api/contacts/7") return response({ contact });
    return response({
      contacts: [contact],
      pagination: { page: 1, pages: 1, per_page: 20, total: 1 },
    });
  });
  mount("/settings/7");
  await screen.findByRole("dialog", { name: "Edit contact" });
  expect(screen.getByRole("link", { name: "Notification settings" })).toHaveAttribute(
    "aria-current",
    "page",
  );
  expect(screen.getByRole("link", { name: "Alerts" })).not.toHaveAttribute("aria-current");
  expect(await screen.findByLabelText("Name")).toHaveValue("Direct contact");
  fireEvent(
    screen.getByRole("dialog", { name: "Edit contact" }),
    new Event("cancel", { bubbles: false, cancelable: true }),
  );
  await waitFor(() => expect(screen.queryByRole("dialog")).not.toBeInTheDocument());
  expect(screen.getByRole("button", { name: "Edit Direct contact" })).toBeInTheDocument();
});

it("shows an unavailable contact in the dialog without exposing an edit form", async () => {
  vi.spyOn(globalThis, "fetch").mockImplementation((url) => {
    if (url === "/api/session") return response(session);
    if (url === "/api/contacts/999") return response({ error: "Record not found." }, 404);
    return response({ contacts: [], pagination: { page: 1, pages: 0, per_page: 20, total: 0 } });
  });
  mount("/settings/999");
  expect(await screen.findByRole("alert")).toHaveTextContent("Record not found.");
  expect(screen.queryByLabelText("Name")).not.toBeInTheDocument();
  await userEvent.click(screen.getByRole("button", { name: "Close dialog" }));
  expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
});

it("opens queue status from the sidebar and highlights the selected view", async () => {
  vi.spyOn(globalThis, "fetch").mockImplementation((url) => {
    if (url === "/api/session") return response(session);
    if (String(url).startsWith("/api/queued_jobs"))
      return response({
        jobs: [
          {
            id: "job-1",
            job_class: "Notifications::DeliverJob",
            queue: "notifications",
            status: "completed",
            attempts: 1,
            scheduled_at: null,
            finished_at: "2026-10-19T12:00:00Z",
          },
        ],
        pagination: { page: 1, pages: 1, per_page: 20, total: 1 },
      });
    return response({ contacts: [], pagination: { page: 1, pages: 0, per_page: 20, total: 0 } });
  });
  mount();
  const queueLink = await within(
    await screen.findByRole("navigation", { name: "Workspace" }),
  ).findByRole("link", { name: "Queue status ↗" });
  expect(screen.getAllByRole("link", { name: "Queue status ↗" })).toHaveLength(1);
  await userEvent.click(queueLink);
  expect(queueLink).toHaveAttribute("aria-current", "page");
  expect(screen.getByRole("link", { name: "Notification settings" })).not.toHaveAttribute(
    "aria-current",
  );
  expect(await screen.findByText("Notifications::DeliverJob")).toBeInTheDocument();
  expect(screen.getByText("completed")).toBeInTheDocument();
});

it("submits from the dialog footer with validation and pending controls, and cancels after an error", async () => {
  const contact: Contact = {
    id: 7,
    name: "Alice",
    email: "alice@example.com",
    phone: null,
    setup: { alert_no_inventory: true, alert_price_change: false },
  };
  let finishSave!: (value: Response) => void;
  const fetch = vi.spyOn(globalThis, "fetch").mockImplementation((url, options) => {
    if (url === "/api/session") return response(session);
    if (options?.method === "PATCH")
      return new Promise<Response>((resolve) => {
        finishSave = resolve;
      });
    if (url === "/api/contacts/7") return response({ contact });
    return response({
      contacts: [contact],
      pagination: { page: 1, pages: 1, total: 1, per_page: 20 },
    });
  });
  mount("/settings/7");
  await screen.findByLabelText("Name");
  const dialog = screen.getByRole("dialog", { name: "Edit contact" });
  const footer = dialog.querySelector("footer")!;
  const save = within(footer).getByRole("button", { name: "Save contact" });
  const cancel = within(footer).getByRole("button", { name: "Cancel" });
  expect(save.closest("form")).toBeNull();
  expect((save as HTMLButtonElement).form).toBe(screen.getByLabelText("Name").closest("form"));
  await userEvent.clear(screen.getByLabelText("Email"));
  await userEvent.type(screen.getByLabelText("Email"), "invalid");
  await userEvent.click(save);
  expect(fetch.mock.calls.some(([, options]) => options?.method === "PATCH")).toBe(false);
  await userEvent.clear(screen.getByLabelText("Email"));
  await userEvent.type(screen.getByLabelText("Email"), "updated@example.com");
  await userEvent.click(save);
  expect(save).toBeDisabled();
  expect(cancel).toBeDisabled();
  expect(screen.getByLabelText("Name")).toBeDisabled();
  await act(async () => finishSave(await response({ error: "Save failed" }, 422)));
  expect(await screen.findByRole("alert")).toHaveTextContent("Save failed");
  expect(screen.getByLabelText("Email")).toHaveValue("updated@example.com");
  await userEvent.click(cancel);
  await waitFor(() => expect(screen.queryByRole("dialog")).not.toBeInTheDocument());
});

it("debounces contact search for 500 ms, resets pagination, and clears the filter", async () => {
  const fetch = vi.spyOn(globalThis, "fetch").mockImplementation((url) => {
    if (url === "/api/session") return response(session);
    const page = new URL(String(url), "http://localhost").searchParams.get("page") || "1";
    return response({
      contacts: [
        {
          id: Number(page),
          name: `Person ${page}`,
          email: "person@example.com",
          phone: null,
          setup: { alert_no_inventory: false, alert_price_change: false },
        },
      ],
      pagination: { page: Number(page), pages: 2, total: 21, per_page: 20 },
    });
  });
  mount();
  await screen.findByText("Person 1");
  await userEvent.click(screen.getByRole("button", { name: "Next →" }));
  await screen.findByText("Person 2");
  const initialRequests = fetch.mock.calls.length;
  vi.useFakeTimers();
  try {
    fireEvent.change(screen.getByLabelText("Search contacts"), { target: { value: "Alice" } });
    await act(async () => {
      await vi.advanceTimersByTimeAsync(499);
    });
    expect(fetch).toHaveBeenCalledTimes(initialRequests);
    fireEvent.change(screen.getByLabelText("Search contacts"), {
      target: { value: "alice@example.com" },
    });
    await act(async () => {
      await vi.advanceTimersByTimeAsync(499);
    });
    expect(fetch).toHaveBeenCalledTimes(initialRequests);
    await act(async () => {
      await vi.advanceTimersByTimeAsync(1);
    });
    expect(fetch.mock.calls.at(-1)?.[0]).toBe("/api/contacts?page=1&q=alice%40example.com");
    expect(fetch.mock.calls.some(([url]) => String(url).includes("q=Alice"))).toBe(false);
    fireEvent.change(screen.getByLabelText("Search contacts"), { target: { value: "" } });
    await act(async () => {
      await vi.advanceTimersByTimeAsync(500);
    });
    await act(async () => {
      await vi.advanceTimersByTimeAsync(1);
    });
    expect(screen.getByLabelText("Search contacts")).toHaveValue("");
  } finally {
    vi.useRealTimers();
  }
  expect(await screen.findByText("Person 1")).toBeInTheDocument();
});

it("shows a search-specific empty state", async () => {
  vi.spyOn(globalThis, "fetch").mockImplementation((url) => {
    if (url === "/api/session") return response(session);
    return response({ contacts: [], pagination: { page: 1, pages: 0, total: 0, per_page: 20 } });
  });
  mount();
  await userEvent.type(await screen.findByLabelText("Search contacts"), "Missing");
  expect(await screen.findByText("No contacts match your search.")).toBeInTheDocument();
});

it("masks typed and pasted phone numbers and requires a complete number before saving", async () => {
  const fetch = vi.spyOn(globalThis, "fetch").mockImplementation((url, options) => {
    if (url === "/api/session") return response(session);
    if (options?.method === "POST") return response({ error: "Test save error" }, 422);
    return response({ contacts: [], pagination: { page: 1, pages: 0, total: 0, per_page: 20 } });
  });
  const user = userEvent.setup();
  mount();
  await user.click(await screen.findByRole("button", { name: "Add contact" }));
  await user.type(screen.getByLabelText("Name"), "Phone contact");
  const phone = screen.getByLabelText("Phone");
  await user.type(phone, "1202abc");
  expect(phone).toHaveValue("+1202");
  await user.click(screen.getByRole("button", { name: "Save contact" }));
  expect(fetch.mock.calls.some(([, options]) => options?.method === "POST")).toBe(false);
  await user.clear(phone);
  expect(phone).toHaveValue("");
  await user.paste("+1 (202) 555-0123");
  expect(phone).toHaveValue("+12025550123");
  (phone as HTMLInputElement).setSelectionRange(4, 4);
  await user.keyboard("9");
  expect(phone).toHaveValue("+120925550123");
  expect((phone as HTMLInputElement).selectionStart).toBe(5);
  await user.keyboard("{Backspace}");
  expect(phone).toHaveValue("+12025550123");
  await user.click(screen.getByRole("button", { name: "Save contact" }));
  expect(await screen.findByRole("alert")).toHaveTextContent("Test save error");
  const post = fetch.mock.calls.find(([, options]) => options?.method === "POST");
  expect(JSON.parse(String(post?.[1]?.body)).contact.phone).toBe("+12025550123");
  await user.clear(phone);
  await user.paste("+1234567890123456789");
  expect(phone).toHaveValue("+123456789012345");
  await user.clear(phone);
  await user.type(phone, "0");
  expect(phone).toHaveValue("");
  await user.type(phone, "34");
  expect(phone).toHaveValue("+34");
});
