// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {FixedPointMath} from "./FixedPointMath.sol";

/// @title PortfolioManagerPricing
/// @notice Independently implements the weighted-curve formulas in docs/PRICING.md.
/// @dev Balances and traded amounts must share one unit. This library reads no balances or prices.
///      PortfolioManagerSwap supplies oracle-valued reserves and converts native token amounts around these calls.
library PortfolioManagerPricing {
    uint256 internal constant WAD = FixedPointMath.WAD;

    error PortfolioManagerPricingZeroBalance();
    error PortfolioManagerPricingInsufficientOutputBalance(uint256 balanceOut, uint256 amountOut);
    error PortfolioManagerPricingPoweredRatioBelowPrecisionFloor(uint256 poweredRatio);

    /// @dev Limits exact-in near-total depletion where fixed-point error can dominate the remaining reserve.
    uint256 private constant MIN_TRUSTWORTHY_POWERED_RATIO = WAD / 1e9;

    /// @param weightIn/weightOut WAD-scaled weights. Only their ratio matters, so the pair need not sum to WAD.
    /// @param feeWad WAD-scaled LP fee fraction on input. Two basis points equals 2e14.
    struct PoolState {
        uint256 balanceIn;
        uint256 balanceOut;
        uint256 weightIn;
        uint256 weightOut;
        uint256 feeWad;
    }

    /// @notice `SP(i→o) = (B_i / w_i) / (B_o / w_o)`, WAD-scaled, before fees — token `i`
    ///         priced in terms of token `o`.
    /// @dev The second multiplication uses weightIn as its explicit scale.
    function spotPrice(PoolState memory q) internal pure returns (uint256) {
        _requireNonZeroBalances(q);
        return FixedPointMath.mulDivDown(FixedPointMath.divDown(q.balanceIn, q.balanceOut), q.weightOut, q.weightIn);
    }

    /// @notice Returns output for an exact input, in the reserves' unit.
    /// @dev For base <= WAD, ceil the ratio, floor the exponent, and bound the power upward.
    ///      Subtracting that bound and flooring output favors the pool.
    ///      The powered-ratio floor separately limits near-total depletion at unequal weights.
    function exactIn(PoolState memory q, uint256 amountIn) internal pure returns (uint256 amountOut) {
        _requireNonZeroBalances(q);

        uint256 amountInEff = FixedPointMath.mulDown(amountIn, WAD - q.feeWad);
        uint256 ratio = FixedPointMath.divUp(q.balanceIn, q.balanceIn + amountInEff);
        uint256 exponent = FixedPointMath.divDown(q.weightIn, q.weightOut);
        uint256 poweredRatio = FixedPointMath.powUp(ratio, exponent);
        // Equal exponents use the exact identity shortcut and bypass the precision floor.
        require(
            exponent == WAD || poweredRatio >= MIN_TRUSTWORTHY_POWERED_RATIO,
            PortfolioManagerPricingPoweredRatioBelowPrecisionFloor(poweredRatio)
        );

        amountOut = FixedPointMath.mulDown(q.balanceOut, WAD - poweredRatio);
        require(amountOut < q.balanceOut, PortfolioManagerPricingInsufficientOutputBalance(q.balanceOut, amountOut));
    }

    /// @notice Returns the gross input, including the LP fee, for exact output in the reserves' unit.
    /// @dev Round all intermediates up and require amountOut < balanceOut.
    ///      Solving the invariant for input uses weightOut/weightIn, the inverse of exactIn's exponent.
    function exactOut(PoolState memory q, uint256 amountOut) internal pure returns (uint256 amountIn) {
        _requireNonZeroBalances(q);
        require(amountOut < q.balanceOut, PortfolioManagerPricingInsufficientOutputBalance(q.balanceOut, amountOut));

        uint256 ratio = FixedPointMath.divUp(q.balanceOut, q.balanceOut - amountOut);
        // For a base >= WAD, both ratio and exponent must round up.
        // Later rounding cannot recover precision lost inside pow.
        uint256 exponent = FixedPointMath.divUp(q.weightOut, q.weightIn);
        uint256 poweredRatio = FixedPointMath.powUp(ratio, exponent);

        uint256 amountInEff = FixedPointMath.mulUp(q.balanceIn, poweredRatio - WAD);
        amountIn = FixedPointMath.divUp(amountInEff, WAD - q.feeWad);
    }

    /// @dev `B_i == 0` or `B_o == 0`: a weighted pool's price is undefined at a zero balance
    ///      on either side — same requirement `BasketXYCSwap.sol`'s PoC already enforces.
    function _requireNonZeroBalances(PoolState memory q) private pure {
        require(q.balanceIn > 0 && q.balanceOut > 0, PortfolioManagerPricingZeroBalance());
    }
}
