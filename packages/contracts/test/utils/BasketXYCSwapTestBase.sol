// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

/// @dev PoC only — see ../../src/BasketXYCSwap.sol for what this is answering.

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {AquaRouter} from "aqua/AquaRouter.sol";
import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";
import {MakerTraitsLib} from "swap-vm/libs/MakerTraits.sol";
import {PoCRouter} from "../../src/PoCRouter.sol";
import {BasketXYCSwapArgsBuilder} from "../../src/BasketXYCSwap.sol";

/// @dev Shared setup for separate exact-in and exact-out suites.
///      Combining them triggers a via-IR optimizer stack limit in _shipMaker.
abstract contract BasketXYCSwapTestBase is Test {
    AquaRouter aqua;
    PoCRouter router;
    ERC20Mock tokenA;
    ERC20Mock tokenB;
    ERC20Mock tokenC;

    address owner = address(0xEEEE);
    address taker = address(0xBEEF);

    // The placeholder slot becomes the array length, so curve opcodes start at zero.
    uint8 constant OPCODE_BASKET_XYC_SWAP = 0;
    uint8 constant OPCODE_PLAIN_XYC_SWAP = 1;

    function setUp() public virtual {
        aqua = new AquaRouter(owner);
        tokenA = new ERC20Mock();
        tokenB = new ERC20Mock();
        tokenC = new ERC20Mock();
        router = new PoCRouter(address(aqua), address(0x1), owner, "PoC", "1");

        tokenA.mint(taker, 1_000_000e18);
        vm.prank(taker);
        tokenA.approve(address(router), type(uint256).max);
    }

    /// @dev Ship A/B/C balances without approving tokenC, to verify that swaps only read it.
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

    /// @dev Ship the independent XYCSwap baseline with only A/B balances.
    function _shipPlainXYCMaker(address maker, uint256 initA, uint256 initB)
        internal
        returns (ISwapVM.Order memory order)
    {
        tokenB.mint(maker, initB);
        vm.prank(maker);
        tokenB.approve(address(aqua), type(uint256).max);

        bytes memory program = abi.encodePacked(OPCODE_PLAIN_XYC_SWAP, uint8(0));

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

        address[] memory tokens = new address[](2);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = initA;
        amounts[1] = initB;

        vm.prank(maker);
        bytes32 shippedHash = aqua.ship(address(router), abi.encode(order), tokens, amounts);
        assertEq(shippedHash, orderHash, "strategyHash must equal SwapVM's own orderHash");
    }
}
