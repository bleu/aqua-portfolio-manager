// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

/// @dev Prototype opcode table: basket-aware xy=k and the standard XYCSwap comparison baseline.

import {Context} from "swap-vm/libs/VM.sol";
import {XYCSwap} from "swap-vm/instructions/XYCSwap.sol";
import {BasketXYCSwap} from "./BasketXYCSwap.sol";

contract PoCOpcodes is BasketXYCSwap, XYCSwap {
    constructor(address aqua) BasketXYCSwap(aqua) {}

    function _notInstruction(
        Context memory,
        /* ctx */
        bytes calldata /* args */
    )
        internal {}

    function _opcodes()
        internal
        pure
        virtual
        returns (function(Context memory, bytes calldata) internal[] memory result)
    {
        function(Context memory, bytes calldata) internal[3] memory instructions =
            [_notInstruction, BasketXYCSwap._basketXycSwapXD, XYCSwap._xycSwapXD];

        // Reuse the placeholder slot as the dynamic array length, matching AquaOpcodes.
        // The basket curve becomes opcode 0 and XYCSwap becomes opcode 1.
        uint256 instructionsArrayLength = instructions.length - 1;
        assembly ("memory-safe") {
            result := instructions
            mstore(result, instructionsArrayLength)
        }
    }
}
