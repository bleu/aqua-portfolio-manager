"""Trading-agent protocol and proposed trades for BasketWorld validation and settlement."""

from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING, Protocol

if TYPE_CHECKING:
    from aqua_sim.basket_world import BasketWorldView


@dataclass(frozen=True)
class Trade:
    """An exact-in trade proposed by a strategy.

    The wallet receives token_in/amount_in and pays token_out/amount_out.
    strategy_id identifies the proposer for group checks and value attribution.
    The strategy computes amount_out. BasketWorld validates and applies it without repricing."""

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
        """Return a proposed Trade or None. Do not mutate the supplied world or balances. BasketWorld validates and settles trades."""
        ...
