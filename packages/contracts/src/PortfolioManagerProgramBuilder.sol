// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {FeeArgsBuilder, BPS as FEE_BPS} from "swap-vm/instructions/Fee.sol";
import {PortfolioManagerArgsBuilder} from "./PortfolioManagerArgsBuilder.sol";

/// @title PortfolioManagerProgramBuilder — composes a PM strategy's swap-vm program bytes
/// @notice Production equivalent of swap-vm's own test-only `ProgramBuilder`
///         (`lib/swap-vm/test/utils/ProgramBuilder.sol`) — not reused directly because it
///         lives under `test/`, outside what a `script`/`src` contract can import, and because
///         production callers don't need its runtime function-pointer search:
///         `PortfolioManagerOpcodes`' opcode indices are fixed and known here directly.
/// @dev Wire format matches `VM.sol`'s `runLoop` exactly: repeated
///      `[opcode:1 byte][argsLength:1 byte][args:argsLength bytes]`.
/// @dev BLEUDEV-327: this is the only place the protocol fee (recipients, split, rate) is
///      decided. The LP's own `tokens`/`weights`/`feeBps` never influence it, and nothing here
///      is settable through `PortfolioManagerArgsBuilder`'s LP-facing encoding.
library PortfolioManagerProgramBuilder {
    using SafeCast for uint256;

    /// @dev Must match `PortfolioManagerOpcodes._opcodes()`'s dynamic-array indices exactly.
    uint8 internal constant CURVE_OPCODE = 0;
    uint8 internal constant PROTOCOL_FEE_OPCODE = 1;

    /// @dev 1 bps at Fee.sol's own BPS scale (1e9 = 100%) — BLEUDEV-327's fixed protocol fee,
    ///      split evenly between 1inch DAO and Bleu (the PM owner).
    uint32 internal constant DAO_FEE_BPS = 1e5;

    error PortfolioManagerProgramBuilderZeroRecipient();

    /// @param tokens, weights, feeBps  The LP's own declared universe and curve fee — passed
    ///        straight through to `PortfolioManagerArgsBuilder`, unrelated to the protocol fee.
    /// @param daoAddress, bleuAddress  Protocol-fee recipients. Zero for either reverts here,
    ///        at build time, not silently at swap time.
    function build(
        address[] memory tokens,
        uint256[] memory weights,
        uint32 feeBps,
        address daoAddress,
        address bleuAddress
    ) internal pure returns (bytes memory program) {
        require(daoAddress != address(0) && bleuAddress != address(0), PortfolioManagerProgramBuilderZeroRecipient());

        // Chained *before* the curve opcode, DAO composed first: each _aquaProtocolFeeAmountInXD
        // call wraps the rest of the program (shrinks amountIn, recurses into ctx.runLoop(),
        // *then* pulls once that returns), so the curve only ever sees amountIn net of both
        // pulls — but that wrapping also means DAO's own pull runs LAST in real execution, after
        // Bleu's nested call already ran and pulled first (confirmed in
        // PortfolioManagerOpcodes.t.sol). This doesn't change the amounts (each instruction's
        // fee is still computed off the amountIn live when *it* runs, matching program order,
        // not pull order) or the independence of the two pulls, but it does mean "composed
        // first" and "collected first" are different things here — worth knowing before reading
        // a trace. (see PortfolioManagerSwap.sol's @dev note; BLEUDEV-327's "why no proof changes are
        // needed"). bleuFeeBps is solved so the two pulled amounts land exactly equal despite
        // the chain's multiplicative composition (Bleu's bps applies to the amount already net
        // of DAO's cut, not the taker's original amountIn):
        //   daoAmount    = A_i * DAO_FEE_BPS / BPS
        //   ownerAmount  = (A_i - daoAmount) * bleuFeeBps / BPS
        // Solving daoAmount == ownerAmount for bleuFeeBps gives the line below.
        uint32 bleuFeeBps = uint32(uint256(DAO_FEE_BPS) * FEE_BPS / (FEE_BPS - DAO_FEE_BPS));

        program = bytes.concat(
            _instruction(PROTOCOL_FEE_OPCODE, FeeArgsBuilder.buildProtocolFee(DAO_FEE_BPS, daoAddress)),
            _instruction(PROTOCOL_FEE_OPCODE, FeeArgsBuilder.buildProtocolFee(bleuFeeBps, bleuAddress)),
            _instruction(CURVE_OPCODE, PortfolioManagerArgsBuilder.build(tokens, weights, feeBps))
        );
    }

    function _instruction(uint8 opcode, bytes memory args) private pure returns (bytes memory) {
        return abi.encodePacked(opcode, args.length.toUint8(), args);
    }
}
