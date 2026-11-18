// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

/// @dev Registers the weighted-curve instruction. Its protocol fee transfer is part of that instruction.

import {Context} from "swap-vm/libs/VM.sol";
import {Controls} from "swap-vm/instructions/Controls.sol";
import {PortfolioManagerSwap} from "./PortfolioManagerSwap.sol";

/// @dev Never deployed on its own -- only ever inherited by `PortfolioManagerRouter`.
abstract contract PortfolioManagerOpcodes is PortfolioManagerSwap, Controls {
    /// @dev The indices `PortfolioManagerProgramBuilder.sol` and
    ///      `GatedPortfolioManagerProgramBuilder.sol` hardcode into their encoded programs --
    ///      Solidity has no way to share these as a single symbol across a library and an
    ///      abstract contract (no cross-contract access to an internal/public constant without
    ///      inheritance), and a runtime check comparing `_opcodes()`'s entries against these
    ///      function references does not reliably compile under this project's `via_ir` pipeline
    ///      (solc itself warns internal-function-pointer comparison is unreliable with the
    ///      optimizer and will be removed entirely in a future release -- confirmed by triggering
    ///      solc error 1284 while prototyping that check here).
    ///      `PortfolioManagerOpcodesLayoutGuard.t.sol` is the enforcement instead: a dedicated
    ///      regression test that pins opcode byte 0 to the curve swap and opcode byte 1 to the
    ///      KYC gate through the real, shippable program-building path, so reordering or
    ///      extending `_opcodes()` below fails CI immediately rather than silently shipping.
    uint8 internal constant CURVE_OPCODE = 0;
    uint8 internal constant KYC_GATE_OPCODE = 1;

    constructor(
        address aqua,
        address strategyValidator,
        address sequencerUptimeFeed,
        address tokenRegistry,
        address feedRegistry
    ) PortfolioManagerSwap(aqua, strategyValidator, sequencerUptimeFeed, tokenRegistry, feedRegistry) {}

    function _notInstruction(
        Context memory,
        /* ctx */
        bytes calldata /* args */
    )
        internal {}

    /// @dev Opcode 1 = resolver KYC gate (1inch Aqua access-control -- see
    ///      https://business.1inch.com/portal/documentation/aqua/liquidity-layer/access-resolvers-and-pathfinder),
    ///      checked via `tx.origin` since the resolver, not the taker, is the credentialed party
    ///      and only `tx.origin` identifies the resolver across a multi-hop call. Only referenced
    ///      by `GatedPortfolioManagerProgramBuilder`; inert for `PortfolioManagerProgramBuilder`'s
    ///      ungated programs.
    function _opcodes()
        internal
        pure
        virtual
        returns (function(Context memory, bytes calldata) internal[] memory result)
    {
        function(Context memory, bytes calldata) internal[3] memory instructions = [
            _notInstruction, PortfolioManagerSwap._portfolioManagerSwapXd, Controls._onlyTxOriginTokenBalanceNonZero
        ];

        // Same trick AquaOpcodes.sol uses: rewrite the leading _notInstruction with the array's
        // length, turning a fixed-size literal into a dynamic array with that entry dropped.
        uint256 instructionsArrayLength = instructions.length - 1;
        assembly ("memory-safe") {
            result := instructions
            mstore(result, instructionsArrayLength)
        }
    }
}
