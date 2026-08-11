# Third-Party Notices

This project depends on and is a Modification/Extension of third-party licensed work. See
[`docs/LICENSING-RISK.md`](docs/LICENSING-RISK.md) for what that actually means for this
project's own license and business posture — read that before assuming "MIT" applies here.

| Dependency | Path | License | Role |
|---|---|---|---|
| [1inch/aqua](https://github.com/1inch/aqua) | `lib/aqua` | `LicenseRef-Degensoft-Aqua-Source-1.1` (custom, copyleft + commercial triggers) | **Our strategy contract inherits `AquaApp` from this.** This is why this repo's own `LICENSE` is Aqua-Source-1.1, not MIT — see below. |
| [1inch/swap-vm](https://github.com/1inch/swap-vm) | `lib/swap-vm` | `LicenseRef-Degensoft-SwapVM-1.1` (custom, same license family as Aqua) | Only triggers if the chosen design (Milestone 1) extends a swapVM instruction directly, instead of / in addition to the AquaApp path. |
| [foundry-rs/forge-std](https://github.com/foundry-rs/forge-std) | `lib/forge-std` | MIT | Test/scripting utilities only — not deployed, no licensing consequence. |
| [balancer/balancer-v3-monorepo](https://github.com/balancer/balancer-v3-monorepo) | `lib/balancer-v3-monorepo` | GPL-3.0 | **Reference only. Never import, copy, or link against this from `src/`.** It's here so whoever implements the Pricing Engine can study Balancer's weighted-pool math (the *formula* is public, from Balancer's 2019 whitepaper, and — as far as we know — unpatented) without touching their GPL-licensed *code*. The grant's own scope rules explicitly ban "AMM formulas/mechanisms licensed by third parties" — copying this code would violate that, independent of any GPL question. Reimplement the formula from scratch. |

## Why this repo's `LICENSE` is Aqua-Source-1.1, not MIT

Aqua-Source-1.1 §3 requires that if you "Modify" the Licensed Work — defined broadly enough
to include inheritance/extension compiled into the same contract — you publish your own
resulting code under the *same* license. Our strategy contract inherits `AquaApp`
(`lib/aqua/src/AquaApp.sol`), so this almost certainly counts. Using plain MIT here would be
factually wrong about what license actually governs this code. See
[`docs/LICENSING-RISK.md`](docs/LICENSING-RISK.md) for the full reasoning and the open
business risk this creates (a revocable commercial-use waiver, not a permanent exemption).
