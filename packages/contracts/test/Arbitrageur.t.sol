// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";
import {MakerTraits} from "swap-vm/libs/MakerTraits.sol";

import {Arbitrageur} from "../src/Arbitrageur.sol";
import {IArbitrageur} from "../src/interfaces/IArbitrageur.sol";

/// @notice Access-control checks only -- `onlyOwner` reverts before either function touches
/// `ROUTER` or any real token, so no fork/shipped strategy is needed (see
/// `test/e2e/ArbitrageurFlashE2E.t.sol` for the real-fork behavioral coverage). A dummy router
/// address and an empty order are enough to reach the modifier.
contract ArbitrageurTest is Test {
    Arbitrageur private arbitrageur;
    address private owner;

    function setUp() public {
        owner = makeAddr("owner");
        arbitrageur = new Arbitrageur(makeAddr("router"), makeAddr("poolManager"), owner);
    }

    function test_RevertsWhenFlashArbitrageCalledByNonOwner() public {
        ISwapVM.Order memory order = ISwapVM.Order({maker: address(0), traits: MakerTraits.wrap(0), data: ""});
        IArbitrageur.FlashArbParams memory params = IArbitrageur.FlashArbParams({
            order: order,
            tokenIn: address(0),
            tokenOut: address(0),
            amountIn: 1e18,
            minCurveAmountOut: 0,
            fyndTarget: address(0),
            fyndSpender: address(0),
            fyndCalldata: "",
            deadline: 0
        });

        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        arbitrageur.executeFlashArbitrage(params);
    }

    function test_UnlockCallbackRevertsWhenNotCalledByPoolManager() public {
        vm.expectRevert(
            abi.encodeWithSelector(IArbitrageur.ArbitrageurUnauthorizedFlashLoanCallback.selector, address(this))
        );
        arbitrageur.unlockCallback("");
    }

    function test_SweepRevertsForNonOwner() public {
        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        arbitrageur.sweep(makeAddr("token"), 1e18, stranger);
    }
}
