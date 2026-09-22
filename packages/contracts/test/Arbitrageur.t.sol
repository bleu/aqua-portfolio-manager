// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";
import {MakerTraits} from "swap-vm/libs/MakerTraits.sol";

import {Arbitrageur} from "../src/Arbitrageur.sol";

/// @notice Access-control checks only -- `onlyOwner` reverts before either function touches
/// `ROUTER` or any real token, so no fork/shipped strategy is needed (see
/// `test/e2e/ArbitrageurE2E.t.sol` for the real-fork behavioral coverage). A dummy router
/// address and an empty order are enough to reach the modifier.
contract ArbitrageurTest is Test {
    Arbitrageur private arbitrageur;
    address private owner;

    function setUp() public {
        owner = makeAddr("owner");
        arbitrageur = new Arbitrageur(makeAddr("router"), makeAddr("balancerVault"), owner);
    }

    function test_RevertsWhenCalledByNonOwner() public {
        ISwapVM.Order memory order = ISwapVM.Order({maker: address(0), traits: MakerTraits.wrap(0), data: ""});

        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        arbitrageur.executeArbitrage(order, address(0), address(0), 1e18, 0, 0);
    }

    function test_RevertsWhenFlashArbitrageCalledByNonOwner() public {
        ISwapVM.Order memory order = ISwapVM.Order({maker: address(0), traits: MakerTraits.wrap(0), data: ""});
        Arbitrageur.FlashArbParams memory params = Arbitrageur.FlashArbParams({
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

    function test_ReceiveFlashLoanRevertsWhenNotCalledByVault() public {
        IERC20[] memory tokens = new IERC20[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory feeAmounts = new uint256[](1);

        vm.expectRevert(
            abi.encodeWithSelector(Arbitrageur.ArbitrageurUnauthorizedFlashLoanCallback.selector, address(this))
        );
        arbitrageur.receiveFlashLoan(tokens, amounts, feeAmounts, "");
    }

    function test_SweepRevertsForNonOwner() public {
        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        arbitrageur.sweep(makeAddr("token"), 1e18, stranger);
    }
}
