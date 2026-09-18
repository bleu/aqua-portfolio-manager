// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {PortfolioManagerArgsCodec} from "./PortfolioManagerArgsCodec.sol";

/// @title PortfolioManagerProgramBuilder — composes a PM strategy's swap-vm program bytes
/// @notice Production equivalent of swap-vm's own test-only `ProgramBuilder`
///         (`lib/swap-vm/test/utils/ProgramBuilder.sol`) — not reused directly because it
///         lives under `test/`, outside what a `script`/`src` contract can import, and because
///         production callers don't need its runtime function-pointer search:
///         `PortfolioManagerOpcodes`' opcode index is fixed and known here directly.
/// @dev Wire format matches `VM.sol`'s `runLoop` exactly: `[opcode:1 byte][argsLength:1
///      byte][args:argsLength bytes]`.
/// @dev The protocol fee itself is *not* composed here — it's baked directly into
///      `PortfolioManagerSwap`'s own execution so it can't be omitted by a hand-crafted program
///      that skips this builder entirely. The fee's own constants/formula live in
///      `PortfolioManagerFee`, not here — this builder has no need for them itself.
library PortfolioManagerProgramBuilder {
    using SafeCast for uint256;

    /// @dev Must match `PortfolioManagerOpcodes._opcodes()`'s dynamic-array index exactly.
    uint8 internal constant CURVE_OPCODE = 0;

    /// @param groups, feeBps  The LP's own declared groups and curve fee.
    function build(PortfolioManagerArgsCodec.Group[] memory groups, uint32 feeBps)
        internal
        pure
        returns (bytes memory program)
    {
        bytes memory args = PortfolioManagerArgsCodec.build(groups, feeBps);
        program = abi.encodePacked(CURVE_OPCODE, args.length.toUint8(), args);
    }
}
