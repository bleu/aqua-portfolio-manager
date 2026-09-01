"""No PM registered, so there's no Guard (see `basket_world.GroupBoundaryGuard` — the real
`BasketScopeGuard.sol` only exists because it's installed on PM's own dedicated wallet).
Instead of one competitor confined to a single pair (`basket_with_without_pm.py`'s
"without PM" arm), this deploys an independent, profit-seeking `XYCCompetitorStrategy` on
*every* pairwise combination of the wallet's tokens — a fully-connected set with nothing
stopping any of them from moving WETH against the stables.

This is the second half of the comparison: does an unconstrained set of ordinary,
profit-seeking strategies rebalance the wallet anywhere close to what PM (with the Guard
confining everyone else to one group) achieves on its own?
"""

from __future__ import annotations

from itertools import combinations

from aqua_sim.basket_world import BasketGroup, BasketWorld, GroupBoundaryGuard, MetricsRecorder
from aqua_sim.price_process import CompositePriceProcess, GBMPriceProcess
from aqua_sim.strategies.xyc_competitor import XYCCompetitorStrategy

PM_ID = "pm"  # never registered here -- the guard's PM exemption is moot with no PM present


def build_world(
    *,
    initial_balance_weth: float = 10.0,
    initial_balance_usdc: float = 15_000.0,
    initial_balance_usdt: float = 5_000.0,
    initial_price_weth: float = 2000.0,
    target_weight_a: float = 0.5,
    weth_sigma_per_step: float = 0.01,
    usdt_depeg_sigma_per_step: float = 0.0005,
    competitor_fee: float = 0.001,
    competitor_gas_cost: float = 0.01,
    seed: int | None = None,
) -> BasketWorld:
    group_weth = BasketGroup("weth", ("WETH",))
    group_stables = BasketGroup("stables", ("USDC", "USDT"))

    balances = {"WETH": initial_balance_weth, "USDC": initial_balance_usdc, "USDT": initial_balance_usdt}
    strategies = [
        XYCCompetitorStrategy(
            id=f"competitor_{token_a}_{token_b}", token_a=token_a, token_b=token_b, fee=competitor_fee, gas_cost=competitor_gas_cost
        )
        for token_a, token_b in combinations(balances.keys(), 2)
    ]

    world = BasketWorld(
        token_balances=dict(balances),
        groups=[group_weth, group_stables],
        strategies=strategies,
        guard=GroupBoundaryGuard(pm_strategy_id=PM_ID),
        price_process=CompositePriceProcess(
            [
                GBMPriceProcess(token_id="WETH", sigma_per_step=weth_sigma_per_step, initial_price=initial_price_weth, seed=seed),
                GBMPriceProcess(
                    token_id="USDT",
                    sigma_per_step=usdt_depeg_sigma_per_step,
                    initial_price=1.0,
                    seed=None if seed is None else seed + 1,
                ),
            ]
        ),
        metrics=MetricsRecorder(group_a_id="weth", group_b_id="stables", target_weight_a=target_weight_a),
    )
    world.reference_prices = {"USDC": 1.0, "USDT": 1.0, "WETH": initial_price_weth}
    return world
