import { sveltekit } from "@sveltejs/kit/vite";
import tailwindcss from "@tailwindcss/vite";
import { defineConfig } from "vite-plus";
import { readFileSync } from "node:fs";

const pkg = JSON.parse(readFileSync("package.json", "utf-8"));

export default defineConfig({
  fmt: {
    ignorePatterns: ["build/", ".svelte-kit/", "node_modules/", "static/"],
  },
  lint: {
    categories: {
      correctness: "error",
      suspicious: "warn",
      perf: "warn",
    },
    rules: {
      "unicorn/require-module-specifiers": "off",
      "no-map-spread": "off",
    },
    env: {
      builtin: true,
      browser: true,
    },
    ignorePatterns: ["build/", ".svelte-kit/", "node_modules/", "static/"],
  },
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
