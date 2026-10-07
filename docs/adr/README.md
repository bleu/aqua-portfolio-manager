# Architecture decisions

Each architecture decision record (ADR) explains a design choice.
Use [the template](0000-template.md) for new decisions and assign the next number.
Keep merged ADR numbers and files. Mark replaced decisions as superseded and link to their replacements.
Record the reason for a choice here. Put current behavior in the relevant reference document.
Follow the [documentation style](../STYLE.md).

| ADR | Decision | Status |
|---|---|---|
| [0001](0001-license-under-aqua-source-not-mit.md) | Use Aqua-Source-1.1 | Accepted |
| [0002](0002-dedicated-maker-wallet-as-portfolio-scope.md) | Use a dedicated maker wallet | Accepted |
| [0003](0003-oracle-valued-token-groups.md) | Value exposure by token group | Accepted |
| [0004](0004-constant-mean-weighted-curve-pricing.md) | Use a constant-mean weighted curve | Accepted |
| [0005](0005-chainlink-push-oracles.md) | Use Chainlink-style push feeds | Accepted |
| [0006](0006-exposure-smoothing.md) | Price current exposure without smoothing | Accepted |
| [0007](0007-donation-resistance-via-curve-invariant.md) | Use the curve invariant for donation resistance | Accepted |
| [0008](0008-success-metrics-tracking-error-and-cost.md) | Measure tracking error and rebalancing cost | Accepted |
| [0009](0009-deploy-on-an-l2-at-launch.md) | Launch on an L2 | Accepted |
| [0010](0010-on-chain-form-aquaapp-vs-swapvm-instruction.md) | Deploy an independent SwapVM router | Accepted |
| [0011](0011-safe-wallet-with-basket-scope-guard.md) | Require a Safe with a Basket Scope Guard | Accepted |
| [0012](0012-price-deviation-circuit-breaker.md) | Block trades with excessive price deviation | Partially superseded by 0016 |
| [0013](0013-build-parameter-attestation-gate.md) | Require parameter attestation before trading | Accepted |
| [0014](0014-production-arbitrageur-design.md) | Run the production arbitrageur on Base | Proposed |
| [0015](0015-two-program-builders-for-the-resolver-kyc-gate.md) | Ship both a gated and an ungated PM strategy builder | Accepted |
| [0016](0016-per-trade-deviation-step-cap.md) | Cap per-trade deviation step instead of gating on pre-trade state | Accepted |
