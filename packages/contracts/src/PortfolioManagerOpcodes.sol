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

    /// @dev Opcode 0 = the weighted-curve swap, protocol fee included. Opcode 1 is a resolver
    ///      KYC gate (1inch's Aqua access-control requirement -- see
    ///      https://business.1inch.com/portal/documentation/aqua/liquidity-layer/access-resolvers-and-pathfinder):
    ///      `Controls._onlyTxOriginTokenBalanceNonZero` checks `tx.origin` (not `msg.sender`,
    ///      since 1inch's own docs specify the `tx.origin` variant) holds a configured token.
    ///      Present here so `GatedPortfolioManagerProgramBuilder` can reference it -- whether any
    ///      given strategy's program actually includes it is a per-strategy choice, not a
    ///      per-router one; `PortfolioManagerProgramBuilder`'s own programs never reference opcode
    ///      1, so its presence here is inert for them.
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
