// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

/// @dev PoC only — see ../src/BasketXYCSwap.sol for what this is answering.
///
/// Kept as its own contract/file rather than folded into BasketXYCSwap.t.sol: adding these
/// exact-out tests there tripped via-ir's optimizer into a "stack too deep" error inside the
/// unrelated, pre-existing `_shipMaker` helper (more call sites through the same helper shifts
/// its inlined stack allocation). A separate compilation unit sidesteps that entirely rather
/// than fighting the optimizer (BLEUDEV-345).

import {Test} from "forge-std/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {AquaRouter} from "aqua/AquaRouter.sol";
import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";
import {MakerTraitsLib} from "swap-vm/libs/MakerTraits.sol";
import {TakerTraitsLib} from "swap-vm/libs/TakerTraits.sol";
import {PoCRouter} from "../src/PoCRouter.sol";
import {BasketXYCSwapArgsBuilder} from "../src/BasketXYCSwap.sol";

contract BasketXYCSwapExactOutTest is Test {
    AquaRouter aqua;
    PoCRouter router;
    ERC20Mock tokenA;
    ERC20Mock tokenB;
    ERC20Mock tokenC;

    address owner = address(0xEEEE);
    address taker = address(0xBEEF);

    // Same array-shrinking quirk as BasketXYCSwap.t.sol — see that file's comment.
    uint8 constant OPCODE_BASKET_XYC_SWAP = 0;

    function setUp() public {
        aqua = new AquaRouter(owner);
        tokenA = new ERC20Mock();
        tokenB = new ERC20Mock();
        tokenC = new ERC20Mock();
        router = new PoCRouter(address(aqua), address(0x1), owner, "PoC", "1");

        tokenA.mint(taker, 1_000_000e18);
        vm.prank(taker);
        tokenA.approve(address(router), type(uint256).max);
    }

    /// @dev Same shape as BasketXYCSwap.t.sol's `_shipMaker`.
    function _shipMaker(address maker, uint256 initA, uint256 initB, uint256 initC)
        internal
        returns (ISwapVM.Order memory order)
    {
        tokenB.mint(maker, initB);
        tokenC.mint(maker, initC);
        vm.prank(maker);
        tokenB.approve(address(aqua), type(uint256).max);

        bytes memory args = BasketXYCSwapArgsBuilder.build(address(tokenC));
        bytes memory program = abi.encodePacked(OPCODE_BASKET_XYC_SWAP, uint8(args.length), args);

        order = MakerTraitsLib.build(
            MakerTraitsLib.Args({
                maker: maker,
                receiver: address(0),
                shouldUnwrapWeth: false,
                useAquaInsteadOfSignature: true,
                allowZeroAmountIn: false,
                hasPreTransferInHook: false,
                hasPostTransferInHook: false,
                hasPreTransferOutHook: false,
                hasPostTransferOutHook: false,
                preTransferInTarget: address(0),
                preTransferInData: "",
                postTransferInTarget: address(0),
                postTransferInData: "",
                preTransferOutTarget: address(0),
                preTransferOutData: "",
                postTransferOutTarget: address(0),
                postTransferOutData: "",
                program: program
            })
        );

        bytes32 orderHash = keccak256(abi.encode(order));

        address[] memory tokens = new address[](3);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);
        tokens[2] = address(tokenC);
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = initA;
        amounts[1] = initB;
        amounts[2] = initC;

        vm.prank(maker);
        bytes32 shippedHash = aqua.ship(address(router), abi.encode(order), tokens, amounts);
        assertEq(shippedHash, orderHash, "strategyHash must equal SwapVM's own orderHash");
    }

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
    /// amountOut, and must match the exact-out formula's ceilDiv shape (BasketXYCSwap.sol's
    /// `else` branch, previously untested).
    function test_priceIncludesBasketTokenBalance() public {
        ISwapVM.Order memory orderSmallC = _shipMaker(address(0x1111), 1_000e18, 1_000e18, 100e18);
        ISwapVM.Order memory orderLargeC = _shipMaker(address(0x2222), 1_000e18, 1_000e18, 10_000e18);

        uint256 amountOut = 10e18;

        uint256 inSmallC = _swapExactOut(orderSmallC, amountOut);
        uint256 inLargeC = _swapExactOut(orderLargeC, amountOut);

        assertLt(inLargeC, inSmallC, "more basket liquidity should require less amountIn for the same amountOut");

        uint256 expectedSmallC = Math.ceilDiv(amountOut * 1_000e18, (1_000e18 + 100e18) - amountOut);
        uint256 expectedLargeC = Math.ceilDiv(amountOut * 1_000e18, (1_000e18 + 10_000e18) - amountOut);
        assertEq(inSmallC, expectedSmallC, "small-C amountIn should match the basket exact-out formula");
        assertEq(inLargeC, expectedLargeC, "large-C amountIn should match the basket exact-out formula");
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
