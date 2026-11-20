// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Test} from "forge-std/Test.sol";
import {PortfolioManagerProgramBuilder} from "../src/utils/PortfolioManagerProgramBuilder.sol";
import {PortfolioManagerFee} from "../src/utils/PortfolioManagerFee.sol";
import {PortfolioManagerArgsCodec} from "../src/utils/PortfolioManagerArgsCodec.sol";

/// @notice Check opcode and argument-length bytes directly against the SwapVM wire format.
contract PortfolioManagerProgramBuilderTest is Test {
    function _groups() internal pure returns (PortfolioManagerArgsCodec.Group[] memory groups) {
        uint16[2] memory tokenIndices = [uint16(1), uint16(2)];
        uint16[2] memory feedIndices = [uint16(10), uint16(11)];
        groups = new PortfolioManagerArgsCodec.Group[](2);
        for (uint256 i = 0; i < 2; i++) {
            PortfolioManagerArgsCodec.Member[] memory members = new PortfolioManagerArgsCodec.Member[](1);
            members[0] = PortfolioManagerArgsCodec.Member({tokenIndex: tokenIndices[i], feedIndex: feedIndices[i]});
            groups[i] = PortfolioManagerArgsCodec.Group({weight: 0.5e18, members: members});
        }
    }

    function test_BuildProducesCorrectWireFormat() public pure {
        PortfolioManagerArgsCodec.Group[] memory groups = _groups();
        uint32 feeBps = 5_000_000; // 0.5% at PM_BPS = 1e9 scale, the floor

        bytes memory program = PortfolioManagerProgramBuilder.build(groups, feeBps);
        bytes memory expectedArgs = PortfolioManagerArgsCodec.build(groups, feeBps);

        assertEq(program.length, 2 + expectedArgs.length, "opcode byte + argsLength byte + args");
        assertEq(uint8(program[0]), PortfolioManagerProgramBuilder.CURVE_OPCODE, "opcode byte");
        assertEq(uint8(program[1]), uint8(expectedArgs.length), "argsLength byte");

        bytes memory actualArgs = new bytes(expectedArgs.length);
        for (uint256 i = 0; i < expectedArgs.length; i++) {
            actualArgs[i] = program[2 + i];
        }
        assertEq(actualArgs, expectedArgs, "args bytes must match PortfolioManagerArgsCodec's own output exactly");
    }

    function test_DaoFeeBpsFlatRate() public pure {
        assertEq(PortfolioManagerFee.daoFeeBps(0), 0, "zero LP fee yields zero protocol fee");
        assertEq(PortfolioManagerFee.daoFeeBps(600_000), 100_000, "flat 1/6 of the LP fee");
    }

    function test_TrimFeeBpsFlatRate() public pure {
        assertEq(PortfolioManagerFee.trimFeeBps(0), 0, "zero LP fee yields zero Trim fee");
        assertEq(PortfolioManagerFee.trimFeeBps(1_000_000), 100_000, "flat 1/10 of the LP fee");
    }
}
