// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

/// @title AggregatorV3Interface — the standard Chainlink price feed interface
/// @notice Re-declared locally (not pulled in via a `lib/` submodule) since this is the whole
///         surface `OracleAdapter` needs: a stable, published function-signature interface, not
///         an implementation to vendor. Matches Chainlink's own publicly documented ABI exactly.
interface AggregatorV3Interface {
    function decimals() external view returns (uint8);

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}
