# Aqua Portfolio Manager

A rebalancing AMM strategy on [1inch Aqua](https://github.com/1inch/aqua) that keeps an LP's *net* cross-strategy token exposure on a declared target, automatically, as a byproduct of ordinary trading — not a scheduled manual rebalance.

**Status: pre-Milestone 1.** This repo is the scaffold; the mechanism, its on-chain form (AquaApp vs. a swapVM instruction vs. a hybrid), and the security proof are Milestone 1 deliverables under a proposed 1inch Aqua Incubator grant. See [`docs/adr/`](docs/adr/) for the decision record this repo implements.

## The problem

Aqua lets an LP allocate virtual balances across many strategies off one capital base, without fragmenting it. That's real capital efficiency, but nothing manages what that capital base adds up to *across* strategies — an LP running five strategies over six tokens has one real portfolio, not five separate positions, and nobody's watching the combined total.

## The approach (current design, subject to Milestone 1)

- The LP segregates managed capital into a **dedicated maker wallet** (EOA or Safe) holding only the declared universe of tokens. Every strategy shipped from that wallet settles into it — so the wallet's real, settled balance *is* the true net exposure across all of them. **Zero changes to the Aqua protocol.**
- Tokens are grouped by asset class (e.g. "majors", "stablecoins"), not tracked individually — the LP declares a target weight per group.
- Pricing uses a constant-mean weighted curve (Balancer-style weighted-pool math, *reimplemented independently* — see [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) for why we don't import Balancer's own GPL-licensed code) anchored to Chainlink-style push oracles: trades that move the portfolio toward target get a better price, trades that move it away get a worse one.
- The exposure reading is smoothed (EMA/TWAP + tolerance band + rate caps) specifically so a single-block token donation into the wallet can't be used to game the price — see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the invariant this relies on.
- Success is measured by tracking error (how close the realized portfolio stays to target) and cost of rebalancing (what it costs the LP to stay there) — this is a portfolio *maintenance* tool, not a volume/fee product.

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for diagrams and the component breakdown, and [`docs/adr/`](docs/adr/) for the decision record behind each choice above.

## ⚠️ Licensing — read this before assuming "MIT"

Aqua and swapVM ship under a custom Degensoft license, not MIT — and our strategy contract inheriting `AquaApp` likely triggers its copyleft clause. There's also a real, revocable business risk around this project's target scale. Full details, not yet resolved with counsel: [`docs/LICENSING-RISK.md`](docs/LICENSING-RISK.md).

## Repo layout

A pnpm workspace monorepo — `packages/*` are the workspace members.

```
packages/contracts/         Foundry package — strategy/guard/router contracts and tests
packages/contracts/src/     Contract sources
packages/contracts/test/    Forge tests (test/e2e/ forks Base directly, see below)
packages/contracts/lib/     Vendored submodules: aqua, swap-vm, forge-std, safe-smart-account,
                             openzeppelin-contracts, solidity-utils, balancer-v3-monorepo
                             (balancer-v3-monorepo is reference-only, GPL-3.0 — never imported)
docs/ARCHITECTURE.md         System diagrams + component breakdown
docs/LICENSING-RISK.md       The Aqua-Source-1.1 finding above, in full
docs/adr/                    Architecture decision records
simulation/                  M1's economic simulation notebooks (Python, not a workspace member)
```

## Development

```shell
pnpm install

# Contracts
cd packages/contracts

# test/e2e/ forks Base directly (vm.createSelectFork) and deploys everything it needs inline —
# no separate deploy step. Optional: set BASE_RPC_URL to avoid the public endpoint's rate limits.
# Tests default to verified block 51609641. Set BASE_RPC_BLOCK=0 to test live state,
# or set it to another block number to override the snapshot.
cp .env.example .env

forge build
forge test
forge fmt
```

## Links

- [1inch Aqua](https://github.com/1inch/aqua) · [1inch swapVM](https://github.com/1inch/swap-vm)
- [Aqua white paper](https://1inch.com/assets/1inch-aqua-white-paper.pdf)
