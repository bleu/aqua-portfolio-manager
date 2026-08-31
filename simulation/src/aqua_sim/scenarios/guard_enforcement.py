"""R6: another strategy attempts to trade *across* a declared group boundary specifically
to rebalance the shared wallet's exposure. Expected, correct result: `GroupBoundaryGuard`
(simulating ADR-0011's Basket Scope Guard) blocks it structurally, every time — a
regression/robustness check, not a risk-modeling exercise. PM is deliberately NOT
registered as a strategy here: this scenario tests the guard's enforcement in isolation,
independent of whether PM itself is also present and correcting.
"""

from __future__ import annotations

from aqua_sim.basket_world import BasketGroup, BasketWorld, GroupBoundaryGuard, MetricsRecorder
from aqua_sim.price_process import CompositePriceProcess, GBMPriceProcess
from aqua_sim.strategies.xyc_competitor import XYCCompetitorStrategy

PM_ID = "pm"  # the one strategy id the guard would exempt -- never actually registered here
ROGUE_ID = "rogue"


def build_world(
    *,
    initial_balance_a: float = 10.0,
    initial_balance_b: float = 20_000.0,
    initial_price_a: float = 2000.0,
    sigma_per_step: float = 0.02,
    rogue_fee: float = 0.003,
    rogue_gas_cost: float = 0.10,
    seed: int | None = None,
) -> BasketWorld:
    group_a = BasketGroup("A", ("TOKEN_A",))
    group_b = BasketGroup("B", ("TOKEN_B",))

    rogue = XYCCompetitorStrategy(id=ROGUE_ID, token_a="TOKEN_A", token_b="TOKEN_B", fee=rogue_fee, gas_cost=rogue_gas_cost)

    world = BasketWorld(
        token_balances={"TOKEN_A": initial_balance_a, "TOKEN_B": initial_balance_b},
        groups=[group_a, group_b],
        strategies=[rogue],
        guard=GroupBoundaryGuard(pm_strategy_id=PM_ID),
        price_process=CompositePriceProcess(
            [GBMPriceProcess(token_id="TOKEN_A", sigma_per_step=sigma_per_step, initial_price=initial_price_a, seed=seed)]
        ),
        metrics=MetricsRecorder(group_a_id="A", group_b_id="B", target_weight_a=0.5),
    )
    world.reference_prices = {"TOKEN_A": initial_price_a, "TOKEN_B": 1.0}
    return world
