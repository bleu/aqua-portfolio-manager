// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Test} from "forge-std/Test.sol";
import {PortfolioManagerRouter} from "../src/PortfolioManagerRouter.sol";

/// @notice Constructor wiring isn't exercised by any opcode-dispatch test elsewhere. `weth`
/// isn't asserted: `OnlyWethReceiver` stores it in a private immutable with no accessor.
contract PortfolioManagerRouterTest is Test {
    function test_ConstructorWiresAquaAndOwnerCorrectly() public {
        address aqua = address(0xA11CE00000000000000000000000000000000A);
        address weth = address(0xB0B0000000000000000000000000000000000B);
        address owner = address(0xC0FFEE0000000000000000000000000000000C);
        address strategyValidator = address(0xFAC70000000000000000000000000000000000);
        address sequencerUptimeFeed = address(0x5EC000000000000000000000000000000000AD);
        address tokenRegistry = address(0x7071E000000000000000000000000000000000);
        address feedRegistry = address(0xFEEDBEEF00000000000000000000000000000);
        address daoTreasury = address(0xDA00000000000000000000000000000000000);
        address trimTreasury = address(0x7121000000000000000000000000000000000);
        uint32 daoFeeRateBps = 166_666_667;
        uint32 trimFeeRateBps = 100_000_000;

        PortfolioManagerRouter router = new PortfolioManagerRouter(
            aqua,
            weth,
            owner,
            "PM",
            "1",
            strategyValidator,
            sequencerUptimeFeed,
            tokenRegistry,
            feedRegistry,
            daoTreasury,
            trimTreasury,
            daoFeeRateBps,
            trimFeeRateBps
        );

        assertEq(address(router.AQUA()), aqua, "AQUA must be the address passed to the constructor");
        assertEq(router.owner(), owner, "owner (Rescuable/Ownable) must be the address passed to the constructor");
        assertEq(router.DAO_TREASURY(), daoTreasury, "DAO_TREASURY must be the address passed to the constructor");
        assertEq(router.TRIM_TREASURY(), trimTreasury, "TRIM_TREASURY must be the address passed to the constructor");
        assertEq(
            router.DAO_FEE_RATE_BPS(), daoFeeRateBps, "DAO_FEE_RATE_BPS must be the rate passed to the constructor"
        );
        assertEq(
            router.TRIM_FEE_RATE_BPS(), trimFeeRateBps, "TRIM_FEE_RATE_BPS must be the rate passed to the constructor"
        );
    }
}
