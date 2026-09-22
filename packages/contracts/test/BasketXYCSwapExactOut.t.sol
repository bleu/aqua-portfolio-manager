// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

/// @dev Separate suite to avoid optimizer stack limits. See BasketXYCSwapTestBase.

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";
import {TakerTraitsLib} from "swap-vm/libs/TakerTraits.sol";
import {BasketXYCSwapTestBase} from "./utils/BasketXYCSwapTestBase.sol";

contract BasketXYCSwapExactOutTest is BasketXYCSwapTestBase {
    function _swapExactOut(ISwapVM.Order memory order, uint256 amountOut) internal returns (uint256 amountIn) {
        bytes memory takerData = TakerTraitsLib.build(
            TakerTraitsLib.Args({
                taker: taker,
                isExactIn: false,
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
        (amountIn,,) = router.swap(order, address(tokenA), address(tokenB), amountOut, takerData);
    }

    /// @notice Exact-out mirror of BasketXYCSwap.t.sol's test_priceIncludesBasketTokenBalance —
    /// larger basket-token liquidity must mean a *smaller* required amountIn for the same
    /// amountOut.
    function test_priceIncludesBasketTokenBalance() public {
        ISwapVM.Order memory orderSmallC = _shipMaker(address(0x1111), 1_000e18, 1_000e18, 100e18);
        ISwapVM.Order memory orderLargeC = _shipMaker(address(0x2222), 1_000e18, 1_000e18, 10_000e18);

        uint256 amountOut = 10e18;

        uint256 inSmallC = _swapExactOut(orderSmallC, amountOut);
        uint256 inLargeC = _swapExactOut(orderLargeC, amountOut);

        assertLt(inLargeC, inSmallC, "more basket liquidity should require less amountIn for the same amountOut");
    }

    /// @notice Exact-out mirror of test_tokenCBalanceIsNeverMoved.
    function test_tokenCBalanceIsNeverMoved() public {
        address maker = address(0x3333);
        ISwapVM.Order memory order = _shipMaker(maker, 1_000e18, 1_000e18, 500e18);
        uint256 cBalanceBefore = tokenC.balanceOf(maker);

        _swapExactOut(order, 10e18);

        assertEq(tokenC.balanceOf(maker), cBalanceBefore, "token C must never move");
    }

    /// @notice Exact-out mirror of test_zeroBasketBalanceReducesToPlainXYCSwap.
    function test_zeroBasketBalanceReducesToPlainXYCSwap() public {
        ISwapVM.Order memory order = _shipMaker(address(0x4444), 1_000e18, 1_000e18, 0);
        uint256 amountOut = 10e18;

        uint256 amountIn = _swapExactOut(order, amountOut);

        uint256 expected = Math.ceilDiv(amountOut * 1_000e18, 1_000e18 - amountOut);
        assertEq(amountIn, expected, "zero basket balance must match plain xy=k exact-out");
    }
}
