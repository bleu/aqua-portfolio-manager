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
    ///      see `PortfolioManagerOpcodes.KYC_GATE_OPCODE`'s own doc comment for why this can't be
    ///      a single shared symbol, and `PortfolioManagerOpcodesLayoutGuard.t.sol` for the
    ///      regression test that catches a drift between the two.
    uint8 internal constant KYC_GATE_OPCODE = 1;

    /// @dev A zero `resolverKycToken` encodes a gate whose `balanceOf(tx.origin)`
    ///      call always targets address(0) -- on most chains an empty-code call like that reverts
    ///      on ABI-decoding the empty returndata, permanently blocking every swap against the
    ///      resulting program. Caught here, at build time, instead of only discovered the first
    ///      time someone tries to trade against it.
    error GatedPortfolioManagerProgramBuilderZeroResolverKycToken();

    /// @param groups, feeBps  The LP's own declared groups and curve fee.
    /// @param resolverKycToken  1inch's confirmed per-chain Aqua resolver credential
    ///        (`KycNFT`/`RES`) -- `Controls._onlyTxOriginTokenBalanceNonZero` checks
    ///        `balanceOf(tx.origin)` of this token before the curve swap runs.
    /// @dev `tx.origin`-based gating also means any contract a credentialed
    ///      resolver EOA calls can reuse that same credential for an unrelated trade (confused
    ///      deputy), in addition to the EIP-7702 delegation risk `PortfolioManagerOpcodes._opcodes()`'s
    ///      own doc comment already documents -- see that comment for why this is an accepted
    ///      protocol-level tradeoff rather than a local patch.
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
        require(resolverKycToken != address(0), GatedPortfolioManagerProgramBuilderZeroResolverKycToken());
        bytes memory curveProgram = PortfolioManagerProgramBuilder.build(groups, feeBps, maxDeviationBps);
        program = abi.encodePacked(
            curveProgram,
            KYC_GATE_OPCODE,
            uint8(20), // Controls._onlyTxOriginTokenBalanceNonZero reads a 20-byte token address.
            resolverKycToken
        );
    }
}
