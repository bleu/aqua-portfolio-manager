import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";

/** Plain Node-environment unit tests for src/lib/**, separate from vitest.config.ts's
 *  browser-mode Storybook story tests -- those two `test.browser`/plain-Node modes can't share
 *  one config. Run via `pnpm test:unit`. */
export default defineConfig({
  resolve: {
    alias: {
      "@": fileURLToPath(new URL("./src", import.meta.url)),
    },
  },
  test: {
    name: "unit",
    environment: "node",
    include: ["src/**/*.test.ts"],
  },
});
