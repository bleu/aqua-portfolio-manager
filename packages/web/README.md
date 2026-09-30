# Web

The Portfolio Manager frontend. React + TypeScript, built with Vite, styled with Tailwind CSS.
First page: the V1 entry/onboarding flow's `01 · Connect Safe` landing page (BLEUDEV-397).

## Structure

- `src/components/` — reusable UI pieces (`Badge`, `Button`, `AllocationBar`, `CurrentVsTargetCard`,
  `Header`), each with a colocated `*.stories.tsx` file.
- `src/pages/` — full pages assembled from those components (`ConnectSafePage`).
- `src/lib/` — small local utilities (`cn` for conditional class names).

## Running

```sh
pnpm dev          # Vite dev server, http://localhost:5173
pnpm storybook    # Storybook, http://localhost:6006
pnpm build        # typecheck + production build
```

## Design

Dark theme only for now -- tokens live in `src/index.css` under Tailwind v4's `@theme` block
(`--color-bg`, `--color-accent`, etc.), not a separate config file. No light-mode variant exists
yet; the design this page implements didn't have one.

## Storybook

Every component in `src/components/` and page in `src/pages/` has a story. `pnpm exec vitest run`
runs the Storybook Vitest addon's tests (each story renders in a real Chromium instance via
Playwright, with an accessibility check) -- this is the fastest way to catch a component that
doesn't render at all, independent of the full app.

## Known gaps (tracked in BLEUDEV-397, not solved here)

- No wallet-connection library wired up yet -- "Connect Safe" takes an `onConnectSafe` callback
  prop but the page itself doesn't call any wallet SDK.
- The "Current vs. target" card renders static, hardcoded sample data. Where real allocation data
  comes from (the indexer's GraphQL endpoint, a new API, or something else) isn't decided.
