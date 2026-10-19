import { fileURLToPath, URL } from "node:url";
import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

export default defineConfig(({ command }) => ({
  root: "frontend",
  base: command === "build" ? "/alerts-ui/" : "/",
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: [
      {
        find: "@/ui",
        replacement: fileURLToPath(new URL("./frontend/components", import.meta.url)),
      },
      {
        find: "@/component",
        replacement: fileURLToPath(new URL("./frontend/component", import.meta.url)),
      },
      { find: "@", replacement: fileURLToPath(new URL("./frontend/src", import.meta.url)) },
    ],
  },
  server: {
    host: "127.0.0.1",
    port: 5173,
    strictPort: true,
    proxy: { "/api": { target: "http://127.0.0.1:3000" } },
  },
  build: { outDir: "../public/alerts-ui", emptyOutDir: true },
  test: { environment: "jsdom", setupFiles: "./src/test-setup.ts", css: false },
}));
