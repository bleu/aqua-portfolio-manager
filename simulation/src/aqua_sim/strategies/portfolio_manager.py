"""The Portfolio Manager itself, as a `Strategy` — the constant-mean weighted curve
(`curve.py`, `PRICING.md`) plus ADR-0006's fee + gas-cost profitability gate, generalized
from a raw two-token pair to two declared `BasketGroup`s (ADR-0003), so PM correctly reacts
to another strategy moving a basket-mate's balance without PM itself having traded
(BLEUDEV-334 R5) — the same augmentation `basket.py` already does for one side, generalized
to both.
"""

from __future__ import annotations

from dataclasses import dataclass

from aqua_sim.basket_world import BasketGroup, BasketWorldView
from aqua_sim.curve import CurveState, apply_exact_in, spot_price
from aqua_sim.strategy import Trade

#: BLEUDEV-327's protocol fee, per 1IP-103 (1inch's governance-approved Aqua protocol fee
#: activation) — *not* an independent rate: a fraction of whatever `fee` the LP itself
#: configured, 100% to the 1inch DAO Treasury, no split with Bleu or any other operator
#: (the proposal defers operator compensation to a separate governance process). Mirrors
#: `PortfolioManagerProgramBuilder.daoFeeBps` exactly. Not a `PortfolioManagerStrategy`
#: field: on-chain this is computed by Bleu's own strategy-building tooling from the LP's
#: `feeBps`, never something an LP configures directly. Pulled directly from inside the
#: curve opcode's own execution, not a separate chainable instruction (`Aqua.ship()` is
#: permissionless, so a separate instruction could be omitted by a hand-crafted program) —
#: so, as modeled here too, it comes out of the wallet's `amount_in` credit, not out of the
#: curve's own pricing math; the taker pays/receives exactly what the curve quotes either way.
PROTOCOL_FEE_TIER_THRESHOLD = 0.001225  # 0.1225%, 1IP-103's tier boundary
PROTOCOL_FEE_LOW_TIER_SHARE = 1 / 4
PROTOCOL_FEE_HIGH_TIER_SHARE = 1 / 6


def protocol_fee_bps(lp_fee: float) -> float:
    """1IP-103's tiered protocol fee, as a fraction of `amount_in`: 1/4 of `lp_fee` at or
    below the tier threshold, 1/6 above it. `lp_fee = 0` correctly yields `0`."""
    share = PROTOCOL_FEE_LOW_TIER_SHARE if lp_fee <= PROTOCOL_FEE_TIER_THRESHOLD else PROTOCOL_FEE_HIGH_TIER_SHARE
    return lp_fee * share


def _target_balance_in_for_price(invariant_value: float, weight_in: float, weight_out: float, target_price: float) -> float:
    """Closed-form, fee-free sizing: the `balance_in` a curve with this invariant would
    have if its spot price were exactly `target_price`. Same derivation as
    `flows.py`'s private helper of the same name — kept local here since this module
    doesn't depend on `flows.py`'s two-token-only shape."""
    ratio = weight_in * target_price / weight_out
    return invariant_value * ratio**weight_out


@dataclass
class PortfolioManagerStrategy:
    """Quotes and trades one specific token pair (`token_a` in `group_a`, `token_b` in
    `group_b`), but prices against each group's full oracle-valued aggregate (ADR-0003),
    not just `token_a`/`token_b`'s own raw balances — a basket-mate's balance change
    shows up in the quote immediately, even though only `token_a`/`token_b` ever actually
    move from PM's own trades.

    Reduces to the plain two-token case exactly when `group_a`/`group_b` each contain
    only `token_a`/`token_b` (a group's `virtual_balance` divided by its one member's own
    price is just that member's raw balance).
    """

    id: str
    token_a: str
    token_b: str
    group_a: BasketGroup
    group_b: BasketGroup
    target_weight_a: float
    #: The LP's own curve fee (PRICING.md's `f`) — widens the curve, 100% of it stays
    #: with the wallet as pool value, exactly as `curve.py`'s `apply_exact_in` already
    #: models, net of whatever `protocol_fee_bps(fee)` above pulls out separately;
    #: BLEUDEV-327 keeps the two isolated rather than carving the protocol fee out of
    #: this one.
    fee: float = 0.0002
    gas_cost: float = 0.10

    def decide_trade(self, world: BasketWorldView) -> Trade | None:
        price_a = world.reference_prices[self.token_a]
        price_b = world.reference_prices[self.token_b]

        # Try both orientations each step -- same pattern as the old flows.py -- since
        # only one direction is ever actually profitable for a given skew.
        candidates = [
            (self.token_a, self.token_b, self.group_a, self.group_b, self.target_weight_a, price_a, price_b),
            (self.token_b, self.token_a, self.group_b, self.group_a, 1 - self.target_weight_a, price_b, price_a),
        ]
        for token_in, token_out, group_in, group_out, weight_in, price_in, price_out in candidates:
            weight_out = 1 - weight_in
            balance_in_aug = group_in.virtual_balance(world) / price_in
            balance_out_aug = group_out.virtual_balance(world) / price_out
            state = CurveState(balance_in_aug, balance_out_aug, weight_in, weight_out)

            # SP(i->o): units of token_in paid per unit of token_out received.
            market_rate = price_out / price_in
            pool_rate = spot_price(state)
            if pool_rate >= market_rate * (1 - self.fee):
                continue  # this side isn't cheap enough to be worth correcting

            invariant_value = balance_in_aug**weight_in * balance_out_aug**weight_out
            target_balance_in = _target_balance_in_for_price(invariant_value, weight_in, weight_out, market_rate)
            amount_in = target_balance_in - balance_in_aug
            if amount_in <= 0:
                continue

            _, amount_out = apply_exact_in(state, amount_in, self.fee)
            profit_in_value = (amount_out * price_out) - (amount_in * price_in)
            if profit_in_value < self.gas_cost:
                continue

            # Taker-side economics (amount_in/amount_out, the profitability check above)
            # are unaffected by the protocol fee — it's pulled from the wallet's own
            # credit after the fact, not folded into the curve's price (BLEUDEV-327).
            protocol_fee_amount = amount_in * protocol_fee_bps(self.fee)

            return Trade(
                strategy_id=self.id,
                token_in=token_in,
                token_out=token_out,
                amount_in=amount_in,
                amount_out=amount_out,
                protocol_fee_amount=protocol_fee_amount,
            )

        return None
