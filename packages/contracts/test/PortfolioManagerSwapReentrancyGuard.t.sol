// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Test} from "forge-std/Test.sol";
import {Aqua} from "aqua/Aqua.sol";
import {TokenMock} from "@1inch/solidity-utils/contracts/mocks/TokenMock.sol";
import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";
import {MakerTraitsLib} from "swap-vm/libs/MakerTraits.sol";
import {TakerTraitsLib} from "swap-vm/libs/TakerTraits.sol";
import {SwapVM} from "swap-vm/SwapVM.sol";

import {PortfolioManagerRouter} from "../src/PortfolioManagerRouter.sol";
import {PortfolioManagerProgramBuilder} from "../src/utils/PortfolioManagerProgramBuilder.sol";
import {PortfolioManagerArgsCodec} from "../src/utils/PortfolioManagerArgsCodec.sol";
import {PortfolioManagerStrategyValidator} from "../src/PortfolioManagerStrategyValidator.sol";
import {PortfolioManagerTokenRegistry} from "../src/utils/PortfolioManagerTokenRegistry.sol";
import {PortfolioManagerFeedRegistry} from "../src/utils/PortfolioManagerFeedRegistry.sol";
import {MockAggregatorV3} from "./OracleAdapter.t.sol";

/// @notice BLEUDEV-449's regression test: Almanax flagged that a permissionless member token's
/// balanceOf()/decimals() could reenter this router mid-swap (e.g. to execute a nested fill
/// against a *different* order -- SwapVM's own reentrancy lock is per-orderHash, so it alone
/// would not catch that). This token attempts exactly that nested call. It cannot succeed: both
/// calls are made through IERC20/IERC20Metadata, interfaces that declare them `view`, so Solidity
/// compiles them as STATICCALL, and the EVM propagates that read-only context to every call this
/// token's own code makes in turn -- any state-changing attempt reverts with
/// StateChangeDuringStaticCall, with no bypass available to the token. See
/// PortfolioManagerSwap._groupValueWad's own doc comment for where this is relied upon.
contract ReentrantBalanceToken {
    PortfolioManagerRouter internal immutable ROUTER;
    ISwapVM.Order internal reentrantOrder;
    address internal reentrantTokenOut;
    bool internal attacked;

    constructor(PortfolioManagerRouter router) {
        ROUTER = router;
    }

    function configureAttack(ISwapVM.Order memory order, address tokenOut) external {
        reentrantOrder = order;
        reentrantTokenOut = tokenOut;
    }

    /// @dev Lets a control test skip the attack, to prove a revert in the attack test traces back
    ///      to the attack itself and not to some unrelated setup mistake.
    function skipAttack() external {
        attacked = true;
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    /// @dev The actual reentrancy attempt. Guarded by `attacked` purely so a legitimate second
    ///      read of this same balance (e.g. a retry) doesn't re-attack -- the nested call reverts
    ///      before this function would ever return normally either way.
    function balanceOf(address) external returns (uint256) {
        if (!attacked) {
            attacked = true;
            bytes memory takerData = TakerTraitsLib.build(
                TakerTraitsLib.Args({
                    taker: address(this),
                    isExactIn: true,
                    shouldUnwrapWeth: false,
                    isStrictThresholdAmount: false,
                    isFirstTransferFromTaker: false,
                    useTransferFromAndAquaPush: false,
                    threshold: "",
                    to: address(0),
                    deadline: 0,
                    hasPreTransferInCallback: false,
                    hasPreTransferOutCallback: false,
                    preTransferInHookData: "",
                    postTransferInHookData: "",
                    preTransferOutHookData: "",
                    postTransferOutHookData: "",
                    preTransferInCallbackData: "",
                    preTransferOutCallbackData: "",
                    instructionsArgs: "",
                    signature: ""
                })
            );
            // Reverts in the nested swap's own reentrancy lock (a state-changing write, blocked
            // by the static context this call inherited), so this contract never needs working
            // transfer semantics.
            ROUTER.swap(reentrantOrder, address(this), reentrantTokenOut, 1, takerData);
        }
        return 1_000_000e18;
    }
}

contract PortfolioManagerSwapReentrancyGuardTest is Test {
    uint256 internal constant INITIAL_BALANCE = 100_000e18;
    uint256 internal constant SWAP_AMOUNT = 1_000e18;
    uint32 internal constant DEFAULT_MAX_STALENESS = 1 hours;
    uint32 internal constant FEE_BPS = 1e9 / 100; // 1%

    Aqua internal aqua;
    PortfolioManagerRouter internal router;
    PortfolioManagerStrategyValidator internal strategyValidator;
    PortfolioManagerTokenRegistry internal tokenRegistry;
    PortfolioManagerFeedRegistry internal feedRegistry;
    ReentrantBalanceToken internal maliciousToken;
    TokenMock internal tokenB;
    MockAggregatorV3 internal feedA;
    MockAggregatorV3 internal feedB;

    address internal maker1 = vm.addr(0x1111);
    address internal maker2 = vm.addr(0x2222);

    PortfolioManagerArgsCodec.Group[] internal groups;

    function setUp() public {
        vm.warp(1_000_000);
        MockAggregatorV3 sequencerFeed = new MockAggregatorV3(0, 0, block.timestamp - 2 hours);

        aqua = new Aqua();
        tokenRegistry = new PortfolioManagerTokenRegistry();
        feedRegistry = new PortfolioManagerFeedRegistry(address(this));
        strategyValidator = new PortfolioManagerStrategyValidator(
            address(sequencerFeed), address(tokenRegistry), address(feedRegistry)
        );
        router = new PortfolioManagerRouter(
            address(aqua),
            address(0),
            address(this),
            "PM",
            "1",
            address(strategyValidator),
            address(sequencerFeed),
            address(tokenRegistry),
            address(feedRegistry)
        );

        maliciousToken = new ReentrantBalanceToken(router);
        tokenB = new TokenMock("Token B", "TKB");
        feedA = new MockAggregatorV3(18, 1e18, block.timestamp);
        feedB = new MockAggregatorV3(18, 1e18, block.timestamp);

        groups.push(_singleMemberGroup(0.5e18, address(maliciousToken), address(feedA)));
        groups.push(_singleMemberGroup(0.5e18, address(tokenB), address(feedB)));
    }

    function _singleMemberGroup(uint256 weight, address token, address feed)
        internal
        returns (PortfolioManagerArgsCodec.Group memory)
    {
        PortfolioManagerArgsCodec.Member[] memory members = new PortfolioManagerArgsCodec.Member[](1);
        members[0] = PortfolioManagerArgsCodec.Member({
            tokenIndex: tokenRegistry.register(token), feedIndex: feedRegistry.register(feed, DEFAULT_MAX_STALENESS)
        });
        return PortfolioManagerArgsCodec.Group({weight: weight, members: members});
    }

    function _orderFor(address maker) internal returns (ISwapVM.Order memory order) {
        bytes memory program = PortfolioManagerProgramBuilder.build(groups, FEE_BPS);
        order = MakerTraitsLib.build(
            MakerTraitsLib.Args({
                maker: maker,
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

    function _ship(ISwapVM.Order memory order, address maker) internal {
        tokenB.mint(maker, INITIAL_BALANCE);
        vm.prank(maker);
        tokenB.approve(address(aqua), type(uint256).max);

        address[] memory tokens = new address[](2);
        tokens[0] = address(maliciousToken);
        tokens[1] = address(tokenB);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = INITIAL_BALANCE;
        amounts[1] = INITIAL_BALANCE;

        strategyValidator.attestBuildParameters(order, tokens, new string[](0));
        vm.prank(maker);
        aqua.ship(address(router), abi.encode(order), tokens, amounts);
    }

    /// @notice A malicious member token's balanceOf() cannot reenter this router with a
    /// state-changing nested swap, even against a *different* order (different maker, so SwapVM's
    /// own per-orderHash lock would not itself catch this) -- the EVM's STATICCALL propagation
    /// blocks it regardless, with no reentrancy guard needed in this contract.
    function test_ReentrantSwapAttemptFromBalanceOfCannotChangeState() public {
        ISwapVM.Order memory order1 = _orderFor(maker1);
        ISwapVM.Order memory order2 = _orderFor(maker2);
        _ship(order1, maker1);
        _ship(order2, maker2);

        maliciousToken.configureAttack(order2, address(tokenB));

        bytes memory takerData = TakerTraitsLib.build(
            TakerTraitsLib.Args({
                taker: address(this),
                isExactIn: true,
                shouldUnwrapWeth: false,
                isStrictThresholdAmount: false,
                isFirstTransferFromTaker: false,
                useTransferFromAndAquaPush: false,
                threshold: "",
                to: address(0),
                deadline: 0,
                hasPreTransferInCallback: false,
                hasPreTransferOutCallback: false,
                preTransferInHookData: "",
                postTransferInHookData: "",
                preTransferOutHookData: "",
                postTransferOutHookData: "",
                preTransferInCallbackData: "",
                preTransferOutCallbackData: "",
                instructionsArgs: "",
                signature: ""
            })
        );

        // No revert selector to match: a STATICCALL violation is a raw EVM halt with no return
        // data, not a Solidity-level revert reason -- a bare expectRevert() is the correct way to
        // assert this against a call that is still, overall, expected to fail.
        vm.expectRevert();
        router.swap(order1, address(maliciousToken), address(tokenB), SWAP_AMOUNT, takerData);
    }

    /// @notice Control for the test above: the exact same setup, minus the attack, gets all the
    /// way through pricing (reading the malicious token's balanceOf() without incident) and fails
    /// only at final settlement, because this test's minimal taker data never actually pushes
    /// funds -- a distinctly different, specific error from the attack test's raw EVM halt. That
    /// contrast is the proof: the attack test's revert traces to the reentrancy attempt itself,
    /// not to some unrelated mistake shared by both tests' setup.
    function test_SwapWithoutAttackFailsOnlyAtSettlementNotAtPricing() public {
        ISwapVM.Order memory order1 = _orderFor(maker1);
        ISwapVM.Order memory order2 = _orderFor(maker2);
        _ship(order1, maker1);
        _ship(order2, maker2);

        maliciousToken.configureAttack(order2, address(tokenB));
        maliciousToken.skipAttack();

        bytes memory takerData = TakerTraitsLib.build(
            TakerTraitsLib.Args({
                taker: address(this),
                isExactIn: true,
                shouldUnwrapWeth: false,
                isStrictThresholdAmount: false,
                isFirstTransferFromTaker: false,
                useTransferFromAndAquaPush: false,
                threshold: "",
                to: address(0),
                deadline: 0,
                hasPreTransferInCallback: false,
                hasPreTransferOutCallback: false,
                preTransferInHookData: "",
                postTransferInHookData: "",
                preTransferOutHookData: "",
                postTransferOutHookData: "",
                preTransferInCallbackData: "",
                preTransferOutCallbackData: "",
                instructionsArgs: "",
                signature: ""
            })
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                SwapVM.AquaBalanceInsufficientAfterTakerPush.selector, INITIAL_BALANCE, INITIAL_BALANCE, SWAP_AMOUNT, 0
            )
        );
        router.swap(order1, address(maliciousToken), address(tokenB), SWAP_AMOUNT, takerData);
    }
}
