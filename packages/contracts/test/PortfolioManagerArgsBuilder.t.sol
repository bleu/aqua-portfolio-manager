// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {PortfolioManagerArgsBuilder, PM_BPS} from "../src/PortfolioManagerArgsBuilder.sol";

contract PortfolioManagerArgsBuilderTest is Test {
    uint256 constant WAD = 1e18;

    address constant TOKEN_A = address(0xA11CE);
    address constant TOKEN_B = address(0xB0B);
    address constant TOKEN_C = address(0xC0FFEE);

    // See FixedPointMath.t.sol for why internal pure library calls need an external wrapper
    // for `vm.expectRevert` to intercept the revert at the right call depth.
    function _callBuild(address[] memory tokens, uint256[] memory weights, uint32 feeBps)
        external
        pure
        returns (bytes memory)
    {
        return PortfolioManagerArgsBuilder.build(tokens, weights, feeBps);
    }

    function _callParse(bytes calldata args)
        external
        pure
        returns (address[] memory, uint256[] memory, uint32)
    {
        return PortfolioManagerArgsBuilder.parse(args);
    }

    // ---- round trip ----

    function test_BuildThenParseRoundTripsSingleToken() public view {
        address[] memory tokens = new address[](1);
        tokens[0] = TOKEN_A;
        uint256[] memory weights = new uint256[](1);
        weights[0] = WAD;

        bytes memory args = PortfolioManagerArgsBuilder.build(tokens, weights, 2e5); // 2bps, ADR-0008 default
        (address[] memory parsedTokens, uint256[] memory parsedWeights, uint32 parsedFeeBps) =
            this._callParse(args);

        assertEq(parsedTokens.length, 1);
        assertEq(parsedTokens[0], TOKEN_A);
        assertEq(parsedWeights[0], WAD);
        assertEq(parsedFeeBps, 2e5);
    }

    function test_BuildThenParseRoundTripsUnequalWeights() public view {
        address[] memory tokens = new address[](3);
        tokens[0] = TOKEN_A;
        tokens[1] = TOKEN_B;
        tokens[2] = TOKEN_C;
        uint256[] memory weights = new uint256[](3);
        weights[0] = 0.5e18;
        weights[1] = 0.3e18;
        weights[2] = 0.2e18;

        bytes memory args = PortfolioManagerArgsBuilder.build(tokens, weights, 0);
        (address[] memory parsedTokens, uint256[] memory parsedWeights, uint32 parsedFeeBps) =
            this._callParse(args);

        assertEq(parsedTokens.length, 3);
        for (uint256 i = 0; i < 3; i++) {
            assertEq(parsedTokens[i], tokens[i]);
            assertEq(parsedWeights[i], weights[i]);
        }
        assertEq(parsedFeeBps, 0);
    }

    function testFuzz_BuildThenParseRoundTrips(uint8 seed, uint32 feeBps) public view {
        feeBps = uint32(bound(feeBps, 0, PM_BPS));
        uint256 n = bound(seed, 1, 10);

        address[] memory tokens = new address[](n);
        uint256[] memory weights = new uint256[](n);
        uint256 remaining = WAD;
        for (uint256 i = 0; i < n; i++) {
            tokens[i] = address(uint160(0x1000 + i));
            // Last weight soaks up the remainder so the set always sums to exactly WAD.
            weights[i] = i == n - 1 ? remaining : remaining / (n - i);
            remaining -= weights[i];
        }

        bytes memory args = PortfolioManagerArgsBuilder.build(tokens, weights, feeBps);
        (address[] memory parsedTokens, uint256[] memory parsedWeights, uint32 parsedFeeBps) =
            this._callParse(args);

        assertEq(parsedTokens.length, n);
        for (uint256 i = 0; i < n; i++) {
            assertEq(parsedTokens[i], tokens[i]);
            assertEq(parsedWeights[i], weights[i]);
        }
        assertEq(parsedFeeBps, feeBps);
    }

    // ---- build: validation ----

    function test_BuildRevertsOnEmptyUniverse() public {
        address[] memory tokens = new address[](0);
        uint256[] memory weights = new uint256[](0);

        vm.expectRevert(PortfolioManagerArgsBuilder.PortfolioManagerEmptyUniverse.selector);
        this._callBuild(tokens, weights, 0);
    }

    function test_BuildRevertsOnLengthMismatch() public {
        address[] memory tokens = new address[](2);
        tokens[0] = TOKEN_A;
        tokens[1] = TOKEN_B;
        uint256[] memory weights = new uint256[](1);
        weights[0] = WAD;

        vm.expectRevert(PortfolioManagerArgsBuilder.PortfolioManagerTokensWeightsLengthMismatch.selector);
        this._callBuild(tokens, weights, 0);
    }

    function test_BuildRevertsWhenWeightsDoNotSumToWad() public {
        address[] memory tokens = new address[](2);
        tokens[0] = TOKEN_A;
        tokens[1] = TOKEN_B;
        uint256[] memory weights = new uint256[](2);
        weights[0] = 0.5e18;
        weights[1] = 0.4e18; // sums to 0.9e18, not WAD

        vm.expectRevert(
            abi.encodeWithSelector(PortfolioManagerArgsBuilder.PortfolioManagerWeightsMustSumToWad.selector, 0.9e18)
        );
        this._callBuild(tokens, weights, 0);
    }

    function test_BuildRevertsOnFeeBpsAboveHundredPercent() public {
        address[] memory tokens = new address[](1);
        tokens[0] = TOKEN_A;
        uint256[] memory weights = new uint256[](1);
        weights[0] = WAD;

        vm.expectRevert(
            abi.encodeWithSelector(PortfolioManagerArgsBuilder.PortfolioManagerFeeBpsOutOfRange.selector, PM_BPS + 1)
        );
        this._callBuild(tokens, weights, uint32(PM_BPS + 1));
    }

    // ---- parse: hand-crafted args must be independently validated, not just trust build() ----

    function test_ParseRevertsWhenHandCraftedWeightsDoNotSumToWad() public {
        // 1 token, weight 0.5e18 (not WAD), feeBps 0 -- crafted directly, bypassing build().
        bytes memory malformed = abi.encodePacked(uint8(1), TOKEN_A, uint128(0.5e18), uint32(0));

        vm.expectRevert(
            abi.encodeWithSelector(PortfolioManagerArgsBuilder.PortfolioManagerWeightsMustSumToWad.selector, 0.5e18)
        );
        this._callParse(malformed);
    }

    function test_ParseRevertsOnEmptyUniverse() public {
        bytes memory malformed = abi.encodePacked(uint8(0));

        vm.expectRevert(PortfolioManagerArgsBuilder.PortfolioManagerEmptyUniverse.selector);
        this._callParse(malformed);
    }

    function test_ParseRevertsOnTruncatedTokenEntry() public {
        // Declares 1 token but only supplies 10 of the required 36 bytes for it.
        bytes memory malformed = abi.encodePacked(uint8(1), uint80(0));

        vm.expectRevert(PortfolioManagerArgsBuilder.PortfolioManagerMissingTokenEntry.selector);
        this._callParse(malformed);
    }

    function test_ParseRevertsOnMissingFeeBps() public {
        // Valid single-token universe (sums to WAD) but no trailing feeBps bytes.
        bytes memory malformed = abi.encodePacked(uint8(1), TOKEN_A, uint128(WAD));

        vm.expectRevert(PortfolioManagerArgsBuilder.PortfolioManagerMissingFeeBps.selector);
        this._callParse(malformed);
    }
}
