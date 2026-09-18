// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Test} from "forge-std/Test.sol";
import {PortfolioManagerProgramBuilder} from "../src/utils/PortfolioManagerProgramBuilder.sol";
import {PortfolioManagerArgsCodec} from "../src/utils/PortfolioManagerArgsCodec.sol";

/// @notice `build()`'s own wire-format output, asserted directly against VM.sol's runLoop
/// format (`[opcode:1][argsLength:1][args]`) -- every other test exercises this only
/// indirectly, via a full round-trip through the router (ship a strategy, confirm it prices
/// correctly), which would still pass even if the opcode or length byte were wrong as long as
/// VM.sol's own parser happened to tolerate it.
contract PortfolioManagerProgramBuilderTest is Test {
    function _groups() internal pure returns (PortfolioManagerArgsCodec.Group[] memory groups) {
        address[2] memory tokens = [address(0x1111), address(0x2222)];
        address[2] memory feeds = [address(0xFEED1), address(0xFEED2)];
        groups = new PortfolioManagerArgsCodec.Group[](2);
        for (uint256 i = 0; i < 2; i++) {
            PortfolioManagerArgsCodec.Member[] memory members = new PortfolioManagerArgsCodec.Member[](1);
            members[0] = PortfolioManagerArgsCodec.Member({token: tokens[i], feed: feeds[i], maxStaleness: 3600});
            groups[i] = PortfolioManagerArgsCodec.Group({weight: 0.5e18, members: members});
        }
    }

    function test_BuildProducesCorrectWireFormat() public pure {
        PortfolioManagerArgsCodec.Group[] memory groups = _groups();
        uint32 feeBps = 200_000; // 2 bps at PM_BPS = 1e9 scale

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

    function test_DaoFeeBpsTiering() public pure {
        assertEq(PortfolioManagerProgramBuilder.daoFeeBps(0), 0, "zero LP fee yields zero protocol fee");
        assertEq(PortfolioManagerProgramBuilder.daoFeeBps(200_000), 50_000, "1/4 of 2 bps, well under the threshold");
        assertEq(
            PortfolioManagerProgramBuilder.daoFeeBps(PortfolioManagerProgramBuilder.TIER_THRESHOLD_BPS),
            PortfolioManagerProgramBuilder.TIER_THRESHOLD_BPS / 4,
            "the threshold itself is still low-tier (<=), per 1IP-103's own wording"
        );
        assertEq(
            PortfolioManagerProgramBuilder.daoFeeBps(PortfolioManagerProgramBuilder.TIER_THRESHOLD_BPS + 1),
            (PortfolioManagerProgramBuilder.TIER_THRESHOLD_BPS + 1) / 6,
            "one wei above the threshold is high-tier"
        );
    }
}
