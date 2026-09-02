"""R6: with PM registered and correcting, another strategy attempts to trade *across* a
declared group boundary specifically to rebalance the shared wallet's exposure. Expected,
correct result: `GroupBoundaryGuard` (simulating ADR-0011's Basket Scope Guard) blocks it
structurally, every time — a regression/robustness check, not a risk-modeling exercise.

PM must be registered for this to mean anything: the real `BasketScopeGuard.sol` only
exists because it's installed on PM's own dedicated wallet (ADR-0002) — with no PM present
there's no Guard, and nothing is blocked (see `basket_world.GroupBoundaryGuard` and
`scenarios/cross_basket_no_pm.py` for that contrasting case).
"""

from __future__ import annotations

from aqua_sim.basket_world import BasketGroup, BasketWorld, GroupBoundaryGuard, MetricsRecorder
from aqua_sim.price_process import CompositePriceProcess, GBMPriceProcess
from aqua_sim.strategies.portfolio_manager import PortfolioManagerStrategy
from aqua_sim.strategies.xyc_competitor import XYCCompetitorStrategy

PM_ID = "pm"
ROGUE_ID = "rogue"


def build_world(
    *,
    initial_balance_a: float = 10.0,
    initial_balance_b: float = 20_000.0,
    initial_price_a: float = 2000.0,
    target_weight_a: float = 0.5,
    sigma_per_step: float = 0.02,
    pm_fee: float = 0.0002,
    pm_gas_cost: float = 0.10,
    rogue_fee: float = 0.0,
    rogue_gas_cost: float = 0.0,
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
        fee=pm_fee,
        gas_cost=pm_gas_cost,
    )
    # rogue defaults to zero fee/gas -- with PM actively defending the pool every step,
    # any residual mispricing is tiny (bounded by PM's own fee), so a rogue with a
    # realistic cost structure would rarely find anything worth attempting at all. Zero
    # cost is the strongest version of this check: even a maximally aggressive, free
    # attacker still can't get a single cross-group trade through.
    rogue = XYCCompetitorStrategy(id=ROGUE_ID, token_a="TOKEN_A", token_b="TOKEN_B", fee=rogue_fee, gas_cost=rogue_gas_cost)

    world = BasketWorld(
        token_balances={"TOKEN_A": initial_balance_a, "TOKEN_B": initial_balance_b},
        groups=[group_a, group_b],
        strategies=[pm, rogue],
        guard=GroupBoundaryGuard(pm_strategy_id=PM_ID),
        price_process=CompositePriceProcess(
            [GBMPriceProcess(token_id="TOKEN_A", sigma_per_step=sigma_per_step, initial_price=initial_price_a, seed=seed)]
        ),
        metrics=MetricsRecorder(group_a_id="A", group_b_id="B", target_weight_a=target_weight_a),
    )
    world.reference_prices = {"TOKEN_A": initial_price_a, "TOKEN_B": 1.0}
    return world
