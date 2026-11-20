// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

/// @dev Registers the weighted-curve instruction. Its protocol fee transfer is part of that instruction.

import {Context} from "swap-vm/libs/VM.sol";
import {Controls} from "swap-vm/instructions/Controls.sol";
import {PortfolioManagerSwap} from "./PortfolioManagerSwap.sol";

/// @dev Never deployed on its own -- only ever inherited by `PortfolioManagerRouter`.
abstract contract PortfolioManagerOpcodes is PortfolioManagerSwap, Controls {
    /// @dev The indices `PortfolioManagerProgramBuilder.sol` and
    ///      `GatedPortfolioManagerProgramBuilder.sol` hardcode into their encoded programs, with
    ///      no compiler-enforced link to `_opcodes()`'s own order below (Solidity has no way to
    ///      share a constant across a library and an abstract contract without inheritance, and
    ///      solc's own docs mark internal-function-pointer comparison unreliable under the
    ///      optimizer). `PortfolioManagerOpcodesLayoutGuard.t.sol` pins opcode byte 0 to the curve
    ///      swap and byte 1 to the KYC gate through the real program-building path instead, so
    ///      reordering or extending `_opcodes()` fails CI immediately.
    uint8 internal constant CURVE_OPCODE = 0;
    uint8 internal constant KYC_GATE_OPCODE = 1;

    constructor(
        address aqua,
        address strategyValidator,
        address sequencerUptimeFeed,
        address tokenRegistry,
        address feedRegistry
    ) PortfolioManagerSwap(aqua, strategyValidator, sequencerUptimeFeed, tokenRegistry, feedRegistry) {}

    function _notInstruction(
        Context memory,
        /* ctx */
        bytes calldata /* args */
    )
        internal {}

    /// @dev Opcode 1 = resolver KYC gate (1inch Aqua access-control -- see
    ///      https://business.1inch.com/portal/documentation/aqua/liquidity-layer/access-resolvers-and-pathfinder),
    ///      checked via `tx.origin` since the resolver, not the taker, is the credentialed party
    ///      and only `tx.origin` identifies the resolver across a multi-hop call. Only referenced
    ///      by `GatedPortfolioManagerProgramBuilder`; inert for `PortfolioManagerProgramBuilder`'s
    ///      ungated programs.
    function _opcodes()
        internal
        pure
        virtual
        returns (function(Context memory, bytes calldata) internal[] memory result)
    {
        function(Context memory, bytes calldata) internal[3] memory instructions = [
            _notInstruction, PortfolioManagerSwap._portfolioManagerSwapXd, Controls._onlyTxOriginTokenBalanceNonZero
        ];

        // Same trick AquaOpcodes.sol uses: rewrite the leading _notInstruction with the array's
        // length, turning a fixed-size literal into a dynamic array with that entry dropped.
        uint256 instructionsArrayLength = instructions.length - 1;
        assembly ("memory-safe") {
            result := instructions
            mstore(result, instructionsArrayLength)
        }
    }
}
