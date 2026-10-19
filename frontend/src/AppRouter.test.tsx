import React from "react";
import { afterEach, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import AppRouter, { prepareAppLocation } from "@/AppRouter";

vi.mock("@/App", () => ({ default: () => <h1>Alert workspace</h1> }));
afterEach(() => window.history.replaceState(null, "", "/"));

it("opens the workspace from the root URL and preserves query and hash", () => {
  window.history.replaceState(null, "", "/?page=2#top");
  prepareAppLocation();
  render(<AppRouter />);
  expect(screen.getByRole("heading", { name: "Alert workspace" })).toBeInTheDocument();
  expect(window.location.pathname).toBe("/alerts");
  expect(window.location.search).toBe("?page=2");
  expect(window.location.hash).toBe("#top");
});

it("preserves direct alert detail URLs", () => {
  window.history.replaceState(null, "", "/alerts/42");
  prepareAppLocation();
  render(<AppRouter />);
  expect(screen.getByRole("heading", { name: "Alert workspace" })).toBeInTheDocument();
  expect(window.location.pathname).toBe("/alerts/42");
});
