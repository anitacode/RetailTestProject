import React from "react";
import { QueryClientProvider } from "@tanstack/react-query";
import { createQueryClient } from "@/queryClient";
import { createRoot } from "react-dom/client";
import AppRouter, { prepareAppLocation } from "@/AppRouter";
import "@/styles.css";

const root = document.getElementById("root");
if (!root) throw new Error("Missing React root element.");

prepareAppLocation();
const queryClient = createQueryClient();

createRoot(root).render(
  <React.StrictMode>
    <QueryClientProvider client={queryClient}>
      <AppRouter />
    </QueryClientProvider>
  </React.StrictMode>,
);
