// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {BasketScopeGuard} from "../src/BasketScopeGuard.sol";
import {IBasketScopeGuard} from "../src/interfaces/IBasketScopeGuard.sol";
import {Aqua} from "aqua/Aqua.sol";
import {Safe} from "safe-smart-account/contracts/Safe.sol";
import {SafeProxyFactory} from "safe-smart-account/contracts/proxies/SafeProxyFactory.sol";
import {Enum} from "safe-smart-account/contracts/libraries/Enum.sol";

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

        guard = new BasketScopeGuard(address(aqua), address(this), pmStrategyHash, tokens, basketIds);
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
        new BasketScopeGuard(address(aqua), address(this), pmStrategyHash, tokens, basketIds);
    }

    // ---------------------------------------------------------------------
    // Unit tests against the Guard's own check logic (checkTransaction)
    // ---------------------------------------------------------------------

    function _shipCalldata(bytes memory strategy, address[] memory tokens) internal pure returns (bytes memory) {
        uint256[] memory amounts = new uint256[](tokens.length);
        return abi.encodeCall(Aqua.ship, (address(0xAAAA), strategy, tokens, amounts));
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
            bool isPM = seed % 3 == 0;
            address[] memory tokens = _randomTokenSubset(seed, universe);
            bytes memory strategy = isPM ? pmStrategy : abi.encodePacked("random-strategy-", seed);
            bytes memory data = _shipCalldata(strategy, tokens);

            if (_predictedOutcome(isPM, tokens)) {
                guard.checkTransaction(
                    address(aqua),
                    0,
                    data,
                    Enum.Operation.Call,
                    0,
                    0,
                    0,
                    address(0),
                    payable(address(0)),
                    "",
                    address(0)
                );
            } else {
                vm.expectRevert();
                guard.checkTransaction(
                    address(aqua),
                    0,
                    data,
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
    }

    /// @dev Random length (0..universe.length, inclusive of the empty-list edge case) and random
    ///      order, with replacement -- a real `tokens` array could in principle repeat an entry,
    ///      and order determines which token becomes `CrossBasketStrategyForbidden`'s reference
    ///      basket (not the pass/fail outcome itself, which `_predictedOutcome` mirrors exactly).
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

    /// @dev Mirrors `BasketScopeGuard._check`'s own logic exactly (see that function): PM always
    ///      passes unconditionally; otherwise every token must belong to the same nonzero basket.
    function _predictedOutcome(bool isPM, address[] memory tokens) private view returns (bool) {
        if (isPM) return true;
        if (tokens.length == 0) return false;
        uint256 refBasket = guard.basketOf(tokens[0]);
        if (refBasket == 0) return false;
        for (uint256 i = 1; i < tokens.length; i++) {
            uint256 b = guard.basketOf(tokens[i]);
            if (b == 0 || b != refBasket) return false;
        }
        return true;
    }

    // ---------------------------------------------------------------------
    // Integration: a real deployed Safe, both the execTransaction path and
    // the module path, both actually calling the real Aqua contract.
    // ---------------------------------------------------------------------

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

    /// @dev Signs, but does NOT execute — so callers that need `vm.expectRevert()` to target
    ///      the real `execTransaction` call (not one of the view calls used to build the
    ///      signature) can sign first and call `execTransaction` directly right after.
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

        // Sign BEFORE arming expectRevert, so the very next call is the one that must revert —
        // getTransactionHash()/nonce() are view calls that would otherwise satisfy expectRevert's
        // "next call" prematurely (they never revert, but they *are* the next external call).
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
}
