# ADR-0006: Exposure guardrails — a fee + gas-cost profitability gate (no tolerance band, no rate cap, no EMA/TWAP)

**Status:** Accepted. This design superseded an earlier tolerance-band/rate-cap approach —
see "History" below for why.

## Context

The exposure reader (ADR-0002) reads a wallet's settled balance, which means it can move
in a single block — either from legitimate strategy settlement, another of the LP's own
strategies sharing the wallet, or from someone transferring tokens in deliberately (a donation,
see ADR-0007). The original version of this ADR fed that reading through an EMA or TWAP before
pricing, reasoning that a single-block change moving the quoted price instantly was a donation
vector.

**That reasoning didn't survive scrutiny — for donations.** ADR-0007's invariant proof
(`../INVARIANT-PROOF.md`) holds regardless of *how* the pre-trade balance got to be what it is,
for this strategy's own trades and for pure donations, as long as pricing reads the *current*
real balance directly. Smoothing didn't add donation resistance; it *cost* some, by introducing a
lag between the real balance and the quoted price that a patient attacker could trade against
during convergence — a harder proof obligation that the plain, un-smoothed curve never needed in
the first place. **Cross-strategy interaction turned out to need its own fix** (`ADR-0011`'s
Basket Scope Guard) — dropping smoothing didn't close that gap by itself; see the correction in
`../INVARIANT-PROOF.md`.

## Decision

No moving average, no tolerance band, no rate cap. The exposure reading feeds the pricing
engine directly off the current real balance, and a correction fires whenever doing so is
profitable net of two costs, both fixed outside this ADR's scope:

- **`fee`** — the protocol fee, fixed at 2 bps by ADR-0008.
- **`gas_cost_b`** — the arbitrageur's own real transaction cost, a placeholder based on
  observed Base costs (**$0.10** — see History for how that number was arrived at).

Nothing else gates a correction. A tolerance band and a rate cap were both tried first (see
History) and dropped: at a realistic gas cost, neither reduces cost at all — the fee savings
from correcting less often are almost exactly cancelled out by more value leaking to the
market while the pool sits stale (a Loss-Versus-Rebalancing-style effect, not a tuning
problem) — while tracking error gets dramatically worse. There is no cost/tracking trade-off
here for either knob to usefully exploit.

## Consequences

- Donation resistance no longer depends on any parameter choice here — it's fully closed by the
  curve invariant alone (`../INVARIANT-PROOF.md`). Cross-strategy resistance was never this
  ADR's job to close and still isn't — that's `ADR-0011`, enforced at the wallet level, not by
  any parameter picked here.
- No free parameters remain in this ADR's scope: `fee` is fixed by ADR-0008, and `gas_cost_b`
  is an external, real-world number (Base's own transaction costs), not something this design
  picks. Once a gas-per-rebalance number for the actual deployed contract exists
  (`BLEUDEV-265`), `gas_cost_b` should be replaced by that measured value — tightening an
  input, not reopening a design choice.
- This doesn't change the cost-vs-baselines finding from the same work (0 of 10 swept baseline
  settings beat the mechanism on both cost and tracking at once — see `ARCHITECTURE.md`'s
  Milestone 1 section): the mechanism's cost floor is a structural consequence of quoting
  continuously at all, not something a parameter choice inside this design can lower.

## History

**Initial tolerance-band/rate-cap sweep:** chose a 0.5% tolerance band and a 1-hour rate cap, from a sweep
in a notebook since deleted (`10_parameter_decision.ipynb`) that measured cost, tracking
error, shock-recovery time, and stale-quote exploit exposure — all of which got monotonically
worse as either knob loosened. The chosen values were a deliberate step back from that sweep's
mathematical optimum (a 0.1% band, 5-minute cap), trading tracking tightness for fewer
corrective transactions (8,760/year worst case vs. 105,120/year at the optimum) — under a
**$5-per-correction gas placeholder** reused from elsewhere in the simulation.

**Realistic-gas-cost re-sweep:** that $5 gas figure was never checked against Base and turned out
to be roughly 50x too high — real Base transaction costs run $0.01-$0.10 (L2 execution + L1
data fee, OpenLiquid data, Q1 2026), corrected to **$0.10**. Redone at the realistic cost:

- A fee + gas-cost profitability gate alone (no separate band or cooldown) already limits
  corrections to something realistic — at $0.10 gas, corrections fire almost as often as with
  no gas cost at all, since $0.10 is cheap enough that nearly any real drift is worth
  correcting. Cost becomes dominated by cumulative trading-fee drag from correcting
  near-continuously, not by gas.

  ![Mechanism (single point) vs. naive baselines, at realistic Base gas cost](assets/0006-mechanism-vs-baselines.png)

- A tolerance band and/or cooldown on top of the realistic-gas gate was tested directly next,
  since cumulative fee drag looked like exactly the kind of cost a dead-zone might reduce.
  Over a 200x range of correction frequency (~10,655/year down to 53/year), cost barely moved
  (6.77% → 7.19%) while p95 tracking error got 40x worse (0.15% → 6.05%) — the fee savings
  from correcting less often are almost exactly cancelled out by more value leaking to the
  market while the pool sits stale.

  ![Sweeping tolerance band and cooldown at realistic gas cost](assets/0006-tolerance-cooldown-sweep.png)

Both charts and the underlying sweep are why the Decision above has no tolerance band or rate
cap: loosening either knob is strictly worse under a realistic gas cost, so there's nothing for
them to usefully trade off.

## References

- [`../ARCHITECTURE.md`](../ARCHITECTURE.md) — Exposure Smoothing component notes
- `simulation/` — the notebooks and code behind every number in this ADR (currently a
  separate open PR, not yet merged as of this writing)
