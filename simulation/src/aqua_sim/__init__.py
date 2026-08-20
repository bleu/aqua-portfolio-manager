"""aqua_sim — economic simulation library for the Aqua Portfolio Manager.

Not the on-chain source of truth. This package reimplements the strategy's math in
floating point for fast, iterable market simulation (Monte Carlo sweeps, parameter
search) — the real spec is Solidity, fixed-point, with rounding that always favors the
pool (see ../../docs/PRICING.md, ../../docs/INVARIANT-PROOF.md). Never treat this
package as authoritative for on-chain behavior.
"""
