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
from aqua_sim.price_process import CompositePriceProcess, GBMPriceProcess, PriceProcess
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
    weth_price_process: PriceProcess | None = None,
    competitor_fee: float = 0.001,
    competitor_gas_cost: float = 0.01,
    seed: int | None = None,
) -> BasketWorld:
    group_weth = BasketGroup("weth", ("WETH",))
    group_stables = BasketGroup("stables", ("USDC", "USDT"))

    balances = {"WETH": initial_balance_weth, "USDC": initial_balance_usdc, "USDT": initial_balance_usdt}
    reference_prices = {"USDC": 1.0, "USDT": 1.0, "WETH": initial_price_weth}
    # Each competitor gets its own private reserve pair, seeded to open its *own* pair at
    # the real market price (equal dollar value on both sides -- an XYC pool's spot price
    # is its balance ratio, so seeding straight from the wallet's raw balances would be
    # wrong here: the wallet's split reflects the *group* target weight (50/50 between the
    # WETH group and the stables group), not the pairwise price a fresh pool needs to open
    # unbiased -- e.g. 10 WETH : 15,000 USDC implies 1,500 USDC/WETH, not the real 2,000,
    # handing the competitor an arbitrage windfall on step 0). The nominal depth (how much
    # value the pool opens with) is the pair's combined real-balance value, split evenly;
    # only the *split*, not the depth, matters for getting the opening price right. Each
    # competitor's reserves then evolve only from that instance's own trades from there on
    # -- so a trade on one pair (e.g. WETH/USDC) never affects a different instance's own
    # quote (e.g. WETH/USDT), the same way two unrelated Uniswap pools don't share reserves.
    strategies = []
    for token_a, token_b in combinations(balances.keys(), 2):
        price_a, price_b = reference_prices[token_a], reference_prices[token_b]
        depth_value = balances[token_a] * price_a + balances[token_b] * price_b
        strategies.append(
            XYCCompetitorStrategy(
                id=f"competitor_{token_a}_{token_b}",
                token_a=token_a,
                token_b=token_b,
                virtual_balance_a=(depth_value / 2) / price_a,
                virtual_balance_b=(depth_value / 2) / price_b,
                fee=competitor_fee,
                gas_cost=competitor_gas_cost,
            )
        )

    world = BasketWorld(
        token_balances=dict(balances),
        groups=[group_weth, group_stables],
        strategies=strategies,
        guard=GroupBoundaryGuard(pm_strategy_id=PM_ID),
        price_process=CompositePriceProcess(
            [
                weth_price_process
                or GBMPriceProcess(token_id="WETH", sigma_per_step=weth_sigma_per_step, initial_price=initial_price_weth, seed=seed),
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
    world.reference_prices = reference_prices
    return world
