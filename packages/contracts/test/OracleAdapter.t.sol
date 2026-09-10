// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AggregatorV3Interface} from "../src/interfaces/AggregatorV3Interface.sol";
import {OracleAdapter} from "../src/OracleAdapter.sol";

/// @dev Settable Chainlink-style mock -- `answer`/`updatedAt`/`decimals` are all adjustable
///      per-test, unlike a real feed, so staleness and decimal-normalization can be exercised
///      directly rather than waiting on real chain time.
contract MockAggregatorV3 is AggregatorV3Interface {
    int256 public answer;
    uint256 public updatedAt;
    uint8 private _decimals;

    constructor(uint8 decimals_, int256 initialAnswer, uint256 initialUpdatedAt) {
        _decimals = decimals_;
        answer = initialAnswer;
        updatedAt = initialUpdatedAt;
    }

    function setAnswer(int256 newAnswer, uint256 newUpdatedAt) external {
        answer = newAnswer;
        updatedAt = newUpdatedAt;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, answer, updatedAt, updatedAt, 1);
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
    function _priceWad(OracleAdapter.PriceFeed memory config) external view returns (uint256) {
        return OracleAdapter.priceWad(config);
    }

    function _groupValueWad(address[] memory tokens, uint256[] memory balances, OracleAdapter.PriceFeed[] memory feeds)
        external
        view
        returns (uint256)
    {
        return OracleAdapter.groupValueWad(tokens, balances, feeds);
    }

    function _feed(MockAggregatorV3 mock, uint256 maxStaleness) internal pure returns (OracleAdapter.PriceFeed memory) {
        return OracleAdapter.PriceFeed({feed: AggregatorV3Interface(address(mock)), maxStaleness: maxStaleness});
    }

    function test_NormalizesEightDecimalFeedToWad() public {
        vm.warp(1_000_000);
        MockAggregatorV3 mock = new MockAggregatorV3(8, 2000e8, block.timestamp); // $2000.00000000
        uint256 price = OracleAdapter.priceWad(_feed(mock, 1 hours));
        assertEq(price, 2000e18);
    }

    function test_PassesThroughEighteenDecimalFeedUnchanged() public {
        vm.warp(1_000_000);
        MockAggregatorV3 mock = new MockAggregatorV3(18, 1e18, block.timestamp);
        uint256 price = OracleAdapter.priceWad(_feed(mock, 1 hours));
        assertEq(price, 1e18);
    }

    function test_ScalesDownFeedWithMoreThan18Decimals() public {
        vm.warp(1_000_000);
        // Chainlink feeds cap at 18 decimals (8 for most USD pairs, 18 for ETH-denominated
        // ones) -- this branch guards a case no real feed hits, but priceWad's own
        // if/else if/else chain still has it, so it needs coverage.
        MockAggregatorV3 mock = new MockAggregatorV3(24, 2000e24, block.timestamp); // $2000, 24 decimals
        uint256 price = OracleAdapter.priceWad(_feed(mock, 1 hours));
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
        this._priceWad(_feed(mock, 1 hours));
    }

    function test_AcceptsPriceExactlyAtStalenessThreshold() public {
        vm.warp(1_000_000);
        MockAggregatorV3 mock = new MockAggregatorV3(8, 2000e8, block.timestamp - 1 hours);
        uint256 price = OracleAdapter.priceWad(_feed(mock, 1 hours));
        assertEq(price, 2000e18);
    }

    function test_RevertsOnNonPositivePrice() public {
        vm.warp(1_000_000);
        MockAggregatorV3 mock = new MockAggregatorV3(8, 0, block.timestamp);

        vm.expectRevert(
            abi.encodeWithSelector(OracleAdapter.OracleAdapterInvalidPrice.selector, address(mock), int256(0))
        );
        this._priceWad(_feed(mock, 1 hours));
    }

    function test_RevertsOnNegativePrice() public {
        vm.warp(1_000_000);
        MockAggregatorV3 mock = new MockAggregatorV3(8, -1, block.timestamp);

        vm.expectRevert(
            abi.encodeWithSelector(OracleAdapter.OracleAdapterInvalidPrice.selector, address(mock), int256(-1))
        );
        this._priceWad(_feed(mock, 1 hours));
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

        uint256 totalValue = OracleAdapter.groupValueWad(tokens, balances, feeds);
        assertEq(totalValue, 20_000e18);
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
