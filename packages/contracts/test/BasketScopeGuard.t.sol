// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {BasketScopeGuard} from "../src/BasketScopeGuard.sol";
import {IBasketScopeGuard} from "../src/interfaces/IBasketScopeGuard.sol";
import {Aqua} from "aqua/Aqua.sol";
import {Safe} from "safe-smart-account/contracts/Safe.sol";
import {SafeProxyFactory} from "safe-smart-account/contracts/proxies/SafeProxyFactory.sol";
import {Enum} from "safe-smart-account/contracts/libraries/Enum.sol";
import {MultiSendCallOnly} from "safe-smart-account/contracts/libraries/MultiSendCallOnly.sol";

/// @dev Minimal module that just forwards one call through `execTransactionFromModule`,
///      so the test can exercise the Guard's `checkModuleTransaction` path for real.
contract ForwardingModule {
    function forward(Safe safe, address to, bytes memory data) external returns (bool) {
        return safe.execTransactionFromModule(to, 0, data, Enum.Operation.Call);
    }
}

contract BasketScopeGuardTest is Test {
    Aqua internal aqua;
    BasketScopeGuard internal guard;

    address internal tokenA = address(0xA11CE);
    address internal tokenB = address(0xB0B);
    address internal tokenC = address(0xC0FFEE);
    address internal tokenD = address(0xD00D);
    address internal tokenF = address(0xF00D); // outside every declared basket

    bytes internal pmStrategy = bytes("PM STRATEGY: weighted curve, groups={A,B},{C,D}, weights=50/50");
    bytes32 internal pmStrategyHash;
    address internal constant TRUSTED_PM_ROUTER = address(0xAAAA);

    function setUp() public {
        aqua = new Aqua();
        pmStrategyHash = keccak256(pmStrategy);

        address[] memory tokens = new address[](4);
        tokens[0] = tokenA;
        tokens[1] = tokenB;
        tokens[2] = tokenC;
        tokens[3] = tokenD;

        uint256[] memory basketIds = new uint256[](4);
        basketIds[0] = 1;
        basketIds[1] = 1;
        basketIds[2] = 2;
        basketIds[3] = 2;

        guard = new BasketScopeGuard(address(aqua), address(this), pmStrategyHash, TRUSTED_PM_ROUTER, tokens, basketIds);
    }

    // ---------------------------------------------------------------------
    // Constructor validation
    // ---------------------------------------------------------------------

    function test_RevertsOnTokenBasketLengthMismatch() public {
        address[] memory tokens = new address[](2);
        tokens[0] = tokenA;
        tokens[1] = tokenB;

        uint256[] memory basketIds = new uint256[](1);
        basketIds[0] = 1;

        vm.expectRevert(IBasketScopeGuard.TokenBasketLengthMismatch.selector);
        new BasketScopeGuard(address(aqua), address(this), pmStrategyHash, TRUSTED_PM_ROUTER, tokens, basketIds);
    }

    // ---------------------------------------------------------------------
    // Unit tests against the Guard's own check logic (checkTransaction)
    // ---------------------------------------------------------------------

    function _shipCalldata(bytes memory strategy, address[] memory tokens) internal pure returns (bytes memory) {
        return _shipCalldata(TRUSTED_PM_ROUTER, strategy, tokens);
    }

    function _shipCalldata(address app, bytes memory strategy, address[] memory tokens)
        internal
        pure
        returns (bytes memory)
    {
        uint256[] memory amounts = new uint256[](tokens.length);
        return abi.encodeCall(Aqua.ship, (app, strategy, tokens, amounts));
    }

    function test_AllowsPmStrategyEvenAcrossBaskets() public view {
        address[] memory tokens = new address[](4);
        tokens[0] = tokenA;
        tokens[1] = tokenB;
        tokens[2] = tokenC;
        tokens[3] = tokenD;

        guard.checkTransaction(
            address(aqua),
            0,
            _shipCalldata(pmStrategy, tokens),
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            "",
            address(0)
        );
        // no revert = pass
    }

    /// @dev The trusted strategy bytes are publicly recoverable from Aqua's own Shipped event --
    ///      replaying them against a different app must not grant the cross-basket exemption.
    function test_RevertsOnTrustedStrategyReplayedAgainstAnotherApp() public {
        address[] memory tokens = new address[](4);
        tokens[0] = tokenA;
        tokens[1] = tokenB;
        tokens[2] = tokenC;
        tokens[3] = tokenD;

        vm.expectRevert(abi.encodeWithSelector(IBasketScopeGuard.CrossBasketStrategyForbidden.selector, tokenA, tokenC));
        guard.checkTransaction(
            address(aqua),
            0,
            _shipCalldata(address(0xBEEF), pmStrategy, tokens),
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            "",
            address(0)
        );
    }

    /// @dev Even the real router can't ship the trusted strategy against an empty token list.
    function test_RevertsOnTrustedStrategyWithEmptyTokenList() public {
        address[] memory tokens = new address[](0);

        vm.expectRevert(IBasketScopeGuard.EmptyTokenList.selector);
        guard.checkTransaction(
            address(aqua),
            0,
            _shipCalldata(pmStrategy, tokens),
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            "",
            address(0)
        );
    }

    function test_AllowsSingleBasketStrategy() public view {
        address[] memory tokens = new address[](2);
        tokens[0] = tokenA;
        tokens[1] = tokenB;

        guard.checkTransaction(
            address(aqua),
            0,
            _shipCalldata("some other strategy", tokens),
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            "",
            address(0)
        );
    }

    function test_RevertsOnCrossBasketStrategy() public {
        address[] memory tokens = new address[](2);
        tokens[0] = tokenA; // basket 1
        tokens[1] = tokenC; // basket 2

        vm.expectRevert(abi.encodeWithSelector(IBasketScopeGuard.CrossBasketStrategyForbidden.selector, tokenA, tokenC));
        guard.checkTransaction(
            address(aqua),
            0,
            _shipCalldata("some other strategy", tokens),
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            "",
            address(0)
        );
    }

    function test_RevertsOnTokenOutsideUniverse() public {
        address[] memory tokens = new address[](2);
        tokens[0] = tokenA;
        tokens[1] = tokenF; // not in any basket

        vm.expectRevert(abi.encodeWithSelector(IBasketScopeGuard.TokenNotInAnyBasket.selector, tokenF));
        guard.checkTransaction(
            address(aqua),
            0,
            _shipCalldata("some other strategy", tokens),
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            "",
            address(0)
        );
    }

    function test_RevertsOnEmptyTokenList() public {
        address[] memory tokens = new address[](0);

        vm.expectRevert(IBasketScopeGuard.EmptyTokenList.selector);
        guard.checkTransaction(
            address(aqua),
            0,
            _shipCalldata("some other strategy", tokens),
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            "",
            address(0)
        );
    }

    function test_IgnoresCallsToOtherTargets() public view {
        address[] memory tokens = new address[](2);
        tokens[0] = tokenA;
        tokens[1] = tokenC; // would be cross-basket, but target isn't Aqua

        guard.checkTransaction(
            address(0xDEAD),
            0,
            _shipCalldata("some other strategy", tokens),
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            "",
            address(0)
        );
    }

    function test_IgnoresNonShipAquaCalls() public view {
        bytes memory dockCall =
            abi.encodeWithSignature("dock(address,bytes32,address[])", address(0xAAAA), bytes32(0), new address[](0));

        guard.checkTransaction(
            address(aqua), 0, dockCall, Enum.Operation.Call, 0, 0, 0, address(0), payable(address(0)), "", address(0)
        );
    }

    // ---------------------------------------------------------------------
    // Fuzz: cross-strategy invariant under randomized inputs
    // ---------------------------------------------------------------------

    /// @notice Fuzzes randomized PM/non-PM strategy mixes, token subsets, and lengths against
    /// `_check`'s stateless invariant, beyond the hand-picked scenarios above.
    /// @dev Checks only the allow path: the property is one-way (never wrongly allow a
    ///      cross-basket strategy), so a revert needs no prediction. `_isSafe` stays independent
    ///      of `_check`'s own branch structure by construction.
    function testFuzz_CrossStrategyInvariantHoldsUnderRandomizedTradeSequences(uint256 seed) public {
        address[] memory universe = new address[](5);
        universe[0] = tokenA; // basket 1
        universe[1] = tokenB; // basket 1
        universe[2] = tokenC; // basket 2
        universe[3] = tokenD; // basket 2
        universe[4] = tokenF; // outside every basket

        uint256 numMoves = bound(uint256(keccak256(abi.encode(seed, "moves"))), 3, 10);
        for (uint256 i = 0; i < numMoves; i++) {
            seed = uint256(keccak256(abi.encode(seed, i)));
            bool isPm = seed % 3 == 0;
            address[] memory tokens = _randomTokenSubset(seed, universe);
            bytes memory strategy = isPm ? pmStrategy : abi.encodePacked("random-strategy-", seed);
            bytes memory data = _shipCalldata(strategy, tokens);

            try guard.checkTransaction(
                address(aqua), 0, data, Enum.Operation.Call, 0, 0, 0, address(0), payable(address(0)), "", address(0)
            ) {
                assertTrue(_isSafe(isPm, tokens), "guard allowed an unsafe strategy through");
            } catch {
                // A revert is always an acceptable outcome here -- only an unsafe pass is a bug.
            }
        }
    }

    /// @dev Sample with replacement, including empty lists. Token order changes the error reference token, not acceptance.
    function _randomTokenSubset(uint256 seed, address[] memory universe)
        private
        pure
        returns (address[] memory tokens)
    {
        uint256 len = bound(uint256(keccak256(abi.encode(seed, "len"))), 0, universe.length);
        tokens = new address[](len);
        for (uint256 i = 0; i < len; i++) {
            uint256 idx = uint256(keccak256(abi.encode(seed, "pick", i))) % universe.length;
            tokens[i] = universe[idx];
        }
    }

    /// @dev The safety property itself (ADR-0011): every token shares one basket, none is
    ///      undeclared. Deliberately shaped differently from `_check`'s own "compare every token
    ///      to tokens[0]" loop -- counts distinct nonzero basket IDs instead -- so a bug specific
    ///      to that comparison pattern (e.g. the wrong reference index) is less likely to be
    ///      replicated here by construction, not just by not looking at `_check` while writing
    ///      this. Only ever invoked on the non-revert path (see the fuzz test's own doc comment).
    function _isSafe(bool isPm, address[] memory tokens) private view returns (bool) {
        if (isPm) return true;
        if (tokens.length == 0) return false;

        uint256[] memory distinctBaskets = new uint256[](tokens.length);
        uint256 distinctCount;
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 b = guard.basketOf(tokens[i]);
            if (b == 0) return false;

            bool seen;
            for (uint256 j = 0; j < distinctCount; j++) {
                if (distinctBaskets[j] == b) {
                    seen = true;
                    break;
                }
            }
            if (!seen) distinctBaskets[distinctCount++] = b;
        }
        return distinctCount == 1;
    }

    // Safe transaction and module integration.

    function _deploySafeWithOwner(uint256 ownerPk) internal returns (Safe safe, address owner) {
        owner = vm.addr(ownerPk);
        Safe singleton = new Safe();
        SafeProxyFactory factory = new SafeProxyFactory();

        address[] memory owners = new address[](1);
        owners[0] = owner;

        bytes memory setupData =
            abi.encodeCall(Safe.setup, (owners, 1, address(0), "", address(0), address(0), 0, payable(address(0))));

        safe = Safe(payable(address(factory.createProxyWithNonce(address(singleton), setupData, 0))));
    }

    /// @dev Sign before expectRevert so nonce and hash reads do not consume its next-call expectation.
    function _signFor(Safe safe, uint256 ownerPk, address to, bytes memory data)
        internal
        view
        returns (bytes memory signature)
    {
        bytes32 txHash = safe.getTransactionHash(
            to, 0, data, Enum.Operation.Call, 0, 0, 0, address(0), address(0), safe.nonce()
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, txHash);
        signature = abi.encodePacked(r, s, v);
    }

    function _execViaOwner(Safe safe, uint256 ownerPk, address to, bytes memory data) internal returns (bool) {
        bytes memory signature = _signFor(safe, ownerPk, to, data);
        return
            safe.execTransaction(to, 0, data, Enum.Operation.Call, 0, 0, 0, address(0), payable(address(0)), signature);
    }

    function test_Integration_SafeBlocksCrossBasketShipViaExecTransaction() public {
        uint256 ownerPk = 0xA11CE0001;
        (Safe safe,) = _deploySafeWithOwner(ownerPk);

        bool setGuardOk =
            _execViaOwner(safe, ownerPk, address(safe), abi.encodeWithSignature("setGuard(address)", address(guard)));
        assertTrue(setGuardOk, "setGuard should succeed");

        address[] memory tokens = new address[](2);
        tokens[0] = tokenA; // basket 1
        tokens[1] = tokenC; // basket 2
        bytes memory shipData = _shipCalldata("attacker strategy", tokens);

        bytes memory signature = _signFor(safe, ownerPk, address(aqua), shipData);

        vm.expectRevert();
        safe.execTransaction(
            address(aqua), 0, shipData, Enum.Operation.Call, 0, 0, 0, address(0), payable(address(0)), signature
        );
    }

    function test_Integration_SafeAllowsWithinBasketShipViaExecTransaction() public {
        uint256 ownerPk = 0xA11CE0002;
        (Safe safe,) = _deploySafeWithOwner(ownerPk);

        _execViaOwner(safe, ownerPk, address(safe), abi.encodeWithSignature("setGuard(address)", address(guard)));

        address[] memory tokens = new address[](2);
        tokens[0] = tokenA;
        tokens[1] = tokenB;

        bool ok =
            _execViaOwner(safe, ownerPk, address(aqua), _shipCalldata("some legit single-basket strategy", tokens));
        assertTrue(ok, "single-basket ship should succeed through a guarded Safe");
    }

    function test_Integration_SafeAllowsPmStrategyAcrossBasketsViaExecTransaction() public {
        uint256 ownerPk = 0xA11CE0003;
        (Safe safe,) = _deploySafeWithOwner(ownerPk);

        _execViaOwner(safe, ownerPk, address(safe), abi.encodeWithSignature("setGuard(address)", address(guard)));

        address[] memory tokens = new address[](4);
        tokens[0] = tokenA;
        tokens[1] = tokenB;
        tokens[2] = tokenC;
        tokens[3] = tokenD;

        bool ok = _execViaOwner(safe, ownerPk, address(aqua), _shipCalldata(pmStrategy, tokens));
        assertTrue(ok, "PM's own strategy should be allowed to span baskets through a guarded Safe");
    }

    function test_Integration_ModuleGuardBlocksCrossBasketShip() public {
        uint256 ownerPk = 0xA11CE0004;
        (Safe safe,) = _deploySafeWithOwner(ownerPk);
        ForwardingModule module = new ForwardingModule();

        _execViaOwner(safe, ownerPk, address(safe), abi.encodeWithSignature("enableModule(address)", address(module)));
        _execViaOwner(safe, ownerPk, address(safe), abi.encodeWithSignature("setModuleGuard(address)", address(guard)));

        address[] memory tokens = new address[](2);
        tokens[0] = tokenA;
        tokens[1] = tokenC;

        vm.expectRevert();
        module.forward(safe, address(aqua), _shipCalldata("attacker strategy via module", tokens));
    }

    function test_Integration_ModuleGuardAllowsWithinBasketShip() public {
        uint256 ownerPk = 0xA11CE0005;
        (Safe safe,) = _deploySafeWithOwner(ownerPk);
        ForwardingModule module = new ForwardingModule();

        _execViaOwner(safe, ownerPk, address(safe), abi.encodeWithSignature("enableModule(address)", address(module)));
        _execViaOwner(safe, ownerPk, address(safe), abi.encodeWithSignature("setModuleGuard(address)", address(guard)));

        address[] memory tokens = new address[](2);
        tokens[0] = tokenC;
        tokens[1] = tokenD;

        bool ok = module.forward(safe, address(aqua), _shipCalldata("legit strategy via module", tokens));
        assertTrue(ok, "single-basket ship via module should succeed once the module guard is installed");
    }

    // ---------------------------------------------------------------------
    // One-level MultiSend unwrapping.

    /// @dev Must match BasketScopeGuard.sol's own hardcoded constants exactly -- there's no public
    ///      getter for them (minimal surface on the real contract), so the test re-declares the
    ///      same literals on purpose, not by import.
    address internal constant MULTISEND_CALL_ONLY_CANONICAL = 0x40A2aCCbd92BCA938b02010E17A5b8929b49130D;
    address internal constant MULTISEND_CALL_ONLY_SAFE_WALLET = 0xA83c336B20401Af773B6219BA5027174338D1836;

    /// @dev Places a real, working MultiSendCallOnly at one of the guard's two hardcoded trusted
    ///      addresses -- vm.etch, not a fork, since a freshly-deployed instance in a local test
    ///      would land at whatever address CREATE gives it, never the real mainnet address the
    ///      guard actually trusts. Copies real bytecode (a fresh deployment's own .code), not a
    ///      hand-written stand-in, so these tests exercise MultiSendCallOnly's real packing
    ///      semantics, not an assumption about them.
    function _etchMultiSendCallOnlyAt(address target) internal {
        vm.etch(target, address(new MultiSendCallOnly()).code);
    }

    function _packMultiSendEntry(address to, bytes memory data) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(0), to, uint256(0), data.length, data);
    }

    function _signForDelegateCall(Safe safe, uint256 ownerPk, address to, bytes memory data)
        internal
        view
        returns (bytes memory signature)
    {
        bytes32 txHash = safe.getTransactionHash(
            to, 0, data, Enum.Operation.DelegateCall, 0, 0, 0, address(0), address(0), safe.nonce()
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, txHash);
        signature = abi.encodePacked(r, s, v);
    }

    function _execMultiSendBatchViaOwner(Safe safe, uint256 ownerPk, address relay, bytes memory packedEntries)
        internal
        returns (bool)
    {
        bytes memory multiSendData = abi.encodeCall(MultiSendCallOnly.multiSend, (packedEntries));
        bytes memory signature = _signForDelegateCall(safe, ownerPk, relay, multiSendData);
        return safe.execTransaction(
            relay, 0, multiSendData, Enum.Operation.DelegateCall, 0, 0, 0, address(0), payable(address(0)), signature
        );
    }

    /// @dev Signs before returning, not inside a vm.expectRevert()-adjacent call -- see _signFor's
    ///      own comment above: signing reads the Safe's nonce and hash via view calls that would
    ///      otherwise consume vm.expectRevert()'s "next call" themselves instead of the real
    ///      execTransaction this is actually testing.
    function _prepareMultiSendBatch(Safe safe, uint256 ownerPk, address relay, bytes memory packedEntries)
        internal
        view
        returns (bytes memory multiSendData, bytes memory signature)
    {
        multiSendData = abi.encodeCall(MultiSendCallOnly.multiSend, (packedEntries));
        signature = _signForDelegateCall(safe, ownerPk, relay, multiSendData);
    }

    function test_Integration_BlocksCrossBasketShipHiddenInsideMultiSendBatch() public {
        _etchMultiSendCallOnlyAt(MULTISEND_CALL_ONLY_CANONICAL);
        uint256 ownerPk = 0xA11CE0006;
        (Safe safe,) = _deploySafeWithOwner(ownerPk);
        _execViaOwner(safe, ownerPk, address(safe), abi.encodeWithSignature("setGuard(address)", address(guard)));

        address[] memory tokens = new address[](2);
        tokens[0] = tokenA; // basket 1
        tokens[1] = tokenC; // basket 2
        bytes memory packed = _packMultiSendEntry(address(aqua), _shipCalldata("attacker strategy via batch", tokens));
        (bytes memory multiSendData, bytes memory signature) =
            _prepareMultiSendBatch(safe, ownerPk, MULTISEND_CALL_ONLY_CANONICAL, packed);

        vm.expectRevert();
        safe.execTransaction(
            MULTISEND_CALL_ONLY_CANONICAL,
            0,
            multiSendData,
            Enum.Operation.DelegateCall,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            signature
        );
    }

    function test_Integration_AllowsWithinBasketShipInsideMultiSendBatch() public {
        _etchMultiSendCallOnlyAt(MULTISEND_CALL_ONLY_CANONICAL);
        uint256 ownerPk = 0xA11CE0007;
        (Safe safe,) = _deploySafeWithOwner(ownerPk);
        _execViaOwner(safe, ownerPk, address(safe), abi.encodeWithSignature("setGuard(address)", address(guard)));

        address[] memory tokens = new address[](2);
        tokens[0] = tokenA;
        tokens[1] = tokenB;
        bytes memory packed = _packMultiSendEntry(address(aqua), _shipCalldata("legit strategy via batch", tokens));

        bool ok = _execMultiSendBatchViaOwner(safe, ownerPk, MULTISEND_CALL_ONLY_CANONICAL, packed);
        assertTrue(ok, "single-basket ship inside a trusted-relay batch should succeed");
    }

    function test_Integration_AllowsPmStrategyAcrossBasketsInsideMultiSendBatch() public {
        _etchMultiSendCallOnlyAt(MULTISEND_CALL_ONLY_CANONICAL);
        uint256 ownerPk = 0xA11CE0008;
        (Safe safe,) = _deploySafeWithOwner(ownerPk);
        _execViaOwner(safe, ownerPk, address(safe), abi.encodeWithSignature("setGuard(address)", address(guard)));

        address[] memory tokens = new address[](4);
        tokens[0] = tokenA;
        tokens[1] = tokenB;
        tokens[2] = tokenC;
        tokens[3] = tokenD;
        bytes memory packed = _packMultiSendEntry(address(aqua), _shipCalldata(pmStrategy, tokens));

        bool ok = _execMultiSendBatchViaOwner(safe, ownerPk, MULTISEND_CALL_ONLY_CANONICAL, packed);
        assertTrue(ok, "PM's own strategy should be allowed to span baskets inside a trusted-relay batch too");
    }

    /// @dev The second trusted address (Safe{Wallet}'s own deployed MultiSendCallOnly instance,
    ///      confirmed via Sourcify to be the exact same source) gets the same real protection,
    ///      not just the canonical address -- this is the one that matters for a real batch this
    ///      app's own users actually produce.
    function test_Integration_BlocksCrossBasketShipViaSafeWalletsOwnMultiSendInstance() public {
        _etchMultiSendCallOnlyAt(MULTISEND_CALL_ONLY_SAFE_WALLET);
        uint256 ownerPk = 0xA11CE0009;
        (Safe safe,) = _deploySafeWithOwner(ownerPk);
        _execViaOwner(safe, ownerPk, address(safe), abi.encodeWithSignature("setGuard(address)", address(guard)));

        address[] memory tokens = new address[](2);
        tokens[0] = tokenA;
        tokens[1] = tokenC;
        bytes memory packed = _packMultiSendEntry(address(aqua), _shipCalldata("attacker strategy via batch", tokens));
        (bytes memory multiSendData, bytes memory signature) =
            _prepareMultiSendBatch(safe, ownerPk, MULTISEND_CALL_ONLY_SAFE_WALLET, packed);

        vm.expectRevert();
        safe.execTransaction(
            MULTISEND_CALL_ONLY_SAFE_WALLET,
            0,
            multiSendData,
            Enum.Operation.DelegateCall,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            signature
        );
    }

    /// @dev Deliberately out of scope, per this contract's own top doc comment: a batch routed
    ///      through an address the guard doesn't recognize passes through exactly like any other
    ///      untrusted target, cross-basket ship buried inside it or not.
    function test_IgnoresBatchFromAnUntrustedRelayAddress() public view {
        address untrustedRelay = address(0xBADBAD);
        address[] memory tokens = new address[](2);
        tokens[0] = tokenA;
        tokens[1] = tokenC;
        bytes memory packed =
            _packMultiSendEntry(address(aqua), _shipCalldata("attacker strategy via unknown relay", tokens));
        bytes memory multiSendData = abi.encodeCall(MultiSendCallOnly.multiSend, (packed));

        // Does not revert -- the guard never even looks inside, since `untrustedRelay` isn't one
        // of its two trusted addresses.
        guard.checkTransaction(
            untrustedRelay,
            0,
            multiSendData,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            "",
            address(0)
        );
    }

    /// @dev Pins the explicitly-accepted gap from this contract's own top doc comment: a second,
    ///      nested batch (a trusted relay's own entry itself targeting a trusted relay again) is
    ///      not unwrapped a second time. This must NOT revert, even though the cross-basket ship
    ///      really is in there two levels deep -- proving the guard stops at exactly one level
    ///      rather than silently doing something unexpected (infinite loop, wrong revert reason)
    ///      when it meets this shape.
    function test_DoesNotRecurseIntoASecondNestedMultiSendBatch() public view {
        address[] memory tokens = new address[](2);
        tokens[0] = tokenA;
        tokens[1] = tokenC;
        bytes memory innerPacked =
            _packMultiSendEntry(address(aqua), _shipCalldata("attacker strategy two levels deep", tokens));
        bytes memory innerMultiSendData = abi.encodeCall(MultiSendCallOnly.multiSend, (innerPacked));

        // The outer batch's one entry targets a trusted relay address again -- from the outer
        // unwrap's point of view this inner entry is just an ordinary call to AQUA? no: to a
        // trusted relay, which `_checkSingleCall` (not `_check`) never re-unwraps.
        bytes memory outerPacked = _packMultiSendEntry(MULTISEND_CALL_ONLY_SAFE_WALLET, innerMultiSendData);
        bytes memory outerMultiSendData = abi.encodeCall(MultiSendCallOnly.multiSend, (outerPacked));

        guard.checkTransaction(
            MULTISEND_CALL_ONLY_CANONICAL,
            0,
            outerMultiSendData,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            "",
            address(0)
        );
    }

    /// @dev The exact attack class Zodiac Roles Modifier's own MultiSendUnwrapper.sol guards
    ///      against: a declared `bytes` length shorter than the real padded data would make this
    ///      check parse different bytes than MultiSendCallOnly's own assembly loop (which walks by
    ///      real offsets, not the declared length) actually executes on-chain.
    function test_RevertsOnMultiSendHeaderLengthMismatch() public {
        bytes memory packed = _packMultiSendEntry(address(aqua), _shipCalldata("irrelevant", new address[](0)));
        bytes memory multiSendData = abi.encodeCall(MultiSendCallOnly.multiSend, (packed));

        // Corrupt the declared length word (byte offset 36, right after the selector + the fixed
        // 0x20 offset word) to claim zero bytes -- a drastic, unambiguous mismatch against the
        // real payload (ceil32(0) can never equal ceil32(a nonzero length) at any alignment,
        // unlike a +1 corruption, which can silently land on the same 32-byte-rounded value).
        assembly {
            mstore(add(multiSendData, add(0x20, 36)), 0)
        }

        vm.expectRevert(BasketScopeGuard.MalformedMultiSendHeader.selector);
        guard.checkTransaction(
            MULTISEND_CALL_ONLY_CANONICAL,
            0,
            multiSendData,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            "",
            address(0)
        );
    }

    function test_RevertsOnMultiSendBodyWithTruncatedEntry() public {
        // A well-formed header around a body that's too short for the one entry it claims to
        // hold: this entry's own declared data length reaches past the end of the real buffer.
        bytes memory truncated = abi.encodePacked(uint8(0), address(aqua), uint256(0), uint256(1_000_000));
        bytes memory multiSendData = abi.encodeCall(MultiSendCallOnly.multiSend, (truncated));

        vm.expectRevert(BasketScopeGuard.MalformedMultiSendBody.selector);
        guard.checkTransaction(
            MULTISEND_CALL_ONLY_CANONICAL,
            0,
            multiSendData,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            "",
            address(0)
        );
    }
}
