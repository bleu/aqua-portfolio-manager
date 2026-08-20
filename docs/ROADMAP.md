# Roadmap

Tracks execution against the 1inch Aqua Incubator grant's four milestones. Each milestone's
tasks are pulled from open items already named in [`adr/`](adr/README.md); an ADR link means
"this task is what closes that ADR's open question," not new scope.

**Dates below are first-pass estimates, not commitments.** They assume a start of
**2026-08-11** and back-to-back milestones with no slack for the team's other work. M4's
duration is the least reliable of the four: external audit scheduling and turnaround isn't
something engineering effort estimates control. Revisit this table once M1 is underway.

| Milestone | Disbursement | Status | Estimated duration | Estimated window |
|---|---|---|---|---|
| [M1 — Research & Spec](#m1--research--spec) | 5% ($2,500) | In progress | ~1 week | 2026-08-11 → 2026-08-18 |
| [M2 — PoC on testnet](#m2--poc-on-testnet) | 10% ($5,000) | Not started | ~1 week | 2026-08-18 → 2026-08-25 |
| [M3 — Full implementation](#m3--full-implementation) | 35% ($17,500) | Not started | ~3 weeks | 2026-08-25 → 2026-09-15 |
| [M4 — 1inch integration & audit gate](#m4--1inch-integration--audit-gate) | 50% ($25,000) | Not started | ~3 weeks | 2026-09-15 → 2026-10-06 |

Total: **~8 weeks (~2 months)** to a mainnet-ready, audited state, starting today.

## M1 — Research & Spec

**Estimated duration:** ~1 week (2026-08-11 → 2026-08-18)
**Why this is tight but realistic:** the team already has Balancer weighted-math and
hands-on swapVM context — this isn't a cold start. The invariant proof and parameter sweep are
real work, but they're bounded (the candidate knobs are already named), not open-ended.
**Goal:** pick the on-chain form and prove the mechanism is safe, with numbers — not code yet.

- [ ] Build the simulation notebook (flow modeled in two tiers: endogenous rebalancing/arb
      flow + exogenous organic flow) producing a tracking-error/cost-of-rebalancing frontier,
      protocol fee included on the cost side ([ADR-0008](adr/0008-success-metrics-tracking-error-and-cost.md)).
- [ ] From the frontier, pick concrete parameter values: tolerance band width, rate-cap
      thresholds — no EMA window, dropped from scope ([ADR-0006](adr/0006-exposure-smoothing.md)).
- [x] Prove the round-trip-always-favors-the-pool invariant for this specific curve
      implementation — the headline security deliverable. Closed by the curve invariant alone,
      unconditionally (no smoothing/lag bound needed) — see
      [`INVARIANT-PROOF.md`](INVARIANT-PROOF.md) and
      [ADR-0007](adr/0007-donation-resistance-via-curve-invariant.md).
- [x] Resolve the on-chain form: decided for an independent router deploying a new swapVM
      instruction (not `AquaApp`, not merged into 1inch's router) — made on the
      unilateral-deployability criterion and the PoC investment already made, ahead of the
      frontier/gas comparison below ([ADR-0010](adr/0010-on-chain-form-aquaapp-vs-swapvm-instruction.md),
      now `Accepted`).
- [ ] Write up the architecture decision: mechanism + form + numbers, in a form reviewable
      against the grant's pre-declared M1 criteria.

**Exit criteria:** simulation notebook and writeup delivered; ADR-0010 resolved; donation-attack
non-profitability proven, not just asserted.

## M2 — PoC on testnet

**Estimated duration:** ~1 week (2026-08-18 → 2026-08-25)
**Why this short:** by M2, the mechanism and parameters are already decided in M1 — this is
"build the minimal version of a known design," not open design work. Testnet deploy and wiring
the maker-wallet convention end to end are mechanical once the component logic exists.
**Goal:** the mechanism chosen in M1 actually runs, end to end, against testnet chain state.

- [ ] Implement a minimal version of every L2 component in [`ARCHITECTURE.md`](ARCHITECTURE.md):
      group config, declared-universe exposure reader, smoothing, oracle adapter, pricing
      engine.
- [ ] Wire the dedicated maker wallet convention end to end: ship a strategy from a fresh
      **Safe**, execute real trades, verify `balanceOf` reads match expectations
      ([ADR-0002](adr/0002-dedicated-maker-wallet-as-portfolio-scope.md)).
- [ ] Build and install the Basket Scope Guard on that Safe, and confirm it actually blocks a
      cross-group/outside-universe `ship()` attempt on testnet, not just in a local test
      ([ADR-0011](adr/0011-safe-wallet-with-basket-scope-guard.md),
      [`basket-scope-guard-design.md`](../thoughts/basket-scope-guard-design.md)).
- [ ] Deploy to a public testnet on the chosen chain ([ADR-0009](adr/0009-deploy-on-base-at-launch.md) —
      re-confirm Base is still the right call before deploying).
- [ ] Exercise discount/surcharge pricing in both directions with manual or scripted trades.

**Exit criteria:** PoC live on a public testnet; at least one real `ship()` → trade → settle
cycle demonstrated end to end, with the exposure reading behaving as the M1 model predicted.

## M3 — Full implementation

**Estimated duration:** ~3 weeks (2026-08-25 → 2026-09-15)
**Why this is the biggest engineering chunk:** production Solidity plus a Forge suite (fuzz
tests, same-block interaction scenarios, depeg guards, precision edge cases) takes time, and
this milestone is what an auditor will read in M4.
      **Goal:** production-grade code and a test suite that would survive an audit, not just the PoC.

- [ ] Full Solidity implementation of every component named in the M1 writeup and the
      [`ARCHITECTURE.md`](ARCHITECTURE.md) L2 diagram.
- [ ] Forge unit + fuzz test suite for the strategy contract, including intra-group drift by
      another strategy on the same wallet (accepted by design, ADR-0003) and a depeg divergence
      guard inside groups ([ADR-0003](adr/0003-oracle-valued-token-groups.md)).
- [x] Separately, a test suite for the Basket Scope Guard itself against a real Safe (not just
      the strategy contract): confirm it reverts every cross-group and outside-universe `ship()`
      attempt, allows PM's own re-ship, and behaves correctly through both `execTransaction` and
      a module path if any module is present ([ADR-0011](adr/0011-safe-wallet-with-basket-scope-guard.md)).
      Done ahead of schedule (BLEUDEV-320, local Safe v1.5.0) — prioritized as the riskiest new
      architectural bet, so the team could pivot early if it didn't hold up; still needs the
      testnet check in M2 above and an external audit before this counts as M3-done.
- [ ] Precision/edge-case handling near an empty pool: minimum-liquidity floor, round-in-the-
      pool's-favor ([ADR-0004](adr/0004-constant-mean-weighted-curve-pricing.md),
      [ADR-0007](adr/0007-donation-resistance-via-curve-invariant.md)).
- [ ] Reentrancy: confirm every swap-handling path is wrapped in `AquaApp`'s
      `nonReentrantStrategy` modifier before calling `_safeCheckAquaPush`.
- [ ] Gas-per-rebalance benchmarking against the real implementation, re-checked against the
      M1 simulation's assumptions.

**Exit criteria:** full test suite green; gas numbers within the M1 sim's cost-frontier
assumptions; code frozen and ready for external audit.

## M4 — 1inch integration & audit gate

**Estimated duration:** ~3 weeks (2026-09-15 → 2026-10-06)
**Why this is the least reliable estimate:** most of this time is the external audit itself —
scheduling an auditor's availability and their turnaround on findings is not under the team's
control the way M1–M3's effort is. Routing integration, onboarding docs, and deployment are
fast; the audit is the pacing item, and 3 weeks assumes an auditor is lined up in advance, not
found cold after M3 ships.
**Goal:** live, audited, and reachable through 1inch — not just deployed.

- [ ] External audit of the M3-frozen implementation.
- [ ] Confirm the strategy is reachable through 1inch's own routing, not only via direct calls
      ([ADR-0009](adr/0009-deploy-on-base-at-launch.md)).
- [ ] Onboarding guide / migration checklist for LPs adopting the dedicated maker wallet
      convention — setting up a fresh wallet, funding it, re-shipping existing strategies from
      it ([ADR-0002](adr/0002-dedicated-maker-wallet-as-portfolio-scope.md)).
- [ ] Mainnet (or chosen-chain) deployment.
- [ ] Stand up post-launch monitoring; commit to the non-gating +3-month report (managed TVL,
      active LPs, realized tracking error and cost vs. the M1 simulation).

**Exit criteria:** audited, deployed, routable through 1inch, LP onboarding path documented and
usable by someone who isn't the team that built it.
