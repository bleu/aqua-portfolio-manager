# Decoding

Decodes Aqua's `abi.encode(Order)` bytes (`orderDecoder.ts`) and a Portfolio Manager strategy's
program wire format (`programDecoder.ts`) -- the logic any app working with a shipped strategy's
*decoded* form needs, not just one of them. Extracted from `apps/arbitrageur`, the only current
consumer -- `apps/indexer` and a future web UI can depend on the same decode logic instead of
reimplementing it once either actually needs a strategy's decoded form (neither does today).

See `../../docs/MONOREPO-CONVENTIONS.md` for what makes this a "package" rather than an "app."

## Usage

```ts
import { decodeOrder, extractProgram, decodeProgram } from "@aqua-portfolio-manager/decoding";

const order = decodeOrder(encodedOrderBytes);
const program = extractProgram(order.traits, order.data);
const decoded = decodeProgram(program); // { groups, feeBps, maxDeviationBps, resolverKycToken }
```

## Scripts

- `pnpm test` -- `vitest run`. Both decoders are tested against real bytes generated from the
  actual Solidity encoders (`MakerTraitsLib.build`, `PortfolioManagerProgramBuilder.build` /
  `GatedPortfolioManagerProgramBuilder.build`), not hand-derived fixtures.
- `pnpm typecheck` -- `tsc --noEmit`.
- `pnpm build` -- compiles to `dist/`, which `package.json`'s `main`/`types` point at (so a
  consumer running compiled JS directly, `node dist/main.js`-style, resolves this package
  correctly). Runs automatically via `prepare` on `pnpm install`, so no manual step is needed in
  the common case -- only run it directly after changing this package's own source without a
  fresh install.
