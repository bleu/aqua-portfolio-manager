"""The `Strategy` protocol every trading agent in `basket_world.py` implements, and the
`Trade` value object strategies use to describe what they want to do.

Every agent that can move a token balance in the shared basket world — the Portfolio
Manager, a competing swapVM strategy (`xyc.py`-based or otherwise), or organic background
flow — is just a different `Strategy` implementation plugged into the same simulation
loop, not a special-cased code path. This is deliberate: `BasketWorld` never needs to know
*how* a strategy decided to trade, only that it produced a `Trade` (or didn't), which the
world then validates against the group-boundary rule (ADR-0011) and applies.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING, Protocol

if TYPE_CHECKING:
    from aqua_sim.basket_world import BasketWorldView


@dataclass(frozen=True)
class Trade:
    """One strategy's proposed (or already-applied) exact-in trade.

    `token_in`/`amount_in` is what the *wallet* receives, `token_out`/`amount_out` is
    what it pays out — same convention as `curve.py`'s `CurveState`/`apply_exact_in`
    (`balance_in` increases, `balance_out` decreases). A pool that's overweight in some
    token sheds it via a trade where that token is `token_out`, not `token_in`.

    `strategy_id` identifies who proposed it — `GroupBoundaryGuard` uses this to grant
    the one exemption ADR-0011 allows (PM's own strategy may cross a group boundary;
    nothing else may). `amount_out` is filled in by the strategy's own pricing math
    before the trade is offered to `BasketWorld.apply` — the world never re-derives it,
    only validates and moves balances.
    """

    strategy_id: str
    token_in: str
    token_out: str
    amount_in: float
    amount_out: float


class Strategy(Protocol):
    """A trading agent `BasketWorld` can register and step. Implementations: the
    Portfolio Manager (`strategies/portfolio_manager.py`), a competing swapVM strategy
    (`strategies/xyc_competitor.py`), and organic noise flow
    (`strategies/noise_trader.py`).
    """

    id: str

    def decide_trade(self, world: "BasketWorldView") -> Trade | None:
        """Looks at the current world state and returns a `Trade` it wants to make, or
        `None` if nothing is worth doing this step. Pure decision — must not mutate
        `world` or any balance; `BasketWorld.apply` is the only thing allowed to do
        that, after checking the group-boundary rule.
        """
        ...
