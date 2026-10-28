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
///      Also unwraps exactly one level of a batch routed through either Safe deployment of
///      `MultiSendCallOnly` below, checking each inner call the same way as a direct one -- see
///      MULTISEND_CALL_ONLY_* doc comments for why only these two addresses are trusted for this,
///      and why unwrapping stops at one level. A batch routed through anything else, or a
///      ship() nested two batches deep, is outside this check, same as any other untrusted
///      target. See docs/adr/0011-safe-wallet-with-basket-scope-guard.md.
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

    /// @dev Safe's own canonical `MultiSendCallOnly` deployment (same address on every chain Safe
    ///      deploys to). Verified directly: real deployed bytecode, exact `multiSend(bytes)`
    ///      selector (`0x8d80ff0a`), and its own source (`case 1 { revert(0, 0) }`) proves every
    ///      inner call it makes is a plain `Call`, never a `DelegateCall` -- the one property this
    ///      guard's one-level unwrap relies on: an inner entry can never itself be a delegatecall
    ///      into a second, nested batch that could hide a ship() call from this check differently
    ///      than the trusted-relay case handles it.
    address private constant MULTISEND_CALL_ONLY_CANONICAL = 0x40A2aCCbd92BCA938b02010E17A5b8929b49130D;

    /// @dev A second, separately-deployed instance of the exact same `MultiSendCallOnly.sol`
    ///      source -- confirmed via Sourcify (`runtimeMatch: "exact_match"` against the real
    ///      source, same `case 1 { revert(0, 0) }` no-delegatecall guarantee), not assumed from
    ///      matching bytecode length or selector alone. Needed because Safe{Wallet}'s own batch
    ///      construction (confirmed on a real, live Safe transaction) routes through this address,
    ///      not the canonical one above -- an allowlist of only the canonical address would miss
    ///      every real batch this app's own users actually produce.
    address private constant MULTISEND_CALL_ONLY_SAFE_WALLET = 0xA83c336B20401Af773B6219BA5027174338D1836;

    /// @dev `multiSend(bytes)`'s selector.
    bytes4 private constant MULTISEND_SELECTOR = 0x8d80ff0a;

    error MalformedMultiSendHeader();
    error MalformedMultiSendBody();

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

    /// @dev Dispatches to either the one-level MultiSend unwrap or a direct single-call check.
    function _check(address to, bytes memory data) internal view {
        if (_isTrustedMultiSendRelay(to) && data.length >= 4 && _selector(data) == MULTISEND_SELECTOR) {
            _checkMultiSendBatch(data);
            return;
        }
        _checkSingleCall(to, data);
    }

    function _isTrustedMultiSendRelay(address to) internal pure returns (bool) {
        return to == MULTISEND_CALL_ONLY_CANONICAL || to == MULTISEND_CALL_ONLY_SAFE_WALLET;
    }

    /// @dev Decodes exactly one level of MultiSendCallOnly's own packed format (1 byte operation +
    ///      20 bytes to + 32 bytes value + 32 bytes data length + data, repeated) and runs
    ///      `_checkSingleCall` on each inner entry -- never on the entry's own `to` again, even if
    ///      it also happens to be a trusted relay, which is exactly how a second, nested batch
    ///      stays out of scope (see this contract's own top doc comment). The header/body bounds
    ///      validation mirrors Zodiac Roles Modifier's own `MultiSendUnwrapper.sol` precisely,
    ///      including the exact-length check against the padded transactions blob -- that check
    ///      exists specifically to stop a crafted batch whose declared length is shorter than its
    ///      real data from making this guard check different bytes than `MultiSendCallOnly` (whose
    ///      own assembly loop walks by actual offsets, not the declared length) will really
    ///      execute.
    function _checkMultiSendBatch(bytes memory data) internal view {
        // data = 4-byte selector + encodeWithSelector(bytes transactions), i.e. the standard ABI
        // encoding of one `bytes` parameter: a 32-byte offset (always 0x20 here), a 32-byte
        // length, then the length's own bytes, padded up to a multiple of 32.
        if (data.length < 4 + 32 + 32) revert MalformedMultiSendHeader();
        if (_toUint256(data, 4) != 0x20) revert MalformedMultiSendHeader();

        uint256 transactionsLength = _toUint256(data, 4 + 32);
        uint256 transactionsStart = 4 + 32 + 32;
        if (transactionsStart + _ceil32(transactionsLength) != data.length) revert MalformedMultiSendHeader();

        uint256 offset = transactionsStart;
        uint256 end = transactionsStart + transactionsLength;
        bool sawOneEntry = false;

        while (offset < end) {
            // Per entry: operation (1 byte) + to (20 bytes) + value (32 bytes) + data length
            // (32 bytes) + data (data length bytes) -- MultiSendCallOnly's own exact layout.
            if (offset + 1 + 20 + 32 + 32 > end) revert MalformedMultiSendBody();

            uint8 operation = uint8(data[offset]);
            // Belt-and-suspenders: MULTISEND_CALL_ONLY_* already reverts on-chain for operation 1,
            // so a real execution can never actually reach this guard with one -- but this check
            // costs little and keeps the guard's own logic correct even if that assumption ever
            // stops holding (e.g. a future trusted-relay addition that isn't CallOnly).
            if (operation != 0) revert MalformedMultiSendBody();

            address innerTo = _toAddress(data, offset + 1);
            uint256 innerDataLength = _toUint256(data, offset + 1 + 20 + 32);
            uint256 innerDataStart = offset + 1 + 20 + 32 + 32;
            if (innerDataStart + innerDataLength > end) revert MalformedMultiSendBody();

            _checkSingleCall(innerTo, _slice(data, innerDataStart, innerDataLength));

            offset = innerDataStart + innerDataLength;
            sawOneEntry = true;
        }

        if (!sawOneEntry) revert MalformedMultiSendBody();
    }

    /// @dev Checks a direct Aqua ship() call. Other targets and selectors pass without inspection.
    ///      Never unwraps a batch itself -- see this contract's own top doc comment for why a
    ///      batch nested inside this call (if `to` happens to also be a trusted relay) is
    ///      deliberately out of scope, not a bug.
    function _checkSingleCall(address to, bytes memory data) internal view {
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

    /// @dev Big-endian 32 bytes starting at `offset`, the same byte layout `abi.encode` and
    ///      MultiSendCallOnly's own packed format both use for a `uint256`/`address`/length word.
    function _toUint256(bytes memory data, uint256 offset) private pure returns (uint256 value) {
        for (uint256 i = 0; i < 32; i++) {
            value = (value << 8) | uint8(data[offset + i]);
        }
    }

    function _toAddress(bytes memory data, uint256 offset) private pure returns (address value) {
        uint160 raw;
        for (uint256 i = 0; i < 20; i++) {
            raw = (raw << 8) | uint160(uint8(data[offset + i]));
        }
        value = address(raw);
    }

    function _slice(bytes memory data, uint256 start, uint256 len) private pure returns (bytes memory out) {
        out = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            out[i] = data[start + i];
        }
    }

    function _ceil32(uint256 length) private pure returns (uint256) {
        return (length + 31) & ~uint256(31);
    }
}
