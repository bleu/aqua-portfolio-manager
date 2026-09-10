// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Calldata} from "@1inch/solidity-utils/contracts/libraries/Calldata.sol";

/// @dev Matches swap-vm's own `Fee.sol` BPS convention (1e9 = 100%) so `feeBps` here reads the
///      same way as everywhere else in this codebase, not a project-specific scale.
uint256 constant PM_BPS = 1e9;

/// @title PortfolioManagerArgsBuilder — packed-bytes encoding of the Portfolio Manager's
///        declared token universe, per-token target weight, and protocol fee
/// @notice One token per group this milestone; multi-token group routing is separately unbuilt,
///         so "group id per token" degenerates to "each token is its own group" — this stores a
///         (token, weight) pair per declared token
///         rather than a separate group-id field that would always equal the token's own
///         index. Weights are otherwise fully general (not required equal): `PRICING.md`'s
///         formula already reduces correctly at equal weights, so there is nothing to
///         special-case here for the common case.
/// @dev Lives entirely in the swapVM instruction's `args` — part of the immutable `strategy`
///      payload hashed into `strategyHash` (see `IAqua.ship`), not contract storage.
library PortfolioManagerArgsBuilder {
    using Calldata for bytes;

    uint256 private constant WAD = 1e18;
    /// @dev 20-byte token address + 16-byte uint128 weight. uint128 loses no precision here:
    ///      every weight that ever reaches the packed encoding already passed the `sum == WAD`
    ///      check below, and WAD (1e18) is far under uint128's ~3.4e38 range, so no individual
    ///      weight can be truncated by the cast to uint128.
    uint256 private constant TOKEN_ENTRY_SIZE = 36;

    error PortfolioManagerEmptyUniverse();
    error PortfolioManagerTooManyTokens(uint256 count);
    error PortfolioManagerTokensWeightsLengthMismatch();
    error PortfolioManagerFeeBpsOutOfRange(uint32 feeBps);
    error PortfolioManagerZeroWeight(uint256 index);
    error PortfolioManagerWeightsMustSumToWad(uint256 sum);
    error PortfolioManagerMissingTokenCount();
    error PortfolioManagerMissingTokenEntry();
    error PortfolioManagerMissingFeeBps();

    /// @param tokens  Declared token universe, one entry per group (see @notice)
    /// @param weights Target weight per token, WAD-scaled (18 decimals); must sum to WAD
    /// @param feeBps  Protocol fee, BPS-scaled per `PM_BPS` (2bps default per ADR-0008)
    function build(address[] memory tokens, uint256[] memory weights, uint32 feeBps)
        internal
        pure
        returns (bytes memory args)
    {
        require(tokens.length > 0, PortfolioManagerEmptyUniverse());
        require(tokens.length == weights.length, PortfolioManagerTokensWeightsLengthMismatch());
        require(tokens.length <= type(uint8).max, PortfolioManagerTooManyTokens(tokens.length));
        require(feeBps <= PM_BPS, PortfolioManagerFeeBpsOutOfRange(feeBps));

        args = abi.encodePacked(uint8(tokens.length));

        uint256 sum;
        for (uint256 i = 0; i < tokens.length; i++) {
            require(weights[i] > 0, PortfolioManagerZeroWeight(i));
            sum += weights[i];
            args = abi.encodePacked(args, tokens[i], uint128(weights[i]));
        }
        require(sum == WAD, PortfolioManagerWeightsMustSumToWad(sum));

        args = abi.encodePacked(args, feeBps);
    }

    /// @dev Independently re-validates `sum(weights) == WAD` and every individual weight `> 0`
    ///      on every parse, not just at `build()` time — `args` is maker-supplied strategy
    ///      calldata and can be hand-crafted to bypass `build()` entirely, and
    ///      `DONATION-RESISTANCE-PROOF.md`'s algebraic proof depends on the weights actually
    ///      summing to one, not merely being labeled as such. A zero weight isn't caught by the
    ///      sum check alone (it just shifts the remainder onto other tokens) but would make
    ///      `PortfolioManagerPricing`'s `weightIn/weightOut` ratio divide by zero on every trade
    ///      for that token — rejected here instead, at ship()-time, not at first-trade-time.
    function parse(bytes calldata args)
        internal
        pure
        returns (address[] memory tokens, uint256[] memory weights, uint32 feeBps)
    {
        uint8 count = uint8(bytes1(args.slice(0, 1, PortfolioManagerMissingTokenCount.selector)));
        require(count > 0, PortfolioManagerEmptyUniverse());

        tokens = new address[](count);
        weights = new uint256[](count);

        uint256 sum;
        uint256 offset = 1;
        for (uint256 i = 0; i < count; i++) {
            // Bounds-check the whole entry up front so a truncated last entry reverts here,
            // not with a confusing out-of-bounds error from the narrower slices below.
            args.slice(offset, offset + TOKEN_ENTRY_SIZE, PortfolioManagerMissingTokenEntry.selector);
            tokens[i] = address(bytes20(args.slice(offset, offset + 20)));
            weights[i] = uint256(uint128(bytes16(args.slice(offset + 20, offset + TOKEN_ENTRY_SIZE))));
            require(weights[i] > 0, PortfolioManagerZeroWeight(i));
            sum += weights[i];
            offset += TOKEN_ENTRY_SIZE;
        }
        require(sum == WAD, PortfolioManagerWeightsMustSumToWad(sum));

        feeBps = uint32(bytes4(args.slice(offset, offset + 4, PortfolioManagerMissingFeeBps.selector)));
        require(feeBps <= PM_BPS, PortfolioManagerFeeBpsOutOfRange(feeBps));
    }
}
