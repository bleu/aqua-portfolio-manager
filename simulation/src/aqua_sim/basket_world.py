"""The shared-wallet simulation environment: real token balances, ADR-0003's oracle-valued
group ("virtual balance") accounting, ADR-0011's group-boundary enforcement, and the step
loop that ties a `PriceProcess` and any number of `Strategy` implementations together.

This is the piece that didn't exist before BLEUDEV-334 (see
`thoughts/simulation-suite-v2-requirements.md`, Part 2) — `simulate.py`/`basket.py` each
special-cased one specific two-token, one-or-two-strategy scenario; this module makes the
number and kind of strategies, and the number of declared groups, run-time configuration
instead of separate code paths.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from aqua_sim.price_process import PriceProcess
from aqua_sim.strategy import Strategy, Trade


@dataclass(frozen=True)
class BasketGroup:
    """One declared token group (ADR-0003) — the unit ADR-0011's Basket Scope Guard
    protects the boundary of. A single-token "group" (`token_ids` of length 1) is the
    degenerate case of a token with no basket-mates; nothing here requires more than one.
    """

    group_id: str
    token_ids: tuple[str, ...]

    def contains(self, token_id: str) -> bool:
        return token_id in self.token_ids

    def virtual_balance(self, world: "BasketWorldView") -> float:
        """`Σ balance_j × oracle_price_j` over this group's members (ADR-0003) — what
        PM's curve actually prices against, not any single member's raw balance."""
        return sum(world.token_balances[t] * world.reference_prices[t] for t in self.token_ids)


class UnknownTokenError(ValueError):
    """A trade referenced a token that isn't in any declared `BasketGroup` — ADR-0011
    blocks touching a token outside the declared universe, same as crossing a boundary."""


@dataclass(frozen=True)
class GroupBoundaryGuard:
    """Simulates ADR-0011's Basket Scope Guard: every strategy except those explicitly
    trading PM's own declared pair is confined to trading *within* a single declared
    group, but only when PM is actually registered in this world.

    The real `BasketScopeGuard.sol` is a Safe Transaction Guard installed on PM's own
    dedicated maker wallet (ADR-0002) — only PM's own registered strategy contract is
    ever authorized to move that wallet's funds at all (`TRUSTED_PM_STRATEGY_HASH`), so
    *any* settlement against PM's declared pair — whether the counterparty is an
    arbitrageur correcting price or organic flow clearing through it — is exempt the same
    way. `pm_strategy_id` is the strategy whose presence determines whether this Guard
    exists at all (`pm_present`); `also_exempt_ids` covers any other strategy (e.g.
    organic flow) that's also legitimately settling against PM's own pair, not some other
    strategy crossing a group boundary it has no business touching. There is no
    real-world wallet with this Guard installed and no PM ever shipped to it; a wallet
    with no PM simply never has this Guard in the first place, so nothing on it is
    confined to a single group. `check`'s `pm_present` argument models exactly that: with
    `pm_present=False`, every trade is allowed regardless of group membership.
    """

    pm_strategy_id: str
    also_exempt_ids: frozenset[str] = frozenset()

    def group_of(self, token_id: str, groups: list[BasketGroup]) -> BasketGroup | None:
        for group in groups:
            if group.contains(token_id):
                return group
        return None

    def check(self, trade: Trade, groups: list[BasketGroup], pm_present: bool) -> bool:
        if not pm_present:
            return True
        group_in = self.group_of(trade.token_in, groups)
        group_out = self.group_of(trade.token_out, groups)
        same_group = group_in is not None and group_out is not None and group_in.group_id == group_out.group_id
        if same_group:
            return True
        return trade.strategy_id == self.pm_strategy_id or trade.strategy_id in self.also_exempt_ids


@dataclass(frozen=True)
class BasketWorldView:
    """Read-only snapshot handed to every `Strategy.decide_trade` — deliberately not a
    reference to the live `BasketWorld`, so no strategy can mutate state directly or see
    more than "current balances + prices + declared groups". Keeps PM, a competing
    strategy, and organic flow symmetric under the same interface."""

    token_balances: dict[str, float]
    reference_prices: dict[str, float]
    groups: list[BasketGroup]

    def group_of(self, token_id: str) -> BasketGroup | None:
        for group in self.groups:
            if group.contains(token_id):
                return group
        return None


@dataclass
class MetricsRecorder:
    """Records what a `BasketWorld` run needs for the R5 with-PM/without-PM comparison:
    each declared pair's virtual-balance path and the tracking error against a declared
    target weight, generalizing `metrics.py`'s `tracking_error` from raw two-token
    balances to arbitrary oracle-valued groups (ADR-0003).

    Deliberately does not (yet) generalize `metrics.py`'s `cost_of_rebalancing` — that
    metric's frictionless-reference benchmark assumes only one side's *price* moves
    between steps, which doesn't hold once other strategies can also move a group's real
    balances (the whole point of R5). Extending "cost" to that case is its own design
    question, not reimplemented here as a shortcut.
    """

    group_a_id: str
    group_b_id: str
    target_weight_a: float
    value_a_path: list[float] = field(default_factory=list)
    value_b_path: list[float] = field(default_factory=list)
    tracking_error_path: list[float] = field(default_factory=list)
    captured_value_paths: dict[str, list[float]] = field(default_factory=dict)

    def record(self, world: "BasketWorld") -> None:
        view = world.view()
        group_a = next(g for g in world.groups if g.group_id == self.group_a_id)
        group_b = next(g for g in world.groups if g.group_id == self.group_b_id)
        value_a = group_a.virtual_balance(view)
        value_b = group_b.virtual_balance(view)
        total = value_a + value_b
        if total <= 0:
            raise ValueError(f"total value of groups {self.group_a_id!r}/{self.group_b_id!r} must be positive, got {total}")

        self.value_a_path.append(value_a)
        self.value_b_path.append(value_b)
        self.tracking_error_path.append(abs(value_a / total - self.target_weight_a))
        for strategy in world.strategies:
            captured = world.strategy_captured_value.get(strategy.id, 0.0)
            self.captured_value_paths.setdefault(strategy.id, []).append(captured)


@dataclass
class BasketWorld:
    """Owns every real balance, every declared group, every registered strategy, the
    price process, the group-boundary guard, and the step loop that ties them together.

    Strategies act in registration order, each seeing the effects of every trade already
    applied earlier in the *same* step (sequential, not simultaneous-against-a-stale-
    snapshot) — closer to how transactions actually order within a block than a
    collect-then-apply-all model, and it avoids one strategy's decision going stale
    before it's even applied.
    """

    token_balances: dict[str, float]
    groups: list[BasketGroup]
    strategies: list[Strategy]
    guard: GroupBoundaryGuard
    price_process: PriceProcess
    metrics: MetricsRecorder
    reference_prices: dict[str, float] = field(default_factory=dict)
    blocked_trades: list[Trade] = field(default_factory=list)
    strategy_captured_value: dict[str, float] = field(default_factory=dict)
    #: Cumulative BLEUDEV-327 protocol fee pulled from wallet balances across every
    #: applied trade (any strategy's — 0 for one that never sets `Trade.protocol_fee_amount`).
    #: Tracked in aggregate, not split DAO/Bleu, since the 1bps/1bps split is a fixed
    #: constant at collection time (`strategies/portfolio_manager.py`), not something
    #: this economic model needs to attribute separately to study cost/tracking-error.
    protocol_fee_revenue: float = 0.0

    def view(self) -> BasketWorldView:
        return BasketWorldView(
            token_balances=dict(self.token_balances),
            reference_prices=dict(self.reference_prices),
            groups=self.groups,
        )

    def apply(self, trade: Trade) -> bool:
        """Validates `trade` against the group-boundary rule and current liquidity, then
        mutates balances. Returns whether it was applied — `False` means the guard
        blocked it (recorded in `blocked_trades`, this is what the R6 scenario checks)
        or the pool didn't have enough of `token_out` to actually pay it out.

        No `Strategy` here owns the wallet it trades against -- every registered strategy
        is a *taker* quoting/settling against the shared pool (`token_balances`), same as
        a real arbitrageur or organic swapper never gets to be the AMM they're trading
        with. `strategy_captured_value` marks that split explicitly: whatever
        mark-to-market value the pool gives up on a trade (received at `token_in`'s price,
        paid out at `token_out`'s price) is attributed as *captured by* the strategy that
        submitted it -- negative when the trade is bad for the pool (an arbitrage-style
        correction), positive when it's good for the pool (e.g. organic flow paying a
        fee). This is a notional value ledger for charting "who's winning," not a second
        token balance sheet -- the pool's own `token_balances` remain the only real
        reserves this world tracks.
        """
        if trade.token_in not in self.token_balances or trade.token_out not in self.token_balances:
            raise UnknownTokenError(f"trade references a token not in this world: {trade.token_in}/{trade.token_out}")
        pm_present = any(s.id == self.guard.pm_strategy_id for s in self.strategies)
        if not self.guard.check(trade, self.groups, pm_present):
            self.blocked_trades.append(trade)
            return False
        if trade.amount_out >= self.token_balances[trade.token_out]:
            return False

        pool_value_change = trade.amount_in * self.reference_prices[trade.token_in] - trade.amount_out * self.reference_prices[trade.token_out]
        self.strategy_captured_value[trade.strategy_id] = self.strategy_captured_value.get(trade.strategy_id, 0.0) - pool_value_change

        # The wallet's real credit is amount_in net of the protocol fee pulled out on
        # top of it (BLEUDEV-327) — 0 for any strategy that never sets
        # `protocol_fee_amount`, so this is a no-op for everything but PM's own trades.
        self.token_balances[trade.token_in] += trade.amount_in - trade.protocol_fee_amount
        self.token_balances[trade.token_out] -= trade.amount_out
        self.protocol_fee_revenue += trade.protocol_fee_amount
        return True

    def step(self, step_index: int) -> None:
        self.reference_prices.update(self.price_process.next(step_index))
        for strategy in self.strategies:
            trade = strategy.decide_trade(self.view())
            if trade is not None:
                self.apply(trade)
        self.metrics.record(self)

    def run(self, n_steps: int) -> None:
        for step_index in range(1, n_steps + 1):
            self.step(step_index)
