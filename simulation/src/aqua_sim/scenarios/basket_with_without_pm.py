"""R5: another (profit-seeking) strategy trading within PM's declared "stables" group,
with PM present and correcting vs. PM absent (no correction fires) — isolates what PM's
own presence contributes to tracking error, generalized from `basket.py`'s one hardcoded
co-basket agent to any `Strategy` implementation (here, `XYCCompetitorStrategy`).

`weth_drift_per_step` defaults to `0.0` (driftless, matching every other scenario in this
suite) but can be set to force a directional price trend — e.g. to see whether PM's
active rebalancing helps or costs the portfolio when WETH is genuinely trending up, not
just noisily wandering. For a price regime GBM can't express at all (e.g. mean-reverting,
`price_process.MeanRevertingPriceProcess`), pass `weth_price_process` directly instead —
it overrides `weth_sigma_per_step`/`weth_drift_per_step` entirely.
"""

from __future__ import annotations

from aqua_sim.basket_world import BasketGroup, BasketWorld, GroupBoundaryGuard, MetricsRecorder
from aqua_sim.price_process import CompositePriceProcess, GBMPriceProcess, PriceProcess
from aqua_sim.strategies.portfolio_manager import PortfolioManagerStrategy
from aqua_sim.strategies.xyc_competitor import XYCCompetitorStrategy

PM_ID = "pm"
COMPETITOR_ID = "stables_competitor"


def build_world(
    *,
    with_pm: bool,
    initial_balance_weth: float = 10.0,
    initial_balance_usdc: float = 15_000.0,
    initial_balance_usdt: float = 5_000.0,
    initial_price_weth: float = 2000.0,
    target_weight_a: float = 0.5,
    weth_sigma_per_step: float = 0.01,
    weth_drift_per_step: float = 0.0,
    usdt_depeg_sigma_per_step: float = 0.0005,
    weth_price_process: PriceProcess | None = None,
    pm_fee: float = 0.0002,
    pm_gas_cost: float = 0.10,
    competitor_fee: float = 0.001,
    competitor_gas_cost: float = 0.01,
    seed: int | None = None,
) -> BasketWorld:
    group_weth = BasketGroup("weth", ("WETH",))
    group_stables = BasketGroup("stables", ("USDC", "USDT"))

    strategies = []
    if with_pm:
        strategies.append(
            PortfolioManagerStrategy(
                id=PM_ID,
                token_a="WETH",
                token_b="USDC",
                group_a=group_weth,
                group_b=group_stables,
                target_weight_a=target_weight_a,
                fee=pm_fee,
                gas_cost=pm_gas_cost,
            )
        )
    strategies.append(
        XYCCompetitorStrategy(
            id=COMPETITOR_ID, token_a="USDC", token_b="USDT", fee=competitor_fee, gas_cost=competitor_gas_cost
        )
    )

    world = BasketWorld(
        token_balances={"WETH": initial_balance_weth, "USDC": initial_balance_usdc, "USDT": initial_balance_usdt},
        groups=[group_weth, group_stables],
        strategies=strategies,
        guard=GroupBoundaryGuard(pm_strategy_id=PM_ID),
        price_process=CompositePriceProcess(
            [
                weth_price_process
                or GBMPriceProcess(
                    token_id="WETH",
                    sigma_per_step=weth_sigma_per_step,
                    drift_per_step=weth_drift_per_step,
                    initial_price=initial_price_weth,
                    seed=seed,
                ),
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
