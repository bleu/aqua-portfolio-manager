# ADR-0001: Use Aqua-Source-1.1

**Status:** Accepted. Revised 2026-08-25 for the independent SwapVM router.

## Context

The router inherits SwapVM, so licensed source becomes part of its bytecode.
The repository treats this as a modification under Degensoft's license rather than an independent external caller.
The original grant wording described the code as MIT.

## Decision

Use Aqua-Source-1.1 for the repository's own code.
Keep the full license in [LICENSE](../../LICENSE) and dependency details in [third-party notices](../../THIRD_PARTY_NOTICES.md).

## Consequences

- Preserve attribution, marked changes, and reproducible build instructions required by the license.
- Keep Balancer's GPL source as reference material only. Do not import it into the contracts.
- Correct the grant's MIT wording.
- Handle commercial licensing separately, including its thresholds and the waiver that Degensoft can revoke. See [licensing risk](../LICENSING-RISK.md), which still requires review by a lawyer.
