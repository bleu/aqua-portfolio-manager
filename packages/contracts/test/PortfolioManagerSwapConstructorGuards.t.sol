// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Test} from "forge-std/Test.sol";
import {PortfolioManagerRouter} from "../src/PortfolioManagerRouter.sol";
import {IPortfolioManagerSwap} from "../src/interfaces/IPortfolioManagerSwap.sol";
import {PortfolioManagerStrategyValidator} from "../src/PortfolioManagerStrategyValidator.sol";
import {PortfolioManagerTokenRegistry} from "../src/utils/PortfolioManagerTokenRegistry.sol";
import {PortfolioManagerFeedRegistry} from "../src/utils/PortfolioManagerFeedRegistry.sol";
import {MockAggregatorV3} from "./OracleAdapter.t.sol";

/// @notice A zero-address critical dependency passed to
/// PortfolioManagerSwap's constructor (inherited by every PortfolioManagerRouter deployment) used
/// to be stored without validation -- bricking swaps (or failing with an unrelated, unclear
/// revert) in a way that can never be corrected afterward, since these are all immutables.
contract PortfolioManagerSwapConstructorGuardsTest is Test {
    address internal aqua = address(0x1111);
    address internal strategyValidator;
    address internal sequencerUptimeFeed;
    address internal tokenRegistry;
    address internal feedRegistry;

    function setUp() public {
        tokenRegistry = address(new PortfolioManagerTokenRegistry());
        feedRegistry = address(new PortfolioManagerFeedRegistry(address(this)));
        sequencerUptimeFeed = address(new MockAggregatorV3(0, 0, block.timestamp));
        strategyValidator =
            address(new PortfolioManagerStrategyValidator(sequencerUptimeFeed, tokenRegistry, feedRegistry));
    }

    address internal protocolTreasury = address(0xDA0);
    address internal operatorTreasury = address(0x7121);
    address internal operator = address(0x7120);
    address internal revenueShareAdmin = address(0x7122);
    address internal revenueShareTreasury = address(0xDA2);

    function _deploy(
        address aqua_,
        address strategyValidator_,
        address sequencerUptimeFeed_,
        address tokenRegistry_,
        address feedRegistry_,
        address protocolTreasury_,
        address operatorTreasury_,
        address operator_,
        address revenueShareAdmin_,
        address revenueShareTreasury_
    ) internal returns (PortfolioManagerRouter) {
        return new PortfolioManagerRouter(
            aqua_,
            address(0),
            address(this),
            "PM",
            "1",
            strategyValidator_,
            sequencerUptimeFeed_,
            tokenRegistry_,
            feedRegistry_,
            protocolTreasury_,
            operatorTreasury_,
            operator_,
            166_666_667,
            166_666_667,
            revenueShareAdmin_,
            revenueShareTreasury_,
            16_666_667
        );
    }

    function test_DeploysSuccessfullyWithAllRealDependencies() public {
        _deploy(
            aqua,
            strategyValidator,
            sequencerUptimeFeed,
            tokenRegistry,
            feedRegistry,
            protocolTreasury,
            operatorTreasury,
            operator,
            revenueShareAdmin,
            revenueShareTreasury
        );
    }

    function test_RevertsOnZeroAddressAqua() public {
        vm.expectRevert(IPortfolioManagerSwap.PortfolioManagerSwapZeroAddressDependency.selector);
        _deploy(
            address(0),
            strategyValidator,
            sequencerUptimeFeed,
            tokenRegistry,
            feedRegistry,
            protocolTreasury,
            operatorTreasury,
            operator,
            revenueShareAdmin,
            revenueShareTreasury
        );
    }

    function test_RevertsOnZeroAddressStrategyValidator() public {
        vm.expectRevert(IPortfolioManagerSwap.PortfolioManagerSwapZeroAddressDependency.selector);
        _deploy(
            aqua,
            address(0),
            sequencerUptimeFeed,
            tokenRegistry,
            feedRegistry,
            protocolTreasury,
            operatorTreasury,
            operator,
            revenueShareAdmin,
            revenueShareTreasury
        );
    }

    function test_RevertsOnZeroAddressSequencerUptimeFeed() public {
        vm.expectRevert(IPortfolioManagerSwap.PortfolioManagerSwapZeroAddressDependency.selector);
        _deploy(
            aqua,
            strategyValidator,
            address(0),
            tokenRegistry,
            feedRegistry,
            protocolTreasury,
            operatorTreasury,
            operator,
            revenueShareAdmin,
            revenueShareTreasury
        );
    }

    function test_RevertsOnZeroAddressTokenRegistry() public {
        vm.expectRevert(IPortfolioManagerSwap.PortfolioManagerSwapZeroAddressDependency.selector);
        _deploy(
            aqua,
            strategyValidator,
            sequencerUptimeFeed,
            address(0),
            feedRegistry,
            protocolTreasury,
            operatorTreasury,
            operator,
            revenueShareAdmin,
            revenueShareTreasury
        );
    }

    function test_RevertsOnZeroAddressFeedRegistry() public {
        vm.expectRevert(IPortfolioManagerSwap.PortfolioManagerSwapZeroAddressDependency.selector);
        _deploy(
            aqua,
            strategyValidator,
            sequencerUptimeFeed,
            tokenRegistry,
            address(0),
            protocolTreasury,
            operatorTreasury,
            operator,
            revenueShareAdmin,
            revenueShareTreasury
        );
    }

    function test_RevertsOnZeroAddressDaoTreasury() public {
        vm.expectRevert(IPortfolioManagerSwap.PortfolioManagerSwapZeroAddressDependency.selector);
        _deploy(
            aqua,
            strategyValidator,
            sequencerUptimeFeed,
            tokenRegistry,
            feedRegistry,
            address(0),
            operatorTreasury,
            operator,
            revenueShareAdmin,
            revenueShareTreasury
        );
    }

    function test_RevertsOnZeroAddressOperatorTreasury() public {
        vm.expectRevert(IPortfolioManagerSwap.PortfolioManagerSwapZeroAddressDependency.selector);
        _deploy(
            aqua,
            strategyValidator,
            sequencerUptimeFeed,
            tokenRegistry,
            feedRegistry,
            protocolTreasury,
            address(0),
            operator,
            revenueShareAdmin,
            revenueShareTreasury
        );
    }

    function test_RevertsOnZeroAddressOperator() public {
        vm.expectRevert(IPortfolioManagerSwap.PortfolioManagerSwapZeroAddressDependency.selector);
        _deploy(
            aqua,
            strategyValidator,
            sequencerUptimeFeed,
            tokenRegistry,
            feedRegistry,
            protocolTreasury,
            operatorTreasury,
            address(0),
            revenueShareAdmin,
            revenueShareTreasury
        );
    }

    function test_RevertsOnZeroAddressRevenueShareAdmin() public {
        vm.expectRevert(IPortfolioManagerSwap.PortfolioManagerSwapZeroAddressDependency.selector);
        _deploy(
            aqua,
            strategyValidator,
            sequencerUptimeFeed,
            tokenRegistry,
            feedRegistry,
            protocolTreasury,
            operatorTreasury,
            operator,
            address(0),
            revenueShareTreasury
        );
    }

    function test_RevertsOnZeroAddressRevenueShareTreasury() public {
        vm.expectRevert(IPortfolioManagerSwap.PortfolioManagerSwapZeroAddressDependency.selector);
        _deploy(
            aqua,
            strategyValidator,
            sequencerUptimeFeed,
            tokenRegistry,
            feedRegistry,
            protocolTreasury,
            operatorTreasury,
            operator,
            revenueShareAdmin,
            address(0)
        );
    }
}
