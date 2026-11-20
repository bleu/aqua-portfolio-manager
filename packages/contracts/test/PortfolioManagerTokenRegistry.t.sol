// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Test} from "forge-std/Test.sol";
import {PortfolioManagerTokenRegistry} from "../src/utils/PortfolioManagerTokenRegistry.sol";

contract PortfolioManagerTokenRegistryTest is Test {
    PortfolioManagerTokenRegistry internal registry;
    address internal tokenA = address(0xA11CE);

    function setUp() public {
        registry = new PortfolioManagerTokenRegistry();
    }

    /// @dev The reserved "not registered" sentinel -- always valid, must never revert.
    function test_TokenAtReturnsZeroAddressForIndex0() public view {
        assertEq(registry.tokenAt(0), address(0));
    }

    function test_TokenAtReturnsTheRegisteredToken() public {
        uint16 index = registry.register(tokenA);
        assertEq(registry.tokenAt(index), tokenA);
    }

    /// @notice An index that was never registered used to silently resolve to
    /// address(0), identical to index 0's legitimate "not registered" sentinel -- a caller that
    /// doesn't defensively check for address(0) could mishandle it as a real token. Must revert
    /// instead, same fix shape as PortfolioManagerFeedRegistry.
    function test_TokenAtRevertsForNeverRegisteredIndex() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                PortfolioManagerTokenRegistry.PortfolioManagerTokenRegistryIndexOutOfRange.selector, 1
            )
        );
        registry.tokenAt(1);
    }

    function test_TokenAtRevertsForIndexOneOutOfRange() public {
        uint16 lastValidIndex = registry.register(tokenA);
        uint16 outOfRange = lastValidIndex + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                PortfolioManagerTokenRegistry.PortfolioManagerTokenRegistryIndexOutOfRange.selector, outOfRange
            )
        );
        registry.tokenAt(outOfRange);
    }

    function test_TokenAtRevertsForMaxUint16Index() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                PortfolioManagerTokenRegistry.PortfolioManagerTokenRegistryIndexOutOfRange.selector, type(uint16).max
            )
        );
        registry.tokenAt(type(uint16).max);
    }
}
