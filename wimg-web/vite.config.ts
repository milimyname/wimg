import { sveltekit } from "@sveltejs/kit/vite";
import tailwindcss from "@tailwindcss/vite";
import { defineConfig } from "vite";
import { readFileSync } from "node:fs";

const pkg = JSON.parse(readFileSync("package.json", "utf-8"));

export default defineConfig({
  plugins: [tailwindcss(), sveltekit()],
  define: {
    __APP_VERSION__: JSON.stringify(pkg.version),
  },
  server: {
    headers: {
      // Required for SharedArrayBuffer (OPFS) support
      "Cross-Origin-Opener-Policy": "same-origin",
      "Cross-Origin-Embedder-Policy": "credentialless",
    },
  },
});
