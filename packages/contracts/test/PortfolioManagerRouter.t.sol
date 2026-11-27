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
    address internal protocolTreasury = address(0xDA00000000000000000000000000000000000);
    address internal operatorTreasury = address(0x7121000000000000000000000000000000000);
    address internal operator = address(0x7120000000000000000000000000000000000);
    uint32 internal protocolFeeRateBps = 166_666_667;
    uint32 internal operatorFeeRateBps = 166_666_667;
    address internal revenueShareAdmin = address(0x7122000000000000000000000000000000000);
    address internal revenueShareTreasury = address(0xDA20000000000000000000000000000000000);
    uint32 internal revenueShareRateBps = 16_666_667;

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
            protocolTreasury,
            operatorTreasury,
            operator,
            protocolFeeRateBps,
            operatorFeeRateBps,
            revenueShareAdmin,
            revenueShareTreasury,
            revenueShareRateBps
        );
    }

    function test_ConstructorWiresAquaAndOwnerCorrectly() public {
        PortfolioManagerRouter router = _deploy();

        assertEq(address(router.AQUA()), aqua, "AQUA must be the address passed to the constructor");
        assertEq(router.owner(), owner, "owner (Rescuable/Ownable) must be the address passed to the constructor");
        assertEq(
            router.PROTOCOL_TREASURY(),
            protocolTreasury,
            "PROTOCOL_TREASURY must be the address passed to the constructor"
        );
        assertEq(
            router.operatorTreasury(),
            operatorTreasury,
            "operatorTreasury must be the address passed to the constructor"
        );
        assertEq(router.OPERATOR(), operator, "OPERATOR must be the address passed to the constructor");
        assertEq(
            router.PROTOCOL_FEE_RATE_BPS(),
            protocolFeeRateBps,
            "PROTOCOL_FEE_RATE_BPS must be the rate passed to the constructor"
        );
        assertEq(
            router.operatorFeeRateBps(),
            operatorFeeRateBps,
            "operatorFeeRateBps must be the rate passed to the constructor"
        );
        assertEq(
            router.REVENUE_SHARE_ADMIN(),
            revenueShareAdmin,
            "REVENUE_SHARE_ADMIN must be the address passed to the constructor"
        );
        assertEq(
            router.revenueShareTreasury(),
            revenueShareTreasury,
            "revenueShareTreasury must be the address passed to the constructor"
        );
        assertEq(
            router.revenueShareRateBps(),
            revenueShareRateBps,
            "revenueShareRateBps must be the rate passed to the constructor"
        );
    }

    function test_OperatorCanUpdateOperatorTreasury() public {
        PortfolioManagerRouter router = _deploy();
        address newOperatorTreasury = address(0xBEEF);

        vm.prank(operator);
        router.setOperatorTreasury(newOperatorTreasury);

        assertEq(router.operatorTreasury(), newOperatorTreasury);
    }

    function test_OperatorCanUpdateOperatorFeeRateBps() public {
        PortfolioManagerRouter router = _deploy();

        vm.prank(operator);
        router.setOperatorFeeRateBps(0);

        assertEq(router.operatorFeeRateBps(), 0, "OPERATOR can lower its own rate, including to zero");
    }

    function test_NonOperatorCannotUpdateOperatorTreasury() public {
        PortfolioManagerRouter router = _deploy();

        vm.expectRevert(IPortfolioManagerSwap.PortfolioManagerSwapOnlyOperator.selector);
        router.setOperatorTreasury(address(0xBEEF));
    }

    function test_NonOperatorCannotUpdateOperatorFeeRateBps() public {
        PortfolioManagerRouter router = _deploy();

        vm.expectRevert(IPortfolioManagerSwap.PortfolioManagerSwapOnlyOperator.selector);
        router.setOperatorFeeRateBps(0);
    }

    function test_NotEvenProtocolCanUpdateOperatorConfig() public {
        PortfolioManagerRouter router = _deploy();

        vm.prank(protocolTreasury);
        vm.expectRevert(IPortfolioManagerSwap.PortfolioManagerSwapOnlyOperator.selector);
        router.setOperatorFeeRateBps(0);
    }

    function test_SetOperatorTreasuryRevertsOnZeroAddress() public {
        PortfolioManagerRouter router = _deploy();

        vm.prank(operator);
        vm.expectRevert(IPortfolioManagerSwap.PortfolioManagerSwapZeroAddressDependency.selector);
        router.setOperatorTreasury(address(0));
    }

    function test_SetOperatorFeeRateBpsRevertsAtOrAboveOneHundredPercent() public {
        PortfolioManagerRouter router = _deploy();

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(IPortfolioManagerSwap.PortfolioManagerSwapFeeRateTooHigh.selector, 1e9));
        router.setOperatorFeeRateBps(1e9);
    }

    function test_RevenueShareAdminCanUpdateRevenueShareTreasury() public {
        PortfolioManagerRouter router = _deploy();
        address newRevenueShareTreasury = address(0xBEEF);

        vm.prank(revenueShareAdmin);
        router.setRevenueShareTreasury(newRevenueShareTreasury);

        assertEq(router.revenueShareTreasury(), newRevenueShareTreasury);
    }

    function test_RevenueShareAdminCanUpdateRevenueShareRateBps() public {
        PortfolioManagerRouter router = _deploy();

        vm.prank(revenueShareAdmin);
        router.setRevenueShareRateBps(0);

        assertEq(router.revenueShareRateBps(), 0, "REVENUE_SHARE_ADMIN can lower its own rate, including to zero");
    }

    function test_NonRevenueShareAdminCannotUpdateRevenueShareTreasury() public {
        PortfolioManagerRouter router = _deploy();

        vm.expectRevert(IPortfolioManagerSwap.PortfolioManagerSwapOnlyRevenueShareAdmin.selector);
        router.setRevenueShareTreasury(address(0xBEEF));
    }

    function test_NonRevenueShareAdminCannotUpdateRevenueShareRateBps() public {
        PortfolioManagerRouter router = _deploy();

        vm.expectRevert(IPortfolioManagerSwap.PortfolioManagerSwapOnlyRevenueShareAdmin.selector);
        router.setRevenueShareRateBps(0);
    }

    function test_NotEvenOperatorCanUpdateRevenueShareConfig() public {
        PortfolioManagerRouter router = _deploy();

        vm.prank(operator);
        vm.expectRevert(IPortfolioManagerSwap.PortfolioManagerSwapOnlyRevenueShareAdmin.selector);
        router.setRevenueShareRateBps(0);
    }

    function test_SetRevenueShareRateBpsRevertsAtOrAboveOneHundredPercent() public {
        PortfolioManagerRouter router = _deploy();

        vm.prank(revenueShareAdmin);
        vm.expectRevert(abi.encodeWithSelector(IPortfolioManagerSwap.PortfolioManagerSwapFeeRateTooHigh.selector, 1e9));
        router.setRevenueShareRateBps(1e9);
    }

    /// @dev protocolFeeRateBps (166_666_667) + operatorFeeRateBps (166_666_667) already sum to
    ///      333_333_334; raising operatorFeeRateBps alone to anything at or above
    ///      666_666_667 - revenueShareRateBps (16_666_667) pushes the three-way combined total to
    ///      or past PM_BPS (1e9), even though 650_000_000 alone is well under the single-rate cap.
    function test_SetOperatorFeeRateBpsRevertsWhenCombinedWithOtherRatesReachesOneHundredPercent() public {
        PortfolioManagerRouter router = _deploy();
        uint32 tooHighCombined = 1e9 - protocolFeeRateBps - revenueShareRateBps;

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(IPortfolioManagerSwap.PortfolioManagerSwapCombinedFeeRateTooHigh.selector, 1e9)
        );
        router.setOperatorFeeRateBps(tooHighCombined);
    }

    /// @dev Same combined-cap check, from the revenue-share side instead of the operator side.
    function test_SetRevenueShareRateBpsRevertsWhenCombinedWithOtherRatesReachesOneHundredPercent() public {
        PortfolioManagerRouter router = _deploy();
        uint32 tooHighCombined = 1e9 - protocolFeeRateBps - operatorFeeRateBps;

        vm.prank(revenueShareAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(IPortfolioManagerSwap.PortfolioManagerSwapCombinedFeeRateTooHigh.selector, 1e9)
        );
        router.setRevenueShareRateBps(tooHighCombined);
    }
}
