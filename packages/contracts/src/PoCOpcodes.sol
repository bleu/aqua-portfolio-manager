// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

/// @dev PoC only — see BasketXYCSwap.sol. Mirrors AquaOpcodes.sol's pattern exactly, with a
/// single instruction registered instead of 1inch's real opcode set.

import {Context} from "swap-vm/libs/VM.sol";
import {BasketXYCSwap} from "./BasketXYCSwap.sol";

contract PoCOpcodes is BasketXYCSwap {
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
        function(Context memory, bytes calldata) internal[2] memory instructions =
            [_notInstruction, BasketXYCSwap._basketXycSwapXD];

        // Same trick AquaOpcodes.sol uses: rewrite the fixed-size array's length in place to
        // drop the trailing _notInstruction placeholder before returning it as dynamic.
        uint256 instructionsArrayLength = instructions.length - 1;
        assembly ("memory-safe") {
            result := instructions
            mstore(result, instructionsArrayLength)
        }
    }
}
