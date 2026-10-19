import { expect, it, vi } from "vitest";
import { ApiError, request } from "@/api";

it("preserves API status and error messages for authorization handling", async () => {
  vi.spyOn(globalThis, "fetch").mockResolvedValue(
    new Response(JSON.stringify({ error: "Sign in." }), { status: 401 }),
  );
  await expect(request("/alerts")).rejects.toMatchObject({
    name: "ApiError",
    status: 401,
    message: "Sign in.",
  });
});

it("handles non-JSON server failures with a readable error", async () => {
  vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response("Unavailable", { status: 503 }));
  await expect(request("/alerts")).rejects.toThrow("The server could not complete the request.");
});

it("accepts Headers objects and handles errors without a string message", async () => {
  const fetch = vi
    .spyOn(globalThis, "fetch")
    .mockResolvedValue(
      new Response(JSON.stringify({ error: { internal: "details" } }), { status: 422 }),
    );
  await expect(
    request("/session", { headers: new Headers({ "X-Test": "value" }) }),
  ).rejects.toBeInstanceOf(ApiError);
  const headers = new Headers(fetch.mock.calls[0]?.[1]?.headers);
  expect(headers.get("X-Test")).toBe("value");
  expect(headers.get("Accept")).toBe("application/json");
});
