"""aqua_sim — economic simulation library for the Aqua Portfolio Manager.

Floating-point reimplementation of the strategy's math for fast, iterable market
simulation (Monte Carlo sweeps, parameter search). The real spec is Solidity,
fixed-point, with rounding that always favors the pool (see ../../docs/PRICING.md,
../../docs/INVARIANT-PROOF.md).
"""
