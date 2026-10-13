import { fileURLToPath } from "node:url";
import { storybookTest } from "@storybook/addon-vitest/vitest-plugin";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vitest/config";

/** CI's "Run component/story tests" step (test.yml) runs every *.stories.tsx file as a real,
 *  headless-browser smoke test via this addon -- it renders each story and fails on a thrown
 *  render error, not just a type error a plain build would already catch. */
export default defineConfig({
  // react() isn't implied by storybookTest() -- without it, Vite transforms each story's .tsx
  // with the classic JSX runtime instead of the automatic one these components are written for
  // (no component here imports React itself), failing every single story with "React is not
  // defined" the instant it tries to render.
  plugins: [react(), storybookTest({ configDir: ".storybook" })],
  // @storybook/nextjs's mocked Next.js router reads `process.env.*` directly -- real in the
  // Storybook dev server and in `next build`'s Node/webpack context, but this addon's browser-mode
  // tests run inside an actual headless browser tab, where `process` doesn't exist at all.
  define: {
    "process.env": {},
  },
  resolve: {
    // Mirrors tsconfig.json's "@/*" -> "./src/*" path alias -- Vite's resolver doesn't read
    // tsconfig paths on its own, so every "@/..." import in a story's component tree would
    // otherwise fail to resolve under this addon's own Vite instance, even though the exact same
    // import resolves fine for `next build` and the Storybook dev server.
    alias: {
      "@": fileURLToPath(new URL("./src", import.meta.url)),
    },
  },
  test: {
    name: "storybook",
    browser: {
      enabled: true,
      headless: true,
      provider: "playwright",
      instances: [{ browser: "chromium" }],
    },
    setupFiles: [".storybook/vitest.setup.ts"],
  },
});
