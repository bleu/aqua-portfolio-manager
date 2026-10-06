// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {BaseGuard} from "safe-smart-account/contracts/examples/guards/BaseGuard.sol";
import {Enum} from "safe-smart-account/contracts/libraries/Enum.sol";
import {IAqua} from "aqua/interfaces/IAqua.sol";
import {IBasketScopeGuard} from "./interfaces/IBasketScopeGuard.sol";

/// @title BasketScopeGuard
/// @notice Checks direct Aqua ship() calls from the Safe against a fixed strategy hash and group mapping.
/// @dev The trusted PM hash may span groups. Other strategies must declare tokens from one group.
///      Router identity alone is insufficient because a router can execute multiple strategies.
///      Nested calls and prior strategies are outside this check. See docs/adr/0011-safe-wallet-with-basket-scope-guard.md.
contract BasketScopeGuard is BaseGuard, IBasketScopeGuard {
    /// @inheritdoc IBasketScopeGuard
    address public immutable AQUA;

    /// @inheritdoc IBasketScopeGuard
    address public immutable SAFE;

    /// @inheritdoc IBasketScopeGuard
    bytes32 public immutable TRUSTED_PM_STRATEGY_HASH;

    /// @inheritdoc IBasketScopeGuard
    address public immutable TRUSTED_PM_ROUTER;

    /// @inheritdoc IBasketScopeGuard
    mapping(address token => uint256 basketId) public basketOf;

    constructor(
        address aqua,
        address safe_,
        bytes32 trustedPmStrategyHash,
        address trustedPmRouter,
        address[] memory tokens,
        uint256[] memory basketIds
    ) {
        if (tokens.length != basketIds.length) revert TokenBasketLengthMismatch();

        AQUA = aqua;
        SAFE = safe_;
        TRUSTED_PM_STRATEGY_HASH = trustedPmStrategyHash;
        TRUSTED_PM_ROUTER = trustedPmRouter;

        for (uint256 i = 0; i < tokens.length; i++) {
            if (basketIds[i] == 0) revert BasketIdZeroReserved();
            basketOf[tokens[i]] = basketIds[i];
        }
    }

    /// @dev see ITransactionGuard/IModuleGuard
    function checkTransaction(
        address to,
        uint256, /* value */
        bytes memory data,
        Enum.Operation, /* operation */
        uint256, /* safeTxGas */
        uint256, /* baseGas */
        uint256, /* gasPrice */
        address, /* gasToken */
        address payable, /* refundReceiver */
        bytes memory, /* signatures */
        address /* msgSender */
    ) external view override {
        _check(to, data);
    }

    /// @dev see ITransactionGuard/IModuleGuard
    function checkAfterExecution(bytes32, bool) external override {}

    /// @dev see ITransactionGuard/IModuleGuard
    function checkModuleTransaction(
        address to,
        uint256, /* value */
        bytes memory data,
        Enum.Operation, /* operation */
        address /* module */
    )
        external
        view
        override
        returns (bytes32)
    {
        _check(to, data);
        return bytes32(0);
    }

    /// @dev see ITransactionGuard/IModuleGuard
    function checkAfterModuleExecution(bytes32, bool) external override {}

    /// @dev Checks direct Aqua ship() calls. Other targets and selectors pass without inspection.
    function _check(address to, bytes memory data) internal view {
        if (to != AQUA) return;
        if (data.length < 4 || _selector(data) != IAqua.ship.selector) return;

        (address app, bytes memory strategy, address[] memory tokens,) =
            abi.decode(_stripSelector(data), (address, bytes, address[], uint256[]));

        // The strategy hash alone never identifies which app will run it -- an attacker can
        // replay the publicly-recoverable trusted bytes (from Aqua's own Shipped event) against
        // a different, attacker-controlled app, which Aqua tracks under separate ledger slots.
        // Cross-basket/undeclared tokens stay allowed for the real router by design (ADR-0011):
        // only the empty-list sanity check still applies.
        if (app == TRUSTED_PM_ROUTER && keccak256(strategy) == TRUSTED_PM_STRATEGY_HASH) {
            if (tokens.length == 0) revert EmptyTokenList();
            return;
        }

        if (tokens.length == 0) revert EmptyTokenList();
        uint256 basketId = basketOf[tokens[0]];
        if (basketId == 0) revert TokenNotInAnyBasket(tokens[0]);
        for (uint256 i = 1; i < tokens.length; i++) {
            uint256 tokenBasketId = basketOf[tokens[i]];
            if (tokenBasketId == 0) revert TokenNotInAnyBasket(tokens[i]);
            if (tokenBasketId != basketId) revert CrossBasketStrategyForbidden(tokens[0], tokens[i]);
        }
    }

    function _selector(bytes memory data) private pure returns (bytes4 sel) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            sel := mload(add(data, 0x20))
        }
    }

    /// @dev Deliberately a plain byte-copy loop, not assembly — this guard runs far off the
    ///      hot path (only on `ship()`, never on a taker swap), so auditability wins over gas.
    function _stripSelector(bytes memory data) private pure returns (bytes memory out) {
        uint256 len = data.length - 4;
        out = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            out[i] = data[i + 4];
        }
    }
}
