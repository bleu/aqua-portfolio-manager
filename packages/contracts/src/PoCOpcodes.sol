// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

/// @dev PoC only — see BasketXYCSwap.sol. Mirrors AquaOpcodes.sol's pattern, with two
/// instructions registered instead of 1inch's real opcode set: our own basket-aware curve, and
/// swap-vm's plain XYCSwap as a real (not hypothetical) comparison baseline that prices
/// tokenA/tokenB identically but has no notion of a third basket token at all.

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

        // Same trick AquaOpcodes.sol uses: rewrite the fixed-size array's length in place to
        // drop the leading _notInstruction placeholder before returning it as dynamic --
        // BasketXYCSwap ends up at result[0] (opcode 0), plain XYCSwap at result[1] (opcode 1).
        uint256 instructionsArrayLength = instructions.length - 1;
        assembly ("memory-safe") {
            result := instructions
            mstore(result, instructionsArrayLength)
        }
    }
}
