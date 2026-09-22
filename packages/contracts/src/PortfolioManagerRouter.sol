// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

/// @dev Real router, successor to PoCRouter.sol. Mirrors AquaSwapVMRouter.sol exactly, swapping
/// in PortfolioManagerOpcodes instead of 1inch's real AquaOpcodes.

import {Context} from "swap-vm/libs/VM.sol";
import {Simulator} from "@1inch/solidity-utils/contracts/mixins/Simulator.sol";
import {SwapVM} from "swap-vm/SwapVM.sol";
import {PortfolioManagerOpcodes} from "./PortfolioManagerOpcodes.sol";

contract PortfolioManagerRouter is Simulator, SwapVM, PortfolioManagerOpcodes {
    constructor(
        address aqua,
        address weth,
        address owner,
        string memory name,
        string memory version,
        address strategyValidator
    ) SwapVM(aqua, weth, owner, name, version) PortfolioManagerOpcodes(aqua, strategyValidator) {}

    function _instructions()
        internal
        pure
        override
        returns (function(Context memory, bytes calldata) internal[] memory result)
    {
        return _opcodes();
    }
}
