import React from "react";
import { BrowserRouter } from "react-router-dom";
import App from "@/App";

export function prepareAppLocation() {
  // The Vite entry URL should open the workspace under its canonical path.
  if (window.location.pathname === "/") {
    window.history.replaceState(
      window.history.state,
      "",
      `/alerts${window.location.search}${window.location.hash}`,
    );
  }
}

export default function AppRouter() {
  return (
    <BrowserRouter basename="/alerts">
      <App />
    </BrowserRouter>
  );
}
