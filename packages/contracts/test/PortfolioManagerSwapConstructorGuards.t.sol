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

    address internal daoTreasury = address(0xDA0);
    address internal trimTreasury = address(0x7121);
    address internal trimOwner = address(0x7120);

    function _deploy(
        address aqua_,
        address strategyValidator_,
        address sequencerUptimeFeed_,
        address tokenRegistry_,
        address feedRegistry_,
        address daoTreasury_,
        address trimTreasury_,
        address trimOwner_
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
            daoTreasury_,
            trimTreasury_,
            trimOwner_,
            166_666_667,
            166_666_667
        );
    }

    function test_DeploysSuccessfullyWithAllRealDependencies() public {
        _deploy(
            aqua,
            strategyValidator,
            sequencerUptimeFeed,
            tokenRegistry,
            feedRegistry,
            daoTreasury,
            trimTreasury,
            trimOwner
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
            daoTreasury,
            trimTreasury,
            trimOwner
        );
    }

    function test_RevertsOnZeroAddressStrategyValidator() public {
        vm.expectRevert(IPortfolioManagerSwap.PortfolioManagerSwapZeroAddressDependency.selector);
        _deploy(
            aqua, address(0), sequencerUptimeFeed, tokenRegistry, feedRegistry, daoTreasury, trimTreasury, trimOwner
        );
    }

    function test_RevertsOnZeroAddressSequencerUptimeFeed() public {
        vm.expectRevert(IPortfolioManagerSwap.PortfolioManagerSwapZeroAddressDependency.selector);
        _deploy(aqua, strategyValidator, address(0), tokenRegistry, feedRegistry, daoTreasury, trimTreasury, trimOwner);
    }

    function test_RevertsOnZeroAddressTokenRegistry() public {
        vm.expectRevert(IPortfolioManagerSwap.PortfolioManagerSwapZeroAddressDependency.selector);
        _deploy(
            aqua, strategyValidator, sequencerUptimeFeed, address(0), feedRegistry, daoTreasury, trimTreasury, trimOwner
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
            daoTreasury,
            trimTreasury,
            trimOwner
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
            trimTreasury,
            trimOwner
        );
    }

    function test_RevertsOnZeroAddressTrimTreasury() public {
        vm.expectRevert(IPortfolioManagerSwap.PortfolioManagerSwapZeroAddressDependency.selector);
        _deploy(
            aqua,
            strategyValidator,
            sequencerUptimeFeed,
            tokenRegistry,
            feedRegistry,
            daoTreasury,
            address(0),
            trimOwner
        );
    }

    function test_RevertsOnZeroAddressTrimOwner() public {
        vm.expectRevert(IPortfolioManagerSwap.PortfolioManagerSwapZeroAddressDependency.selector);
        _deploy(
            aqua,
            strategyValidator,
            sequencerUptimeFeed,
            tokenRegistry,
            feedRegistry,
            daoTreasury,
            trimTreasury,
            address(0)
        );
    }
}
