// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

/// @dev Registers the weighted-curve instruction. Its protocol fee transfer is part of that instruction.

import {Context} from "swap-vm/libs/VM.sol";
import {Controls} from "swap-vm/instructions/Controls.sol";
import {PortfolioManagerSwap} from "./PortfolioManagerSwap.sol";

/// @dev Never deployed on its own -- only ever inherited by `PortfolioManagerRouter`.
abstract contract PortfolioManagerOpcodes is PortfolioManagerSwap, Controls {
    constructor(address aqua, address strategyValidator) PortfolioManagerSwap(aqua, strategyValidator) {}

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
            _notInstruction, PortfolioManagerSwap._portfolioManagerSwapXD, Controls._onlyTxOriginTokenBalanceNonZero
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
