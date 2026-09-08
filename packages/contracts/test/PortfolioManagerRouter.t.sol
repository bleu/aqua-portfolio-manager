// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Test} from "forge-std/Test.sol";
import {PortfolioManagerRouter} from "../src/PortfolioManagerRouter.sol";

/// @notice The router itself has no logic beyond wiring `SwapVM`/`PortfolioManagerOpcodes`
/// together (see its own header comment: "mirrors AquaSwapVMRouter.sol exactly") -- its
/// opcode dispatch is already exhaustively exercised by every PortfolioManagerOpcodes.t.sol
/// and E2E test that ships/swaps through a deployed instance. What's never independently
/// checked anywhere else is that the constructor forwards `aqua`/`owner` into the base
/// contracts it inherits, rather than, say, swapping two constructor arguments by accident --
/// `weth` isn't checked here: `SwapVM`'s base `OnlyWethReceiver` stores it in a private
/// immutable with no accessor anywhere in the inheritance chain, so it's structurally
/// unobservable from a test.
contract PortfolioManagerRouterTest is Test {
    function test_ConstructorWiresAquaAndOwnerCorrectly() public {
        address aqua = address(0xA11CE00000000000000000000000000000000A);
        address weth = address(0xB0B0000000000000000000000000000000000B);
        address owner = address(0xC0FFEE0000000000000000000000000000000C);

        PortfolioManagerRouter router = new PortfolioManagerRouter(aqua, weth, owner, "PM", "1");

        assertEq(address(router.AQUA()), aqua, "AQUA must be the address passed to the constructor");
        assertEq(router.owner(), owner, "owner (Rescuable/Ownable) must be the address passed to the constructor");
    }
}
