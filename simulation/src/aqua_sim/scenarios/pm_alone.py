"""R1 baseline: PM's own math, no competitors, no basket-mates — the direct successor to
`simulate.run_mechanism_simulation`'s scope, rebuilt on `BasketWorld` so it exercises the
exact same code path every other scenario does."""

from __future__ import annotations

from aqua_sim.basket_world import BasketGroup, BasketWorld, GroupBoundaryGuard, MetricsRecorder
from aqua_sim.price_process import CompositePriceProcess, GBMPriceProcess
from aqua_sim.strategies.portfolio_manager import PortfolioManagerStrategy

PM_ID = "pm"


def build_world(
    *,
    initial_balance_a: float = 10_000.0,
    initial_price_a: float = 2000.0,
    target_weight_a: float = 0.5,
    sigma_per_step: float = 0.01,
    fee: float = 0.0002,
    gas_cost: float = 0.10,
    seed: int | None = None,
) -> BasketWorld:
    group_a = BasketGroup("A", ("TOKEN_A",))
    group_b = BasketGroup("B", ("TOKEN_B",))

    pm = PortfolioManagerStrategy(
        id=PM_ID,
        token_a="TOKEN_A",
        token_b="TOKEN_B",
        group_a=group_a,
        group_b=group_b,
        target_weight_a=target_weight_a,
        fee=fee,
        gas_cost=gas_cost,
    )

    initial_balance_b = initial_balance_a * initial_price_a * (1 - target_weight_a) / target_weight_a

    world = BasketWorld(
        token_balances={"TOKEN_A": initial_balance_a, "TOKEN_B": initial_balance_b},
        groups=[group_a, group_b],
        strategies=[pm],
        guard=GroupBoundaryGuard(pm_strategy_id=PM_ID),
        price_process=CompositePriceProcess(
            [GBMPriceProcess(token_id="TOKEN_A", sigma_per_step=sigma_per_step, initial_price=initial_price_a, seed=seed)]
        ),
        metrics=MetricsRecorder(group_a_id="A", group_b_id="B", target_weight_a=target_weight_a),
    )
    world.reference_prices = {"TOKEN_A": initial_price_a, "TOKEN_B": 1.0}
    return world
