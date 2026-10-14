# Web

The Portfolio Manager frontend. Next.js (App Router) + React + TypeScript, styled with Tailwind
CSS. First page: the entry/onboarding flow's `01 · Connect Safe` landing page (BLEUDEV-397).

## Structure

- `app/` — routes. `/` is the Connect Safe entry page; later steps are added as the flow grows
  (BLEUDEV-409 onward).
- `src/components/` — reusable UI pieces (`Badge`, `Button`, `AllocationBar`, `CurrentVsTargetCard`,
  `Header`), each with a colocated `*.stories.tsx` file.
- `src/components/pages/` — full pages assembled from those components (`ConnectSafePage`).
- `src/lib/` — small local utilities (`cn` for conditional class names, `wagmi` for the wallet
  connection config).

## Running

```sh
pnpm dev          # Next.js dev server, http://localhost:3000
pnpm storybook    # Storybook, http://localhost:6006
pnpm build        # production build
pnpm typecheck    # tsc --noEmit
```

## Wallet connection

Connection is Safe-only (ADR-0011: a Safe smart account is required, not a plain EOA) -- see
`src/lib/wagmi.ts`'s own doc comment. `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID` (see `.env.example`)
is optional: without it, the "Connect Safe" button only works when this page is embedded inside
Safe{Wallet} as a Safe App.

## Design

Dark theme only for now -- tokens live in `tailwind.config.ts` (`surface`, `border`, `accent`,
`positive`). No light-mode variant exists yet; the design this page implements didn't have one.

## Storybook

Every component in `src/components/` and page in `src/components/pages/` has a story.

## Known gaps

- The "Current vs. target" card renders static, hardcoded sample data. Where real allocation data
  comes from (the indexer's GraphQL endpoint, a new API, or something else) isn't decided.
