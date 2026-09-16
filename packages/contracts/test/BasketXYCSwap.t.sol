// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

/// @dev PoC only — see ../src/BasketXYCSwap.sol for what this is answering.

import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";
import {TakerTraitsLib} from "swap-vm/libs/TakerTraits.sol";
import {BasketXYCSwapTestBase} from "./utils/BasketXYCSwapTestBase.sol";

contract BasketXYCSwapTest is BasketXYCSwapTestBase {
    function _swap(ISwapVM.Order memory order, uint256 amountIn) internal returns (uint256 amountOut) {
        bytes memory takerData = TakerTraitsLib.build(
            TakerTraitsLib.Args({
                taker: taker,
                isExactIn: true,
                shouldUnwrapWeth: false,
                isStrictThresholdAmount: false,
                isFirstTransferFromTaker: true,
                useTransferFromAndAquaPush: true,
                threshold: "",
                to: address(0),
                deadline: 0,
                hasPreTransferInCallback: false,
                hasPreTransferOutCallback: false,
                preTransferInHookData: "",
                postTransferInHookData: "",
                preTransferOutHookData: "",
                postTransferOutHookData: "",
                preTransferInCallbackData: "",
                preTransferOutCallbackData: "",
                instructionsArgs: "",
                signature: ""
            })
        );

        vm.prank(taker);
        (, amountOut,) = router.swap(order, address(tokenA), address(tokenB), amountIn, takerData);
    }

    /// @notice Two makers, identical A/B liquidity, different C. Same trade must price
    /// differently, and must match the plain xy=k formula with (B + C) as the effective
    /// balanceOut — proving the curve genuinely reads the basket, not just tokenOut.
    function test_priceIncludesBasketTokenBalance() public {
        ISwapVM.Order memory orderSmallC = _shipMaker(address(0x1111), 1_000e18, 1_000e18, 100e18);
        ISwapVM.Order memory orderLargeC = _shipMaker(address(0x2222), 1_000e18, 1_000e18, 10_000e18);

        uint256 amountIn = 10e18;

        uint256 outSmallC = _swap(orderSmallC, amountIn);
        uint256 outLargeC = _swap(orderLargeC, amountIn);

        assertGt(outLargeC, outSmallC, "basket token C's balance should change the A->B price");

        uint256 expectedSmallC = (amountIn * (1_000e18 + 100e18)) / (1_000e18 + amountIn);
        uint256 expectedLargeC = (amountIn * (1_000e18 + 10_000e18)) / (1_000e18 + amountIn);
        assertEq(outSmallC, expectedSmallC, "small-C price should match the basket xy=k formula");
        assertEq(outLargeC, expectedLargeC, "large-C price should match the basket xy=k formula");
    }

    /// @notice The whole point: C's balance is consulted for pricing but never moved.
    function test_tokenCBalanceIsNeverMoved() public {
        address maker = address(0x3333);
        ISwapVM.Order memory order = _shipMaker(maker, 1_000e18, 1_000e18, 500e18);
        uint256 cBalanceBefore = tokenC.balanceOf(maker);

        _swap(order, 10e18);

        assertEq(tokenC.balanceOf(maker), cBalanceBefore, "token C must never move");
    }

    /// @notice Sanity check against plain XYCSwap's own formula shape: with C's balance at
    /// zero, this curve must reduce to exactly the 2-token xy=k case.
    function test_zeroBasketBalanceReducesToPlainXYCSwap() public {
        ISwapVM.Order memory order = _shipMaker(address(0x4444), 1_000e18, 1_000e18, 0);
        uint256 amountIn = 10e18;

        uint256 amountOut = _swap(order, amountIn);

        uint256 expected = (amountIn * 1_000e18) / (1_000e18 + amountIn);
        assertEq(amountOut, expected, "zero basket balance must match plain xy=k");
    }

    /// @notice Comparison against swap-vm's own plain XYCSwap (opcode 1), which has no notion of
    /// a third token at all -- the basket-aware maker (also holding C) must price better than an
    /// identically-funded plain-XYCSwap maker on the same A/B trade.
    function test_PricesBetterThanPlainXYCSwapWhichCannotSeeTokenC() public {
        address basketMaker = address(0x5555);
        address plainMaker = address(0x6666);
        ISwapVM.Order memory basketOrder = _shipMaker(basketMaker, 1_000e18, 1_000e18, 500e18);
        ISwapVM.Order memory plainOrder = _shipPlainXYCMaker(plainMaker, 1_000e18, 1_000e18);

        uint256 amountIn = 10e18;
        uint256 basketOut = _swap(basketOrder, amountIn);
        uint256 plainOut = _swap(plainOrder, amountIn);

        assertGt(
            basketOut, plainOut, "basket-aware pricing must beat a comparator strategy structurally blind to token C"
        );

        uint256 expectedPlainOut = (amountIn * 1_000e18) / (1_000e18 + amountIn);
        assertEq(plainOut, expectedPlainOut, "plain XYCSwap comparator must match the unmodified xy=k formula");
    }
}
