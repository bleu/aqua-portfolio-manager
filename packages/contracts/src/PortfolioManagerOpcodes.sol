// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

/// @dev Real opcode table, successor to PoCOpcodes.sol. Mirrors PoCOpcodes.sol's minimal shape:
/// a single real instruction (the weighted-curve swap). The protocol fee is not a separate
/// opcode entry — it's baked directly into PortfolioManagerSwap's own execution, so it can't be
/// omitted by a hand-crafted program that never uses our own program-builder.

import {Context} from "swap-vm/libs/VM.sol";
import {PortfolioManagerSwap} from "./PortfolioManagerSwap.sol";

contract PortfolioManagerOpcodes is PortfolioManagerSwap {
    constructor(address aqua, address strategyFactory) PortfolioManagerSwap(aqua, strategyFactory) {}

    function _notInstruction(
        Context memory,
        /* ctx */
        bytes calldata /* args */
    )
        internal {}

    /// @dev Opcode 0 = the weighted-curve swap, protocol fee included.
    function _opcodes()
        internal
        pure
        virtual
        returns (function(Context memory, bytes calldata) internal[] memory result)
    {
        function(Context memory, bytes calldata) internal[2] memory instructions =
            [_notInstruction, PortfolioManagerSwap._portfolioManagerSwapXD];

        // Same trick AquaOpcodes.sol uses: rewrite the leading _notInstruction with the array's
        // length, turning a fixed-size literal into a dynamic array with that entry dropped.
        uint256 instructionsArrayLength = instructions.length - 1;
        assembly ("memory-safe") {
            result := instructions
            mstore(result, instructionsArrayLength)
        }
    }
}
