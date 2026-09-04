// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {FeeArgsBuilder} from "swap-vm/instructions/Fee.sol";
import {PortfolioManagerArgsBuilder} from "./PortfolioManagerArgsBuilder.sol";

/// @title PortfolioManagerProgramBuilder — composes a PM strategy's swap-vm program bytes
/// @notice Production equivalent of swap-vm's own test-only `ProgramBuilder`
///         (`lib/swap-vm/test/utils/ProgramBuilder.sol`) — not reused directly because it
///         lives under `test/`, outside what a `script`/`src` contract can import, and because
///         production callers don't need its runtime function-pointer search:
///         `PortfolioManagerOpcodes`' opcode indices are fixed and known here directly.
/// @dev Wire format matches `VM.sol`'s `runLoop` exactly: repeated
///      `[opcode:1 byte][argsLength:1 byte][args:argsLength bytes]`.
/// @dev BLEUDEV-327: this is the only place the protocol fee (recipient, rate) is decided. The
///      LP's own `tokens`/`weights`/`feeBps` never influence it beyond feeding the tiered
///      formula below, and nothing here is settable through `PortfolioManagerArgsBuilder`'s
///      LP-facing encoding.
library PortfolioManagerProgramBuilder {
    using SafeCast for uint256;

    /// @dev Must match `PortfolioManagerOpcodes._opcodes()`'s dynamic-array indices exactly.
    uint8 internal constant CURVE_OPCODE = 0;
    uint8 internal constant PROTOCOL_FEE_OPCODE = 1;

    /// @dev 1inch DAO Treasury's main wallet, disclosed in 1IP-103 (the governance proposal
    ///      that activated Aqua's protocol fee): the sole recipient of the protocol fee this
    ///      builder composes. Fixed, not LP-settable — see PortfolioManagerSwap.sol's @dev note.
    address internal constant DAO_TREASURY_ADDRESS = 0x7951c7ef839e26F63DA87a42C9a87986507f1c07;

    /// @dev 1IP-103's tier boundary: 0.1225% at `PM_BPS = 1e9` scale (0.001225 * 1e9).
    uint32 internal constant TIER_THRESHOLD_BPS = 1_225_000;

    /// @param tokens, weights, feeBps  The LP's own declared universe and curve fee. `feeBps`
    ///        is passed straight through to `PortfolioManagerArgsBuilder` for curve pricing,
    ///        and separately feeds the protocol-fee formula below — the two uses are
    ///        independent (see PortfolioManagerSwap.sol's @dev note on why the curve is
    ///        unaffected by the protocol fee regardless of what `feeBps` happens to be).
    function build(address[] memory tokens, uint256[] memory weights, uint32 feeBps)
        internal
        pure
        returns (bytes memory program)
    {
        program = bytes.concat(
            _instruction(PROTOCOL_FEE_OPCODE, FeeArgsBuilder.buildProtocolFee(daoFeeBps(feeBps), DAO_TREASURY_ADDRESS)),
            _instruction(CURVE_OPCODE, PortfolioManagerArgsBuilder.build(tokens, weights, feeBps))
        );
    }

    /// @notice 1IP-103's tiered protocol fee: 1/4 of the LP's own `feeBps` at or below the
    ///         tier threshold, 1/6 above it. Not a flat rate — it scales with whatever the LP
    ///         configured, because that's what the proposal actually specifies ("a slice of
    ///         the LP fee on each strategy"), not an independently-set number. `feeBps == 0`
    ///         correctly yields `0`: no LP fee means nothing for the protocol to take a slice
    ///         of, and `_aquaProtocolFeeAmountInXD` already treats a zero rate as a no-op.
    function daoFeeBps(uint32 feeBps) internal pure returns (uint32) {
        return feeBps <= TIER_THRESHOLD_BPS ? feeBps / 4 : feeBps / 6;
    }

    function _instruction(uint8 opcode, bytes memory args) private pure returns (bytes memory) {
        return abi.encodePacked(opcode, args.length.toUint8(), args);
    }
}
