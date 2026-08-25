// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

/// @dev PoC only — see BasketXYCSwap.sol. Mirrors AquaSwapVMRouter.sol exactly, swapping in
/// PoCOpcodes instead of 1inch's real AquaOpcodes.

import {Context} from "swap-vm/libs/VM.sol";
import {Simulator} from "@1inch/solidity-utils/contracts/mixins/Simulator.sol";
import {SwapVM} from "swap-vm/SwapVM.sol";
import {PoCOpcodes} from "./PoCOpcodes.sol";

contract PoCRouter is Simulator, SwapVM, PoCOpcodes {
    constructor(address aqua, address weth, address owner, string memory name, string memory version)
        SwapVM(aqua, weth, owner, name, version)
        PoCOpcodes(aqua)
    {}

    function _instructions()
        internal
        pure
        override
        returns (function(Context memory, bytes calldata) internal[] memory result)
    {
        return _opcodes();
    }
}
