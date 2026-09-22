"""Shared wallet simulation with group valuation, trade validation, and sequential strategy execution."""

from __future__ import annotations

from dataclasses import dataclass, field

from aqua_sim.price_process import PriceProcess
from aqua_sim.strategy import Strategy, Trade


@dataclass(frozen=True)
class BasketGroup:
    """A declared group of one or more tokens, valued in the common quote currency."""

    group_id: str
    token_ids: tuple[str, ...]

    def contains(self, token_id: str) -> bool:
        return token_id in self.token_ids

    def virtual_balance(self, world: "BasketWorldView") -> float:
        """Return the sum of each member balance multiplied by its reference price."""
        return sum(world.token_balances[t] * world.reference_prices[t] for t in self.token_ids)


class UnknownTokenError(ValueError):
    """A trade references a token outside the simulated wallet."""


@dataclass(frozen=True)
class GroupBoundaryGuard:
    """Model group restrictions while PM is registered.

    PM and also_exempt_ids may cross groups. Other strategies must stay within one group.
    With pm_present=False, all trades pass this check.
    This model checks trades, whereas the Solidity Guard inspects direct shipping calls."""

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
    """Snapshot of balances and prices for strategy decisions. Strategies must not mutate the supplied data."""

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
    """Record group values, tracking error, and value captured by each strategy.

    Does not measure rebalancing cost against a frictionless reference.
    That benchmark needs a separate definition when other strategies also change balances."""

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
    """Manage shared reserves, strategies, prices, and metrics.

    Strategies run in registration order and see earlier trades from the same step."""

    token_balances: dict[str, float]
    groups: list[BasketGroup]
    strategies: list[Strategy]
    guard: GroupBoundaryGuard
    price_process: PriceProcess
    metrics: MetricsRecorder
    reference_prices: dict[str, float] = field(default_factory=dict)
    blocked_trades: list[Trade] = field(default_factory=list)
    strategy_captured_value: dict[str, float] = field(default_factory=dict)

    def view(self) -> BasketWorldView:
        return BasketWorldView(
            token_balances=dict(self.token_balances),
            reference_prices=dict(self.reference_prices),
            groups=self.groups,
        )

    def apply(self, trade: Trade) -> bool:
        """Apply a trade if group restrictions and output liquidity permit it.

        Return False for blocked trades or insufficient output liquidity.
        Record guard rejections in blocked_trades.
        strategy_captured_value records the negative of the pool's marked value change.
        It is a reporting ledger, not a second reserve balance."""
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

        self.token_balances[trade.token_in] += trade.amount_in
        self.token_balances[trade.token_out] -= trade.amount_out
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
