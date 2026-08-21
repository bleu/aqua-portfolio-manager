# Aqua Portfolio Manager

A rebalancing AMM strategy on [1inch Aqua](https://github.com/1inch/aqua) that keeps an LP's
*net* cross-strategy token exposure on a declared target, automatically, as a byproduct of
ordinary trading — not a scheduled manual rebalance.

**Status: pre-Milestone 1.** This repo is the scaffold; the mechanism, its on-chain form
(AquaApp vs. a swapVM instruction vs. a hybrid), and the security proof are Milestone 1
deliverables under a proposed 1inch Aqua Incubator grant. See [`docs/adr/`](docs/adr/) for the
decision record this repo implements.

## The problem

Aqua lets an LP allocate virtual balances across many strategies off one capital base,
without fragmenting it. That's real capital efficiency, but nothing manages what that capital
base adds up to *across* strategies — an LP running five strategies over six tokens has one
real portfolio, not five separate positions, and nobody's watching the combined total.

## The approach (current design, subject to Milestone 1)

- The LP segregates managed capital into a **dedicated maker wallet** (EOA or Safe) holding
  only the declared universe of tokens. Every strategy shipped from that wallet settles into
  it — so the wallet's real, settled balance *is* the true net exposure across all of them.
  **Zero changes to the Aqua protocol.**
- Tokens are grouped by asset class (e.g. "majors", "stablecoins"), not tracked individually —
  the LP declares a target weight per group.
- Pricing uses a constant-mean weighted curve (Balancer-style weighted-pool math,
  *reimplemented independently* — see [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) for
  why we don't import Balancer's own GPL-licensed code) anchored to Chainlink-style push
  oracles: trades that move the portfolio toward target get a better price, trades that move
  it away get a worse one.
- The exposure reading is smoothed (EMA/TWAP + tolerance band + rate caps) specifically so a
  single-block token donation into the wallet can't be used to game the price — see
  [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the invariant this relies on.
- Success is measured by tracking error (how close the realized portfolio stays to target)
  and cost of rebalancing (what it costs the LP to stay there) — this is a portfolio
  *maintenance* tool, not a volume/fee product.

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for diagrams and the component breakdown,
and [`docs/adr/`](docs/adr/) for the decision record behind each choice above.

## ⚠️ Licensing — read this before assuming "MIT"

Aqua and swapVM ship under a custom Degensoft license, not MIT — and our strategy contract
inheriting `AquaApp` likely triggers its copyleft clause. There's also a real, revocable
business risk around this project's target scale. Full details, not yet resolved with
counsel: [`docs/LICENSING-RISK.md`](docs/LICENSING-RISK.md).

## Repo layout

```
src/                    Strategy contract(s) — empty until Milestone 1 picks the on-chain form
test/                   Forge tests
script/                 Deployment scripts
docs/ARCHITECTURE.md    System diagrams + component breakdown
docs/LICENSING-RISK.md  The Aqua-Source-1.1 finding above, in full
docs/adr/               Architecture decision records
lib/aqua/               1inch Aqua core (submodule) — AquaApp base contract, IAqua interface
lib/swap-vm/            1inch swapVM (submodule) — only relevant if M1 picks a swapVM instruction
lib/balancer-v3-monorepo/  Reference-only (GPL-3.0) — study the weighted-math formula, never import
lib/forge-std/          Foundry test utilities
```

## Development

```shell
forge build
forge test
forge fmt
```

## Links

- [1inch Aqua](https://github.com/1inch/aqua) · [1inch swapVM](https://github.com/1inch/swap-vm)
- [Aqua white paper](https://1inch.com/assets/1inch-aqua-white-paper.pdf)
