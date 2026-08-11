# Architecture Decision Records

Lightweight ADRs (Nygard-style: Context / Decision / Consequences) for this project. Start a
new one from [`0000-template.md`](0000-template.md); number sequentially, never renumber or
delete a merged ADR — mark it **Superseded by ADR-XXXX** instead and let the new one explain
why.

Most of these decisions were made before this repo existed, during the grant proposal's design
process. Each ADR here is the durable, code-repo-local record of one of those decisions,
grounded against the Aqua/swapVM interfaces.

| # | Title | Status |
|---|---|---|
| [0001](0001-license-under-aqua-source-not-mit.md) | License this repo's own code under Aqua-Source-1.1, not MIT | Accepted |
| [0002](0002-dedicated-maker-wallet-as-portfolio-scope.md) | Dedicated maker wallet as portfolio scope, zero Aqua protocol changes | Accepted |
| [0003](0003-oracle-valued-token-groups.md) | Oracle-valued token groups, not per-token targets | Accepted |
| [0004](0004-constant-mean-weighted-curve-pricing.md) | Constant-mean weighted curve pricing, reimplemented independently | Accepted |
| [0005](0005-chainlink-push-oracles.md) | Chainlink-style push oracles, bluechip-first | Accepted |
| [0006](0006-exposure-smoothing.md) | EMA/TWAP + tolerance band + rate caps for exposure smoothing | Accepted |
| [0007](0007-donation-resistance-via-curve-invariant.md) | Donation resistance via curve invariant, not internal accounting | Accepted (round-trip proof owed by M1) |
| [0008](0008-success-metrics-tracking-error-and-cost.md) | Success = tracking error + cost of rebalancing, not fee/volume | Accepted |
| [0009](0009-deploy-on-base-at-launch.md) | Deploy on Base at launch | Accepted (held loosely) |
| [0010](0010-on-chain-form-aquaapp-vs-swapvm-instruction.md) | On-chain form: AquaApp vs. swapVM instruction vs. hybrid | **Proposed — M1 deliverable** |
