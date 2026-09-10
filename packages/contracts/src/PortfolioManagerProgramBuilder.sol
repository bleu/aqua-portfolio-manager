// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {PortfolioManagerArgsBuilder} from "./PortfolioManagerArgsBuilder.sol";

/// @title PortfolioManagerProgramBuilder — composes a PM strategy's swap-vm program bytes
/// @notice Production equivalent of swap-vm's own test-only `ProgramBuilder`
///         (`lib/swap-vm/test/utils/ProgramBuilder.sol`) — not reused directly because it
///         lives under `test/`, outside what a `script`/`src` contract can import, and because
///         production callers don't need its runtime function-pointer search:
///         `PortfolioManagerOpcodes`' opcode index is fixed and known here directly.
/// @dev Wire format matches `VM.sol`'s `runLoop` exactly: `[opcode:1 byte][argsLength:1
///      byte][args:argsLength bytes]`.
/// @dev The protocol fee itself is *not* composed here — it's baked directly into
///      `PortfolioManagerSwap`'s own execution so it can't be omitted by a hand-crafted program
///      that skips this builder entirely. This library still owns the tiered-rate formula and
///      the DAO Treasury address, since `PortfolioManagerSwap` needs the same constants and a
///      single source of truth is worth a one-directional import from opcode back to builder.
library PortfolioManagerProgramBuilder {
    using SafeCast for uint256;

    /// @dev Must match `PortfolioManagerOpcodes._opcodes()`'s dynamic-array index exactly.
    uint8 internal constant CURVE_OPCODE = 0;

    /// @dev 1inch DAO Treasury's main wallet, disclosed in 1IP-103 (the governance proposal
    ///      that activated Aqua's protocol fee): the sole recipient of the protocol fee.
    address internal constant DAO_TREASURY_ADDRESS = 0x7951c7ef839e26F63DA87a42C9a87986507f1c07;

    /// @dev 1IP-103's tier boundary: "≈0.1225%" (the proposal's own hedge, quoted as "the
    ///      geometric midpoint of 0.05% and 0.30%") at `PM_BPS = 1e9` scale.
    uint32 internal constant TIER_THRESHOLD_BPS = 1_225_000;

    /// @param tokens, weights, feeBps  The LP's own declared universe and curve fee.
    function build(address[] memory tokens, uint256[] memory weights, uint32 feeBps)
        internal
        pure
        returns (bytes memory program)
    {
        bytes memory args = PortfolioManagerArgsBuilder.build(tokens, weights, feeBps);
        program = abi.encodePacked(CURVE_OPCODE, args.length.toUint8(), args);
    }

    /// @notice 1IP-103's tiered protocol fee: 1/4 of the LP's own `feeBps` at or below the
    ///         tier threshold, 1/6 above it. Not a flat rate — it scales with whatever the LP
    ///         configured, because that's what the proposal actually specifies ("a slice of
    ///         the LP fee on each strategy"), not an independently-set number. `feeBps == 0`
    ///         correctly yields `0`.
    function daoFeeBps(uint32 feeBps) internal pure returns (uint32) {
        return feeBps <= TIER_THRESHOLD_BPS ? feeBps / 4 : feeBps / 6;
    }
}
