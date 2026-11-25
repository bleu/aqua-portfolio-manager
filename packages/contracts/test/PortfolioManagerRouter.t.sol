// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Test} from "forge-std/Test.sol";
import {PortfolioManagerRouter} from "../src/PortfolioManagerRouter.sol";
import {IPortfolioManagerSwap} from "../src/interfaces/IPortfolioManagerSwap.sol";

/// @notice Constructor wiring isn't exercised by any opcode-dispatch test elsewhere. `weth`
/// isn't asserted: `OnlyWethReceiver` stores it in a private immutable with no accessor.
contract PortfolioManagerRouterTest is Test {
    address internal aqua = address(0xA11CE00000000000000000000000000000000A);
    address internal weth = address(0xB0B0000000000000000000000000000000000B);
    address internal owner = address(0xC0FFEE0000000000000000000000000000000C);
    address internal strategyValidator = address(0xFAC70000000000000000000000000000000000);
    address internal sequencerUptimeFeed = address(0x5EC000000000000000000000000000000000AD);
    address internal tokenRegistry = address(0x7071E000000000000000000000000000000000);
    address internal feedRegistry = address(0xFEEDBEEF00000000000000000000000000000);
    address internal daoTreasury = address(0xDA00000000000000000000000000000000000);
    address internal trimTreasury = address(0x7121000000000000000000000000000000000);
    address internal trimOwner = address(0x7120000000000000000000000000000000000);
    uint32 internal daoFeeRateBps = 166_666_667;
    uint32 internal trimFeeRateBps = 166_666_667;

    function _deploy() internal returns (PortfolioManagerRouter) {
        return new PortfolioManagerRouter(
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
            trimOwner,
            daoFeeRateBps,
            trimFeeRateBps
        );
    }

    function test_ConstructorWiresAquaAndOwnerCorrectly() public {
        PortfolioManagerRouter router = _deploy();

        assertEq(address(router.AQUA()), aqua, "AQUA must be the address passed to the constructor");
        assertEq(router.owner(), owner, "owner (Rescuable/Ownable) must be the address passed to the constructor");
        assertEq(router.DAO_TREASURY(), daoTreasury, "DAO_TREASURY must be the address passed to the constructor");
        assertEq(router.trimTreasury(), trimTreasury, "trimTreasury must be the address passed to the constructor");
        assertEq(router.TRIM_OWNER(), trimOwner, "TRIM_OWNER must be the address passed to the constructor");
        assertEq(
            router.DAO_FEE_RATE_BPS(), daoFeeRateBps, "DAO_FEE_RATE_BPS must be the rate passed to the constructor"
        );
        assertEq(router.trimFeeRateBps(), trimFeeRateBps, "trimFeeRateBps must be the rate passed to the constructor");
    }

    function test_TrimOwnerCanUpdateTrimTreasury() public {
        PortfolioManagerRouter router = _deploy();
        address newTrimTreasury = address(0xBEEF);

        vm.prank(trimOwner);
        router.setTrimTreasury(newTrimTreasury);

        assertEq(router.trimTreasury(), newTrimTreasury);
    }

    function test_TrimOwnerCanUpdateTrimFeeRateBps() public {
        PortfolioManagerRouter router = _deploy();

        vm.prank(trimOwner);
        router.setTrimFeeRateBps(0);

        assertEq(router.trimFeeRateBps(), 0, "TRIM_OWNER can lower its own rate, including to zero");
    }

    function test_NonTrimOwnerCannotUpdateTrimTreasury() public {
        PortfolioManagerRouter router = _deploy();

        vm.expectRevert(IPortfolioManagerSwap.PortfolioManagerSwapOnlyTrimOwner.selector);
        router.setTrimTreasury(address(0xBEEF));
    }

    function test_NonTrimOwnerCannotUpdateTrimFeeRateBps() public {
        PortfolioManagerRouter router = _deploy();

        vm.expectRevert(IPortfolioManagerSwap.PortfolioManagerSwapOnlyTrimOwner.selector);
        router.setTrimFeeRateBps(0);
    }

    function test_NotEvenDaoCanUpdateTrimConfig() public {
        PortfolioManagerRouter router = _deploy();

        vm.prank(daoTreasury);
        vm.expectRevert(IPortfolioManagerSwap.PortfolioManagerSwapOnlyTrimOwner.selector);
        router.setTrimFeeRateBps(0);
    }

    function test_SetTrimTreasuryRevertsOnZeroAddress() public {
        PortfolioManagerRouter router = _deploy();

        vm.prank(trimOwner);
        vm.expectRevert(IPortfolioManagerSwap.PortfolioManagerSwapZeroAddressDependency.selector);
        router.setTrimTreasury(address(0));
    }

    function test_SetTrimFeeRateBpsRevertsAtOrAboveOneHundredPercent() public {
        PortfolioManagerRouter router = _deploy();

        vm.prank(trimOwner);
        vm.expectRevert(abi.encodeWithSelector(IPortfolioManagerSwap.PortfolioManagerSwapFeeRateTooHigh.selector, 1e9));
        router.setTrimFeeRateBps(1e9);
    }
}
