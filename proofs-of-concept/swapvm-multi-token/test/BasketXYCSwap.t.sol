// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

/// @dev PoC only — see ../src/BasketXYCSwap.sol for what this is answering.

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {AquaRouter} from "aqua/AquaRouter.sol";
import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";
import {MakerTraitsLib} from "swap-vm/libs/MakerTraits.sol";
import {TakerTraitsLib} from "swap-vm/libs/TakerTraits.sol";
import {PoCRouter} from "../src/PoCRouter.sol";
import {BasketXYCSwapArgsBuilder} from "../src/BasketXYCSwap.sol";

contract BasketXYCSwapTest is Test {
    AquaRouter aqua;
    PoCRouter router;
    ERC20Mock tokenA;
    ERC20Mock tokenB;
    ERC20Mock tokenC;

    address owner = address(0xEEEE);
    address taker = address(0xBEEF);

    // _opcodes()'s array-shrinking trick overwrites index 0 with the new length, shifting
    // everything down by one — the second literal element (_basketXycSwapXD) ends up at
    // result[0], not result[1].
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

    /// @dev Ships one maker's strategy with initial A/B/C balances and returns the order
    /// needed to trade against it. tokenC is deliberately never approved to Aqua — it's
    /// read-only for the curve, proving the swap never actually moves it.
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
}
