// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {ExposureReader} from "../src/ExposureReader.sol";

contract ExposureReaderTest is Test {
    ERC20Mock tokenA;
    ERC20Mock tokenB;
    ERC20Mock outsideToken;
    address maker = address(0xBEEF);

    function setUp() public {
        tokenA = new ERC20Mock();
        tokenB = new ERC20Mock();
        outsideToken = new ERC20Mock();
    }

    // See FixedPointMath.t.sol for why internal library calls need an external wrapper for
    // `vm.expectRevert` to intercept the revert at the right call depth.
    function _callBalanceOf(address token, address account, address[] memory universe) external view returns (uint256) {
        return ExposureReader.balanceOf(token, account, universe);
    }

    function _universeOf(address a, address b) internal pure returns (address[] memory universe) {
        universe = new address[](2);
        universe[0] = a;
        universe[1] = b;
    }

    function test_ReadsRealWalletBalance() public {
        tokenA.mint(maker, 1_000e18);

        uint256 balance =
            ExposureReader.balanceOf(address(tokenA), maker, _universeOf(address(tokenA), address(tokenB)));
        assertEq(balance, 1_000e18);
    }

    function test_ReadsZeroForUntouchedInUniverseToken() public view {
        uint256 balance =
            ExposureReader.balanceOf(address(tokenB), maker, _universeOf(address(tokenA), address(tokenB)));
        assertEq(balance, 0);
    }

    function test_ReflectsBalanceChangesLive() public {
        tokenA.mint(maker, 500e18);
        assertEq(
            ExposureReader.balanceOf(address(tokenA), maker, _universeOf(address(tokenA), address(tokenB))), 500e18
        );

        tokenA.mint(maker, 250e18);
        assertEq(
            ExposureReader.balanceOf(address(tokenA), maker, _universeOf(address(tokenA), address(tokenB))), 750e18
        );

        vm.prank(maker);
        tokenA.transfer(address(0x1), 100e18);
        assertEq(
            ExposureReader.balanceOf(address(tokenA), maker, _universeOf(address(tokenA), address(tokenB))), 650e18
        );
    }

    function test_RevertsOnTokenOutsideDeclaredUniverse() public {
        outsideToken.mint(maker, 1_000_000e18); // a "donation" landing outside the declared universe

        vm.expectRevert(
            abi.encodeWithSelector(
                ExposureReader.ExposureReaderTokenOutsideDeclaredUniverse.selector, address(outsideToken)
            )
        );
        this._callBalanceOf(address(outsideToken), maker, _universeOf(address(tokenA), address(tokenB)));
    }

    function test_RevertsOnEmptyUniverse() public {
        address[] memory emptyUniverse = new address[](0);

        vm.expectRevert(
            abi.encodeWithSelector(ExposureReader.ExposureReaderTokenOutsideDeclaredUniverse.selector, address(tokenA))
        );
        this._callBalanceOf(address(tokenA), maker, emptyUniverse);
    }
}
