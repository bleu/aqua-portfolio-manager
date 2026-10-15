// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {PortfolioManagerArgsCodec} from "./PortfolioManagerArgsCodec.sol";
import {PortfolioManagerProgramBuilder} from "./PortfolioManagerProgramBuilder.sol";

/// @notice Same wire format as `PortfolioManagerProgramBuilder`, with a resolver KYC gate
///         appended after the curve instruction (`program[0]` must stay `CURVE_OPCODE`, per
///         `PortfolioManagerStrategyValidator._args()`).
library GatedPortfolioManagerProgramBuilder {
    /// @dev Must match `PortfolioManagerOpcodes._opcodes()`'s dynamic-array index exactly --
    ///      no compile-time check ties these together, so reordering that array breaks this silently.
    uint8 internal constant KYC_GATE_OPCODE = 1;

    /// @param groups, feeBps  The LP's own declared groups and curve fee.
    /// @param resolverKycToken  1inch's confirmed per-chain Aqua resolver credential
    ///        (`KycNFT`/`RES`) -- `Controls._onlyTxOriginTokenBalanceNonZero` checks
    ///        `balanceOf(tx.origin)` of this token before the curve swap runs.
    function build(PortfolioManagerArgsCodec.Group[] memory groups, uint32 feeBps, address resolverKycToken)
        internal
        pure
        returns (bytes memory program)
    {
        return build(groups, feeBps, 0, resolverKycToken);
    }

    /// @param groups, feeBps  The LP's own declared groups and curve fee.
    /// @param maxDeviationBps  Price-deviation circuit breaker (ADR-0012) -- 0 disables it.
    /// @param resolverKycToken  1inch's confirmed per-chain Aqua resolver credential
    ///        (`KycNFT`/`RES`) -- `Controls._onlyTxOriginTokenBalanceNonZero` checks
    ///        `balanceOf(tx.origin)` of this token before the curve swap runs.
    function build(
        PortfolioManagerArgsCodec.Group[] memory groups,
        uint32 feeBps,
        uint32 maxDeviationBps,
        address resolverKycToken
    ) internal pure returns (bytes memory program) {
        bytes memory curveProgram = PortfolioManagerProgramBuilder.build(groups, feeBps, maxDeviationBps);
        program = abi.encodePacked(
            curveProgram,
            KYC_GATE_OPCODE,
            uint8(20), // Controls._onlyTxOriginTokenBalanceNonZero reads a 20-byte token address.
            resolverKycToken
        );
    }
}
