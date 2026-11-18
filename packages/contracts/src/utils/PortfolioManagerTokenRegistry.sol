// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

/// @title PortfolioManagerTokenRegistry
/// @notice Permissionless token <-> index registry, letting a PM strategy reference a token by a
///         2-byte index instead of its full 20-byte address.
/// @dev No vetting needed here: a token index carries no safety claim the way a feed index does
///      (see PortfolioManagerFeedRegistry) -- a token is just an address the LP wants exposure
///      to, nothing to get wrong about it the way a feed can quote the wrong pair. Registration
///      is open to anyone. Index 0 is reserved and never assigned, so `indexOf[token] == 0`
///      unambiguously means "not registered."
/// @dev BLEUDEV-449/454: `uint16` caps this registry at 65535 real entries, and `register()` is
///      permissionless, so a well-funded attacker could eventually fill it and block new token
///      onboarding. Accepted as-is rather than widened to `uint32`+: the 2-byte index is a wire-
///      format budget shared with every encoded strategy argument (PortfolioManagerArgsCodec),
///      so widening it is a breaking encoding change, not a local fix -- and filling 65535 slots
///      costs an attacker tens of millions of gas for a griefing outcome (new-token onboarding
///      delayed, not existing strategies broken), not a fund-loss bug. Revisit alongside any
///      future encoding-format version bump, not in isolation.
contract PortfolioManagerTokenRegistry {
    /// @dev tokensByIndex[0] stays the zero address forever -- see this contract's doc comment.
    address[] public tokensByIndex;
    mapping(address => uint16) public indexOf;

    error PortfolioManagerTokenRegistryZeroAddress();
    error PortfolioManagerTokenRegistryFull();

    event TokenRegistered(address indexed token, uint16 index);

    constructor() {
        tokensByIndex.push(address(0));
    }

    /// @notice Registers `token` if it isn't already, returning its index either way.
    function register(address token) external returns (uint16 index) {
        require(token != address(0), PortfolioManagerTokenRegistryZeroAddress());
        uint16 existing = indexOf[token];
        if (existing != 0) return existing;

        require(tokensByIndex.length <= type(uint16).max, PortfolioManagerTokenRegistryFull());
        index = uint16(tokensByIndex.length);
        tokensByIndex.push(token);
        indexOf[token] = index;
        emit TokenRegistered(token, index);
    }

    /// @notice Returns the token at `index`, or the zero address for index 0 or an
    ///         out-of-range index.
    function tokenAt(uint16 index) external view returns (address) {
        return index < tokensByIndex.length ? tokensByIndex[index] : address(0);
    }

    function tokenCount() external view returns (uint256) {
        return tokensByIndex.length;
    }
}
