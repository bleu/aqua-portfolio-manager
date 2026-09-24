// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {PortfolioManagerArgsCodec} from "./PortfolioManagerArgsCodec.sol";

/// @title GatedPortfolioManagerProgramBuilder
/// @notice Same wire format as `PortfolioManagerProgramBuilder`, plus a resolver KYC gate
///         appended after the curve instruction -- 1inch's Aqua access-control requirement
///         (https://business.1inch.com/portal/documentation/aqua/liquidity-layer/access-resolvers-and-pathfinder):
///         "Assembler attaches `withTxOriginAccessToken(aquaKycToken)` to every strategy."
/// @dev A separate library rather than a flag on the existing builder: gating is a per-strategy
///      program choice (the token address lives in the instruction's own args, not a router-level
///      constant), so `PortfolioManagerProgramBuilder` stays untouched for strategies that don't
///      need it yet (e.g. mainnet-test strategies shipped before a confirmed credential exists).
/// @dev The gate comes *after* the curve instruction, not before: `PortfolioManagerStrategyValidator`
///      hard-requires `program[0] == CURVE_OPCODE` (`_args()`'s own check), so a strategy validates
///      identically whether it's gated or not. This doesn't weaken the gate -- `runLoop` runs both
///      instructions in the same call, so a failing gate still reverts the whole transaction,
///      including whatever the curve instruction already did.
library GatedPortfolioManagerProgramBuilder {
    using SafeCast for uint256;

    /// @dev Must match `PortfolioManagerOpcodes._opcodes()`'s dynamic-array index exactly.
    uint8 internal constant CURVE_OPCODE = 0;
    /// @dev Must match `PortfolioManagerOpcodes._opcodes()`'s dynamic-array index exactly.
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
        bytes memory curveArgs = PortfolioManagerArgsCodec.build(groups, feeBps, maxDeviationBps);
        program = abi.encodePacked(
            CURVE_OPCODE,
            curveArgs.length.toUint8(),
            curveArgs,
            KYC_GATE_OPCODE,
            uint8(20), // Controls._onlyTxOriginTokenBalanceNonZero reads a 20-byte token address.
            resolverKycToken
        );
    }
}
