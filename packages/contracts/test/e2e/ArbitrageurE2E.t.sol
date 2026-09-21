// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";

import {PortfolioManagerE2EBase} from "./base/PortfolioManagerE2EBase.t.sol";
import {Arbitrageur} from "../../src/Arbitrageur.sol";

/// @notice Real-fork proof that `Arbitrageur` genuinely works as an ordinary EOA-driven taker
/// against a real, shipped PM strategy -- not just that it compiles against `ISwapVM`'s
/// interface. `arbitrageurOwner` is a plain address (`vm.addr`, not a contract), exercising the
/// exact property the contract exists for: no `ITakerCallbacks` implementation anywhere in this
/// test. Access-control reverts are covered separately in `test/Arbitrageur.t.sol` (no fork
/// needed there).
contract ArbitrageurE2ETest is PortfolioManagerE2EBase {
    uint256 private constant OWNER_KEY = 0xA12BEE;
    address private arbitrageurOwner;
    Arbitrageur private arbitrageur;

    function setUp() public override {
        super.setUp();
        arbitrageurOwner = vm.addr(OWNER_KEY);
        arbitrageur = new Arbitrageur(address(router), arbitrageurOwner);
    }

    function test_QuoteThenExecuteMatchExactly() public {
        ISwapVM.Order memory order = _buildOrder(LOW_TIER_FEE_BPS);
        _fundAndShip(order, INITIAL_BALANCE);

        uint256 amountIn = 1e18; // 1 WETH
        deal(address(pmTokenA), arbitrageurOwner, amountIn);
        vm.prank(arbitrageurOwner);
        pmTokenA.approve(address(arbitrageur), amountIn);

        uint256 quotedOut = arbitrageur.quoteExactIn(order, address(pmTokenA), address(pmTokenB), amountIn);
        assertGt(quotedOut, 0, "quote must be non-zero for a funded, shipped strategy");

        vm.prank(arbitrageurOwner);
        uint256 amountOut = arbitrageur.executeArbitrage(
            order, address(pmTokenA), address(pmTokenB), amountIn, quotedOut, uint40(block.timestamp + 60)
        );

        assertEq(amountOut, quotedOut, "executed amountOut must match the earlier quote exactly");
        assertEq(pmTokenB.balanceOf(arbitrageurOwner), amountOut, "tokenOut must land directly on the owner");
        assertEq(pmTokenA.balanceOf(arbitrageurOwner), 0, "tokenIn must be fully pulled from the owner");
        assertEq(pmTokenA.balanceOf(address(arbitrageur)), 0, "contract must not retain tokenIn between calls");
    }

    function test_RevertsWhenSlippageFloorNotMet() public {
        ISwapVM.Order memory order = _buildOrder(LOW_TIER_FEE_BPS);
        _fundAndShip(order, INITIAL_BALANCE);

        uint256 amountIn = 1e18;
        deal(address(pmTokenA), arbitrageurOwner, amountIn);
        vm.prank(arbitrageurOwner);
        pmTokenA.approve(address(arbitrageur), amountIn);

        uint256 quotedOut = arbitrageur.quoteExactIn(order, address(pmTokenA), address(pmTokenB), amountIn);

        vm.prank(arbitrageurOwner);
        vm.expectRevert();
        arbitrageur.executeArbitrage(
            order, address(pmTokenA), address(pmTokenB), amountIn, quotedOut + 1, uint40(block.timestamp + 60)
        );
    }

    function test_RevertsAfterDeadline() public {
        ISwapVM.Order memory order = _buildOrder(LOW_TIER_FEE_BPS);
        _fundAndShip(order, INITIAL_BALANCE);

        uint256 amountIn = 1e18;
        deal(address(pmTokenA), arbitrageurOwner, amountIn);
        vm.prank(arbitrageurOwner);
        pmTokenA.approve(address(arbitrageur), amountIn);

        vm.warp(block.timestamp + 1000);
        vm.prank(arbitrageurOwner);
        vm.expectRevert();
        arbitrageur.executeArbitrage(
            order, address(pmTokenA), address(pmTokenB), amountIn, 0, uint40(block.timestamp - 1)
        );
    }

    function test_OwnerCanSweepStrandedTokens() public {
        deal(address(pmTokenA), address(arbitrageur), 5e18);

        vm.prank(arbitrageurOwner);
        arbitrageur.sweep(address(pmTokenA), 5e18, arbitrageurOwner);

        assertEq(pmTokenA.balanceOf(arbitrageurOwner), 5e18);
        assertEq(pmTokenA.balanceOf(address(arbitrageur)), 0);
    }
}
