// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";
import {MakerTraitsLib} from "swap-vm/libs/MakerTraits.sol";
import {PortfolioManagerProgramBuilder} from "../src/PortfolioManagerProgramBuilder.sol";
import {PortfolioManagerE2EBase} from "./base/PortfolioManagerE2EBase.sol";

/// @notice Trades that move the wallet's exposure away from its declared 50/50
/// target — confirm the curve's own price impact penalizes this direction, matching
/// PRICING.md's prediction, against the actually deployed router.
contract PortfolioManagerSkewWorseningE2ETest is PortfolioManagerE2EBase {
    /// @dev See PortfolioManagerSkewReducingE2E.t.sol's identical constant note.
    uint256 internal constant SKEW_AMOUNT = 20_000e18;
    uint256 internal constant TRADE_AMOUNT = 100e18;

    /// @dev Declares the universe in reverse token order from `_buildOrder`'s (still 50/50, so
    ///      functionally identical -- `_weightOf` matches by address, not position). Needed so
    ///      this test's `feeBps = 0` order encodes to different bytes than
    ///      PortfolioManagerSkewReducingE2E's own `feeBps = 0` order: `strategyHash` is
    ///      `keccak256(abi.encode(order))` alone, and forge doesn't snapshot/revert state
    ///      between test *contracts* on a live `--rpc-url` run any more than it does between
    ///      test functions (the same gotcha `PortfolioManagerShipE2E.t.sol`'s
    ///      `LOW_TIER_FEE_BPS + 1` trick works around) -- two contracts shipping the
    ///      byte-identical strategy through the same `pmSafe` would make whichever ships second
    ///      revert on Aqua's own immutability check.
    function _buildOrderWithReversedUniverse() internal view returns (ISwapVM.Order memory) {
        address[] memory reversedUniverse = new address[](2);
        reversedUniverse[0] = address(pmTokenB);
        reversedUniverse[1] = address(pmTokenA);
        uint256[] memory sameWeights = new uint256[](2);
        sameWeights[0] = 0.5e18;
        sameWeights[1] = 0.5e18;
        bytes memory program = PortfolioManagerProgramBuilder.build(reversedUniverse, sameWeights, 0);

        return MakerTraitsLib.build(
            MakerTraitsLib.Args({
                maker: address(pmSafe),
                shouldUnwrapWeth: false,
                useAquaInsteadOfSignature: true,
                allowZeroAmountIn: false,
                receiver: address(0),
                hasPreTransferInHook: false,
                hasPostTransferInHook: false,
                hasPreTransferOutHook: false,
                hasPostTransferOutHook: false,
                preTransferInTarget: address(0),
                preTransferInData: "",
                postTransferInTarget: address(0),
                postTransferInData: "",
                preTransferOutTarget: address(0),
                preTransferOutData: "",
                postTransferOutTarget: address(0),
                postTransferOutData: "",
                program: program
            })
        );
    }

    function test_SkewWorseningTradeGetsPenalizedRate() public {
        // feeBps = 0 isolates the curve's own price-impact penalty from any fee distortion.
        // Full ledger on both sides -- this test isn't exercising the fee-skip ledger-starving
        // scenario.
        ISwapVM.Order memory order = _buildOrderWithReversedUniverse();
        _fundAndShip(order, INITIAL_BALANCE);

        // Wallet starts perfectly balanced; skew it by donating extra tokenA so the wallet is
        // already overweight tokenA relative to target.
        deal(address(pmTokenA), address(pmSafe), INITIAL_BALANCE + SKEW_AMOUNT);

        // Skew-worsening: the taker brings in MORE tokenA (already overweight) and receives
        // tokenB -- pushing the wallet further from 50/50, the opposite correction direction.
        (uint256 amountIn, uint256 amountOut) = _swapExactIn(order, address(pmTokenA), address(pmTokenB), TRADE_AMOUNT);

        // At perfect 50/50 with equal weights the fair rate is 1:1 (no fee here to distort it);
        // worsening an existing skew must fall short of that, per PRICING.md's own prediction.
        assertLt(amountOut, amountIn, "a skew-worsening trade must receive less than the fair 1:1 rate");
    }
}
