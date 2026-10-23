import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";

/** src/lib/contracts.ts (and anything that imports it, like a dock/ship transaction builder)
 *  reads process.env.NEXT_PUBLIC_* the way Next.js itself does. Vite only loads .env* into
 *  import.meta.env by default and this package has no direct dependency on `vite` itself to pull
 *  in its loadEnv helper, so this parses .env.local directly instead -- good enough for the
 *  `KEY=value` lines this file actually has, not a general-purpose dotenv parser. */
function loadDotEnvLocal(): Record<string, string> {
  const vars: Record<string, string> = {};
  let content: string;
  try {
    content = readFileSync(fileURLToPath(new URL("./.env.local", import.meta.url)), "utf-8");
  } catch {
    return vars;
  }
  for (const line of content.split("\n")) {
    const match = /^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/.exec(line.trim());
    if (match) vars[match[1]!] = match[2]!.replace(/^["']|["']$/g, "");
  }
  return vars;
}

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
    env: loadDotEnvLocal(),
  },
});
