// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";
import {MakerTraitsLib} from "swap-vm/libs/MakerTraits.sol";
import {PortfolioManagerArgsCodec} from "../../src/utils/PortfolioManagerArgsCodec.sol";
import {PortfolioManagerProgramBuilder} from "../../src/utils/PortfolioManagerProgramBuilder.sol";
import {PortfolioManagerE2EBase} from "./base/PortfolioManagerE2EBase.t.sol";

contract PortfolioManagerSkewWorseningE2ETest is PortfolioManagerE2EBase {
    /// @dev See PortfolioManagerSkewReducingE2E.t.sol's identical constant note.
    uint256 internal constant SKEW_AMOUNT = 20_000e18;
    uint256 internal constant TRADE_AMOUNT = 100e18;

    /// @dev Reverse group order to produce a distinct hash while preserving the equal-weight configuration.
    function _buildOrderWithReversedUniverse() internal view returns (ISwapVM.Order memory) {
        PortfolioManagerArgsCodec.Group[] memory reversedGroups = new PortfolioManagerArgsCodec.Group[](2);
        reversedGroups[0] = _singleMemberGroup(0.5e18, address(pmTokenB), DAI_USD_FEED_BASE);
        reversedGroups[1] = _singleMemberGroup(0.5e18, address(pmTokenA), ETH_USD_FEED_BASE);
        bytes memory program = PortfolioManagerProgramBuilder.build(reversedGroups, 0);

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
        // Disable fees to isolate price impact.
        ISwapVM.Order memory order = _buildOrderWithReversedUniverse();
        _fundAndShip(order, INITIAL_BALANCE);

        // Wallet starts perfectly balanced; skew it by donating extra tokenA so the wallet is
        // already overweight tokenA relative to target.
        deal(address(pmTokenA), address(pmSafe), INITIAL_BALANCE + SKEW_AMOUNT);

        // Skew-worsening: the taker brings in MORE tokenA (already overweight) and receives
        // tokenB -- pushing the wallet further from 50/50, the opposite correction direction.
        (uint256 amountIn, uint256 amountOut) = _swapExactIn(order, address(pmTokenA), address(pmTokenB), TRADE_AMOUNT);

        assertLt(amountOut, amountIn, "a skew-worsening trade must receive less than the fair 1:1 rate");
    }
}
