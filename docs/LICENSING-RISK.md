# Licensing risk

Repository assessment recorded on 2026-08-11. Counsel has not reviewed it.
The shipped [license texts](../LICENSES/) control the terms.

## Source obligations

Aqua and SwapVM use custom Degensoft licenses.
Section 3 of Aqua-Source-1.1 requires modifications to use the same license, with attribution, marked changes, and reproducible build instructions.
Its definition of modification includes linking and instruction sets in the same virtual machine.

Our router inherits SwapVM, which compiles licensed source into the deployed bytecode.
The repository therefore uses Aqua-Source-1.1 under [ADR-0001](adr/0001-license-under-aqua-source-not-mit.md).
The grant's original MIT wording needs correction.

## Commercial thresholds

Section 5.2 requires a Commercial License when either threshold is exceeded:

- Charged Fees above US$100,000 in a rolling 12-month period.
- Liquidity Under Control above US$10,000,000 at any time.

The grant's recorded six-month base case is US$30 million under management, above the liquidity threshold.

Section 5.3 waives enforcement for specified Volume Activities.
This strategy may qualify, but the waiver is not a license and creates no reliance rights.
Degensoft can revoke it and require compliance or cessation within ten days of notice.

## Follow-up

1. Obtain counsel review of the source obligations and waiver applicability.
2. Correct the grant's license description.
3. Record waiver revocation as a project risk.
4. Discuss commercial licensing with the project contact and budget for negotiation if required.

[Third-party notices](../THIRD_PARTY_NOTICES.md) records dependency licenses.
