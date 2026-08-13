import vinext from "vinext";
import { nitro } from "nitro/vite";
import tailwindcss from "@tailwindcss/vite";
import { defineConfig } from "vite";

// Netlify requires a server adapter that emits Netlify Functions and assets.
// Keep this separate from vite.config.ts, which remains the Cloudflare/Sites
// build used by the private evidence-ledger deployment.
export default defineConfig({
  plugins: [vinext(), tailwindcss(), nitro({ preset: "netlify" })],
});
