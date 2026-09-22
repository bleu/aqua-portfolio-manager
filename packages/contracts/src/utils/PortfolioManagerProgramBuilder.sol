// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {PortfolioManagerArgsCodec} from "./PortfolioManagerArgsCodec.sol";

/// @title PortfolioManagerProgramBuilder
/// @notice Encodes a PM instruction using the fixed PortfolioManagerOpcodes index.
/// @dev Wire format: [opcode:1 byte][argsLength:1 byte][args:argsLength bytes].
///      The curve instruction handles the protocol fee internally.
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
        return build(groups, feeBps, 0);
    }

    /// @param groups, feeBps  The LP's own declared groups and curve fee.
    /// @param maxDeviationBps  Price-deviation circuit breaker (ADR-0012) -- 0 disables it.
    function build(PortfolioManagerArgsCodec.Group[] memory groups, uint32 feeBps, uint32 maxDeviationBps)
        internal
        pure
        returns (bytes memory program)
    {
        bytes memory args = PortfolioManagerArgsCodec.build(groups, feeBps, maxDeviationBps);
        program = abi.encodePacked(CURVE_OPCODE, args.length.toUint8(), args);
    }
}
