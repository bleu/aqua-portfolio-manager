// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";
import {MakerTraits, MakerTraitsLib} from "swap-vm/libs/MakerTraits.sol";
import {PortfolioManagerArgsCodec} from "../src/utils/PortfolioManagerArgsCodec.sol";
import {PortfolioManagerProgramBuilder} from "../src/utils/PortfolioManagerProgramBuilder.sol";

/// @dev Prints real Solidity output as a golden vector for the hand-ported TS encoder in
///      apps/web/src/lib/portfolioManagerEncoding.ts (no JS/TS SDK exists for this codec or for
///      the vendored swap-vm package). Run with `forge test --match-contract
///      PortfolioManagerEncodingGoldenVectorsTest -vv` and copy the logged hex into
///      apps/web/src/lib/portfolioManagerEncoding.test.ts if this file's inputs or the Solidity
///      encoding ever change.
contract PortfolioManagerEncodingGoldenVectorsTest is Test {
    function test_PrintGoldenVector() public pure {
        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](2);

        PortfolioManagerArgsCodec.Member[] memory m0 = new PortfolioManagerArgsCodec.Member[](2);
        m0[0] = PortfolioManagerArgsCodec.Member({tokenIndex: 5, feedIndex: 7});
        m0[1] = PortfolioManagerArgsCodec.Member({tokenIndex: 9, feedIndex: 0});
        groups[0] = PortfolioManagerArgsCodec.Group({weight: 0.6e18, members: m0});

        PortfolioManagerArgsCodec.Member[] memory m1 = new PortfolioManagerArgsCodec.Member[](1);
        m1[0] = PortfolioManagerArgsCodec.Member({tokenIndex: 12, feedIndex: 3});
        groups[1] = PortfolioManagerArgsCodec.Group({weight: 0.4e18, members: m1});

        uint32 feeBps = 10_000_000;
        uint32 maxDeviationBps = 50_000_000;

        bytes memory args = PortfolioManagerArgsCodec.build(groups, feeBps, maxDeviationBps);
        bytes memory program = PortfolioManagerProgramBuilder.build(groups, feeBps, maxDeviationBps);

        console2.log("args:");
        console2.logBytes(args);
        console2.log("program:");
        console2.logBytes(program);

        address maker = 0x1111111111111111111111111111111111111111;
        ISwapVM.Order memory order = MakerTraitsLib.build(
            MakerTraitsLib.Args({
                maker: maker,
                shouldUnwrapWeth: false,
                useAquaInsteadOfSignature: true,
                allowZeroAmountIn: false,
                receiver: address(0),
                hasPreTransferInHook: false,
                hasPostTransferInHook: false,
                hasPreTransferOutHook: false,
                hasPostTransferOutHook: false,
                preTransferInTarget: address(0),
                postTransferInTarget: address(0),
                preTransferOutTarget: address(0),
                postTransferOutTarget: address(0),
                preTransferInData: "",
                postTransferInData: "",
                preTransferOutData: "",
                postTransferOutData: "",
                program: program
            })
        );

        console2.log("order.maker:", order.maker);
        console2.log("order.traits:");
        console2.logBytes32(bytes32(MakerTraits.unwrap(order.traits)));
        console2.log("order.data:");
        console2.logBytes(order.data);
        console2.log("abi.encode(order):");
        console2.logBytes(abi.encode(order));
    }
}
