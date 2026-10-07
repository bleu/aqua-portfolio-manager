// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AggregatorV3Interface} from "../src/interfaces/AggregatorV3Interface.sol";
import {OracleAdapter} from "../src/utils/OracleAdapter.sol";

/// @dev Feed mock with configurable answer, timestamp, and decimals.
contract MockAggregatorV3 is AggregatorV3Interface {
    int256 public answer;
    uint256 public updatedAt;
    uint8 private _decimals;
    uint80 public roundId = 1;
    uint80 public answeredInRound = 1;

    constructor(uint8 decimals_, int256 initialAnswer, uint256 initialUpdatedAt) {
        _decimals = decimals_;
        answer = initialAnswer;
        updatedAt = initialUpdatedAt;
    }

    function setAnswer(int256 newAnswer, uint256 newUpdatedAt) external {
        answer = newAnswer;
        updatedAt = newUpdatedAt;
    }

    function setRound(uint80 newRoundId, uint80 newAnsweredInRound) external {
        roundId = newRoundId;
        answeredInRound = newAnsweredInRound;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (roundId, answer, updatedAt, updatedAt, answeredInRound);
    }
}

/// @dev A 6-decimal ERC20 (e.g. USDC-like), since `ERC20Mock` is hardcoded to 18.
contract ERC20MockWithDecimals is ERC20 {
    uint8 private immutable _decimals;

    constructor(uint8 decimals_) ERC20("Mock", "MCK") {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}

contract OracleAdapterTest is Test {
    // See FixedPointMath.t.sol for why internal library calls need an external wrapper for
    // `vm.expectRevert` to intercept the revert at the right call depth.
    function _priceWad(OracleAdapter.PriceFeed memory config, OracleAdapter.Rounding rounding)
        external
        view
        returns (uint256)
    {
        return OracleAdapter.priceWad(config, rounding);
    }

    function _groupValueWad(address[] memory tokens, uint256[] memory balances, OracleAdapter.PriceFeed[] memory feeds)
        external
        view
        returns (uint256)
    {
        return OracleAdapter.groupValueWad(tokens, balances, feeds, OracleAdapter.Rounding.Down);
    }

    function _feed(MockAggregatorV3 mock, uint256 maxStaleness) internal pure returns (OracleAdapter.PriceFeed memory) {
        return OracleAdapter.PriceFeed({feed: AggregatorV3Interface(address(mock)), maxStaleness: maxStaleness});
    }

    function _requireSequencerUp(AggregatorV3Interface sequencerUptimeFeed) external view {
        OracleAdapter.requireSequencerUp(sequencerUptimeFeed);
    }

    function test_NormalizesEightDecimalFeedToWad() public {
        vm.warp(1_000_000);
        MockAggregatorV3 mock = new MockAggregatorV3(8, 2000e8, block.timestamp); // $2000.00000000
        uint256 price = OracleAdapter.priceWad(_feed(mock, 1 hours), OracleAdapter.Rounding.Down);
        assertEq(price, 2000e18);
    }

    function test_PassesThroughEighteenDecimalFeedUnchanged() public {
        vm.warp(1_000_000);
        MockAggregatorV3 mock = new MockAggregatorV3(18, 1e18, block.timestamp);
        uint256 price = OracleAdapter.priceWad(_feed(mock, 1 hours), OracleAdapter.Rounding.Down);
        assertEq(price, 1e18);
    }

    function test_ScalesDownFeedWithMoreThan18Decimals() public {
        vm.warp(1_000_000);
        MockAggregatorV3 mock = new MockAggregatorV3(24, 2000e24, block.timestamp); // $2000, 24 decimals
        uint256 price = OracleAdapter.priceWad(_feed(mock, 1 hours), OracleAdapter.Rounding.Down);
        assertEq(price, 2000e18);
    }

    function test_RevertsOnStalePrice() public {
        vm.warp(1_000_000);
        MockAggregatorV3 mock = new MockAggregatorV3(8, 2000e8, block.timestamp - 2 hours);

        vm.expectRevert(
            abi.encodeWithSelector(
                OracleAdapter.OracleAdapterStalePrice.selector, address(mock), block.timestamp - 2 hours, 1 hours
            )
        );
        this._priceWad(_feed(mock, 1 hours), OracleAdapter.Rounding.Down);
    }

    function test_AcceptsPriceExactlyAtStalenessThreshold() public {
        vm.warp(1_000_000);
        MockAggregatorV3 mock = new MockAggregatorV3(8, 2000e8, block.timestamp - 1 hours);
        uint256 price = OracleAdapter.priceWad(_feed(mock, 1 hours), OracleAdapter.Rounding.Down);
        assertEq(price, 2000e18);
    }

    function test_RevertsOnNonPositivePrice() public {
        vm.warp(1_000_000);
        MockAggregatorV3 mock = new MockAggregatorV3(8, 0, block.timestamp);

        vm.expectRevert(
            abi.encodeWithSelector(OracleAdapter.OracleAdapterInvalidPrice.selector, address(mock), int256(0))
        );
        this._priceWad(_feed(mock, 1 hours), OracleAdapter.Rounding.Down);
    }

    function test_RevertsOnNegativePrice() public {
        vm.warp(1_000_000);
        MockAggregatorV3 mock = new MockAggregatorV3(8, -1, block.timestamp);

        vm.expectRevert(
            abi.encodeWithSelector(OracleAdapter.OracleAdapterInvalidPrice.selector, address(mock), int256(-1))
        );
        this._priceWad(_feed(mock, 1 hours), OracleAdapter.Rounding.Down);
    }

    function test_RevertsOnIncompleteRound() public {
        vm.warp(1_000_000);
        MockAggregatorV3 mock = new MockAggregatorV3(8, 2000e8, block.timestamp);
        mock.setRound(5, 4);

        vm.expectRevert(
            abi.encodeWithSelector(
                OracleAdapter.OracleAdapterIncompleteRound.selector, address(mock), uint80(5), uint80(4)
            )
        );
        this._priceWad(_feed(mock, 1 hours), OracleAdapter.Rounding.Down);
    }

    function test_RevertsOnZeroRoundId() public {
        vm.warp(1_000_000);
        MockAggregatorV3 mock = new MockAggregatorV3(8, 2000e8, block.timestamp);
        mock.setRound(0, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                OracleAdapter.OracleAdapterIncompleteRound.selector, address(mock), uint80(0), uint80(0)
            )
        );
        this._priceWad(_feed(mock, 1 hours), OracleAdapter.Rounding.Down);
    }

    function test_AcceptsRoundWhereAnsweredInRoundExceedsRoundId() public {
        vm.warp(1_000_000);
        MockAggregatorV3 mock = new MockAggregatorV3(8, 2000e8, block.timestamp);
        mock.setRound(5, 6);
        uint256 price = OracleAdapter.priceWad(_feed(mock, 1 hours), OracleAdapter.Rounding.Down);
        assertEq(price, 2000e18);
    }

    function test_RequireSequencerUpRevertsWhenSequencerIsDown() public {
        vm.warp(1_000_000);
        MockAggregatorV3 sequencerFeed = new MockAggregatorV3(0, 1, block.timestamp - 2 hours); // answer 1 == down

        vm.expectRevert(
            abi.encodeWithSelector(OracleAdapter.OracleAdapterSequencerDown.selector, address(sequencerFeed))
        );
        this._requireSequencerUp(AggregatorV3Interface(address(sequencerFeed)));
    }

    function test_RequireSequencerUpRevertsWithinGracePeriodAfterRecovery() public {
        vm.warp(1_000_000);
        MockAggregatorV3 sequencerFeed = new MockAggregatorV3(0, 0, block.timestamp - 30 minutes);

        vm.expectRevert(
            abi.encodeWithSelector(
                OracleAdapter.OracleAdapterSequencerGracePeriodNotElapsed.selector,
                address(sequencerFeed),
                uint256(30 minutes),
                OracleAdapter.SEQUENCER_GRACE_PERIOD
            )
        );
        this._requireSequencerUp(AggregatorV3Interface(address(sequencerFeed)));
    }

    function test_RequireSequencerUpAcceptsExactlyAtGracePeriodThreshold() public {
        vm.warp(1_000_000);
        MockAggregatorV3 sequencerFeed = new MockAggregatorV3(0, 0, block.timestamp - 1 hours);
        OracleAdapter.requireSequencerUp(AggregatorV3Interface(address(sequencerFeed)));
    }

    function test_GroupValueSumsAcrossDifferentTokenAndFeedDecimals() public {
        vm.warp(1_000_000);
        // USDC-like: 6 token decimals, 8 feed decimals, $1.00 -- 15,000 USDC.
        ERC20MockWithDecimals usdc = new ERC20MockWithDecimals(6);
        MockAggregatorV3 usdcFeed = new MockAggregatorV3(8, 1e8, block.timestamp);
        // USDT-like: same shape, 5,000 USDT.
        ERC20MockWithDecimals usdt = new ERC20MockWithDecimals(6);
        MockAggregatorV3 usdtFeed = new MockAggregatorV3(8, 1e8, block.timestamp);

        address[] memory tokens = new address[](2);
        tokens[0] = address(usdc);
        tokens[1] = address(usdt);
        uint256[] memory balances = new uint256[](2);
        balances[0] = 15_000e6;
        balances[1] = 5_000e6;
        OracleAdapter.PriceFeed[] memory feeds = new OracleAdapter.PriceFeed[](2);
        feeds[0] = _feed(usdcFeed, 1 hours);
        feeds[1] = _feed(usdtFeed, 1 hours);

        uint256 totalValue = OracleAdapter.groupValueWad(tokens, balances, feeds, OracleAdapter.Rounding.Down);
        assertEq(totalValue, 20_000e18);
    }

    function test_GroupValueUsesFullPrecisionBalanceConversion() public {
        ERC20MockWithDecimals token = new ERC20MockWithDecimals(18);
        MockAggregatorV3 mock = new MockAggregatorV3(18, 1e18, block.timestamp);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        uint256[] memory balances = new uint256[](1);
        balances[0] = 1e60;
        OracleAdapter.PriceFeed[] memory feeds = new OracleAdapter.PriceFeed[](1);
        feeds[0] = _feed(mock, 1 hours);

        // The unscaled product 1e60 * 1e18 overflows, but its normalized value fits.
        assertEq(OracleAdapter.groupValueWad(tokens, balances, feeds, OracleAdapter.Rounding.Down), 1e60);
        assertEq(OracleAdapter.groupValueWad(tokens, balances, feeds, OracleAdapter.Rounding.Up), 1e60);
    }

    function testFuzz_GroupValueBoundsMixedDecimals(uint256 balanceA, uint256 balanceB) public {
        balanceA = bound(balanceA, 1, 1e24);
        balanceB = bound(balanceB, 1, 1e24);
        address[] memory tokens = new address[](2);
        tokens[0] = address(new ERC20MockWithDecimals(18));
        tokens[1] = address(new ERC20MockWithDecimals(24));
        uint256[] memory balances = new uint256[](2);
        balances[0] = balanceA;
        balances[1] = balanceB;
        OracleAdapter.PriceFeed[] memory feeds = new OracleAdapter.PriceFeed[](2);
        feeds[0] = _feed(new MockAggregatorV3(18, 0.5e18, block.timestamp), 1 hours);
        feeds[1] = _feed(new MockAggregatorV3(8, 0.75e8, block.timestamp), 1 hours);

        uint256 lower = OracleAdapter.groupValueWad(tokens, balances, feeds, OracleAdapter.Rounding.Down);
        uint256 upper = OracleAdapter.groupValueWad(tokens, balances, feeds, OracleAdapter.Rounding.Up);
        // Compare exact rational values at a common denominator, without rounded helpers.
        uint256 numerator = balanceA * 0.5e18 * 1e6 + balanceB * 0.75e18;
        assertLe(lower * 1e24, numerator);
        assertGe(upper * 1e24, numerator);
        assertLe(upper - lower, 2);
    }

    function test_FeedNormalizationRoundsInRequestedDirection() public {
        MockAggregatorV3 mock = new MockAggregatorV3(24, 1_999_999, block.timestamp);
        assertEq(OracleAdapter.priceWad(_feed(mock, 1 hours), OracleAdapter.Rounding.Down), 1);
        assertEq(OracleAdapter.priceWad(_feed(mock, 1 hours), OracleAdapter.Rounding.Up), 2);
    }

    function test_RevertsWhenPositivePriceNormalizesToZero() public {
        MockAggregatorV3 mock = new MockAggregatorV3(24, 999_999, block.timestamp);
        bytes memory expected =
            abi.encodeWithSelector(OracleAdapter.OracleAdapterInvalidPrice.selector, address(mock), int256(999_999));
        vm.expectRevert(expected);
        this._priceWad(_feed(mock, 1 hours), OracleAdapter.Rounding.Down);
        vm.expectRevert(expected);
        this._priceWad(_feed(mock, 1 hours), OracleAdapter.Rounding.Up);
    }

    function testFuzz_HighDecimalFeedBoundsPriceAndGroupValue(uint256 rawAnswer, uint256 balance) public {
        rawAnswer = bound(rawAnswer, 1e6, 1e24);
        balance = bound(balance, 1, 1e24);
        MockAggregatorV3 mock = new MockAggregatorV3(24, int256(rawAnswer), block.timestamp);
        OracleAdapter.PriceFeed memory feed = _feed(mock, 1 hours);
        uint256 priceDown = OracleAdapter.priceWad(feed, OracleAdapter.Rounding.Down);
        uint256 priceUp = OracleAdapter.priceWad(feed, OracleAdapter.Rounding.Up);
        assertLe(priceDown * 1e6, rawAnswer);
        assertGe(priceUp * 1e6, rawAnswer);
        assertLe(priceUp - priceDown, 1);

        address[] memory tokens = new address[](1);
        tokens[0] = address(new ERC20MockWithDecimals(24));
        uint256[] memory balances = new uint256[](1);
        balances[0] = balance;
        OracleAdapter.PriceFeed[] memory feeds = new OracleAdapter.PriceFeed[](1);
        feeds[0] = feed;
        uint256 lower = OracleAdapter.groupValueWad(tokens, balances, feeds, OracleAdapter.Rounding.Down);
        uint256 upper = OracleAdapter.groupValueWad(tokens, balances, feeds, OracleAdapter.Rounding.Up);
        // Raw feed and token units give the exact value balance * answer / 1e30.
        assertLe(lower * 1e30, balance * rawAnswer);
        assertGe(upper * 1e30, balance * rawAnswer);
    }

    function test_GroupValueRevertsIfAnyMemberFeedIsStale() public {
        ERC20MockWithDecimals tokenA = new ERC20MockWithDecimals(18);
        ERC20MockWithDecimals tokenB = new ERC20MockWithDecimals(18);
        vm.warp(1_000_000);
        MockAggregatorV3 freshFeed = new MockAggregatorV3(8, 1e8, block.timestamp);
        MockAggregatorV3 staleFeed = new MockAggregatorV3(8, 1e8, block.timestamp - 2 hours);

        address[] memory tokens = new address[](2);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);
        uint256[] memory balances = new uint256[](2);
        balances[0] = 100e18;
        balances[1] = 100e18;
        OracleAdapter.PriceFeed[] memory feeds = new OracleAdapter.PriceFeed[](2);
        feeds[0] = _feed(freshFeed, 1 hours);
        feeds[1] = _feed(staleFeed, 1 hours); // this member never moves in the swap, but still gates the trade

        vm.expectRevert(
            abi.encodeWithSelector(
                OracleAdapter.OracleAdapterStalePrice.selector, address(staleFeed), block.timestamp - 2 hours, 1 hours
            )
        );
        this._groupValueWad(tokens, balances, feeds);
    }

    function test_GroupValueRevertsOnLengthMismatch() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(0x1);
        uint256[] memory balances = new uint256[](2);
        OracleAdapter.PriceFeed[] memory feeds = new OracleAdapter.PriceFeed[](1);

        vm.expectRevert(abi.encodeWithSelector(OracleAdapter.OracleAdapterTokensFeedsLengthMismatch.selector));
        this._groupValueWad(tokens, balances, feeds);
    }
}
