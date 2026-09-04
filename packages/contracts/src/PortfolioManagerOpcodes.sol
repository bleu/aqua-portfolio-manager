// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

/// @dev Real opcode table, successor to PoCOpcodes.sol. Mirrors AquaOpcodes.sol's pattern:
/// registers our own curve instruction alongside swap-vm's `Fee` mixin, reused unmodified
/// (BLEUDEV-327) rather than reimplemented, so the protocol-fee pull's best-effort
/// try/catch/skip-event behavior is exactly the audited one 1inch's own router relies on.

import {Context} from "swap-vm/libs/VM.sol";
import {Fee} from "swap-vm/instructions/Fee.sol";
import {PortfolioManagerSwap} from "./PortfolioManagerSwap.sol";

contract PortfolioManagerOpcodes is PortfolioManagerSwap, Fee {
    constructor(address aqua) Fee(aqua) {}

    function _notInstruction(
        Context memory,
        /* ctx */
        bytes calldata /* args */
    )
        internal {}

    /// @dev Opcode 0 = the weighted-curve swap; opcode 1 = the protocol-fee pull, called twice
    /// (once per recipient) by PortfolioManagerProgramBuilder when composing a strategy's
    /// program bytes, chained *before* opcode 0 so the curve never sees the protocol's cut
    /// (see PortfolioManagerSwap.sol's @dev note, and BLEUDEV-327 for the full derivation).
    function _opcodes()
        internal
        pure
        virtual
        returns (function(Context memory, bytes calldata) internal[] memory result)
    {
        function(Context memory, bytes calldata) internal[3] memory instructions =
            [_notInstruction, PortfolioManagerSwap._portfolioManagerSwapXD, Fee._aquaProtocolFeeAmountInXD];

        // Same trick AquaOpcodes.sol uses: rewrite the leading _notInstruction with the array's
        // length, turning a fixed-size literal into a dynamic array with that entry dropped.
        uint256 instructionsArrayLength = instructions.length - 1;
        assembly ("memory-safe") {
            result := instructions
            mstore(result, instructionsArrayLength)
        }
    }
}
