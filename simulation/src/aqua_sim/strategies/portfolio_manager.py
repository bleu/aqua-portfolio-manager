"""Weighted-curve PM model with oracle-valued groups and a taker profitability gate after fees and gas."""

from __future__ import annotations

from dataclasses import dataclass

from aqua_sim.basket_world import BasketGroup, BasketWorldView
from aqua_sim.curve import CurveState, apply_exact_in, spot_price
from aqua_sim.strategy import Trade


def _target_balance_in_for_price(invariant_value: float, weight_in: float, weight_out: float, target_price: float) -> float:
    """Return the fee-free input reserve that gives target_price at the supplied invariant and weights."""
    ratio = weight_in * target_price / weight_out
    return invariant_value * ratio**weight_out


@dataclass
class PortfolioManagerStrategy:
    """Trade one token pair using each group's full oracle-valued reserve.

    Other members affect the quote but do not move in this trade.
    Single-member groups reduce to the ordinary two-token curve."""

    id: str
    token_a: str
    token_b: str
    group_a: BasketGroup
    group_b: BasketGroup
    target_weight_a: float
    fee: float = 0.0002
    gas_cost: float = 0.10

    def decide_trade(self, world: BasketWorldView) -> Trade | None:
        price_a = world.reference_prices[self.token_a]
        price_b = world.reference_prices[self.token_b]

        # Check both trade directions for profitable correction.
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

            return Trade(strategy_id=self.id, token_in=token_in, token_out=token_out, amount_in=amount_in, amount_out=amount_out)

        return None
