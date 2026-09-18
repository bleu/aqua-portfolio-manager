// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Test} from "forge-std/Test.sol";
import {PortfolioManagerRouter} from "../src/PortfolioManagerRouter.sol";

/// @notice Constructor wiring isn't exercised by any opcode-dispatch test elsewhere. `weth`
/// isn't asserted: `OnlyWethReceiver` stores it in a private immutable with no accessor.
contract PortfolioManagerRouterTest is Test {
    function test_ConstructorWiresAquaAndOwnerCorrectly() public {
        address aqua = address(0xA11CE00000000000000000000000000000000A);
        address weth = address(0xB0B0000000000000000000000000000000000B);
        address owner = address(0xC0FFEE0000000000000000000000000000000C);
        address strategyFactory = address(0xFAC70000000000000000000000000000000000);

        PortfolioManagerRouter router = new PortfolioManagerRouter(aqua, weth, owner, "PM", "1", strategyFactory);

        assertEq(address(router.AQUA()), aqua, "AQUA must be the address passed to the constructor");
        assertEq(router.owner(), owner, "owner (Rescuable/Ownable) must be the address passed to the constructor");
    }
}
