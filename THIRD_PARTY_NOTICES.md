# Third-Party Notices

This project uses and extends code licensed by others.
See [licensing risk](docs/LICENSING-RISK.md) for the source requirements and commercial risks. The project does not use MIT for its own code.

| Dependency | Path | License | Role |
|---|---|---|---|
| [1inch/aqua](https://github.com/1inch/aqua) | `packages/contracts/lib/aqua` | `LicenseRef-Degensoft-Aqua-Source-1.1` (custom source-sharing requirements and commercial thresholds) | Provides Aqua interfaces and settlement contracts. Our router inherits SwapVM, rather than `AquaApp`. See [ADR-0001](docs/adr/0001-license-under-aqua-source-not-mit.md). |
| [1inch/swap-vm](https://github.com/1inch/swap-vm) | `packages/contracts/lib/swap-vm` | `LicenseRef-Degensoft-SwapVM-1.1` (same license family as Aqua) | Our router inherits SwapVM, so its source becomes part of our deployed contract. |
| [foundry-rs/forge-std](https://github.com/foundry-rs/forge-std) | `packages/contracts/lib/forge-std` | MIT | Test and script tools. Not included in deployed contracts. |
| [PaulRBerg/prb-math](https://github.com/PaulRBerg/prb-math) | `packages/contracts/lib/prb-math` | MIT | `FixedPointMath.sol` uses PRBMath for `powDown` and `powUp`, compiled into `PortfolioManagerPricing`. Preserve its license notice under §11.2's third-party requirements. MIT does not require our code to adopt its license. |
| [balancer/balancer-v3-monorepo](https://github.com/balancer/balancer-v3-monorepo) | `packages/contracts/lib/balancer-v3-monorepo` | GPL-3.0 | **Reference only. Never import, copy, or link against this from `src/`.** Independently implement the public formula from Balancer's 2019 whitepaper. |

The original design recorded no known patent on that formula.
The grant also bans third-party-licensed AMM formulas or mechanisms. Copying Balancer's code would violate that restriction, independently of GPL requirements.

## Why this repo's `LICENSE` is Aqua-Source-1.1, not MIT

Aqua-Source-1.1 §3 requires modifications to be published under the same license.
The repository treats inherited SwapVM code as a modification under [ADR-0001](docs/adr/0001-license-under-aqua-source-not-mit.md).
See [licensing risk](docs/LICENSING-RISK.md) for the assessment, which still needs legal review, and the commercial-use waiver that Degensoft can revoke.
