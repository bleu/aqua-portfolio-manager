// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title IFlashLoanRecipient — Balancer V2's flash-loan callback interface
/// @notice Re-declared locally rather than pulled in via a `lib/` submodule, same reasoning as
///         `AggregatorV3Interface.sol`: this is the whole surface `Arbitrageur` needs, matching
///         Balancer V2's own published ABI exactly.
interface IFlashLoanRecipient {
    /// @dev Called by the Vault synchronously, inside its own `flashLoan` execution -- `tokens`/
    ///      `amounts` must be repaid (transferred back to `msg.sender`, i.e. the Vault) plus
    ///      `feeAmounts` before this call returns, or the whole flash loan reverts.
    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external;
}

/// @title IBalancerVault — the subset of Balancer V2's Vault needed for flash loans
/// @notice Same canonical address (`0xBA12222222228d8Ba445958a75a0704d566BF2C8`) on every EVM
///         chain Balancer V2 is deployed to, Base included. Flash loans are fee-free as of this
///         writing -- `feeAmounts` in the callback above may still be nonzero if that ever
///         changes, so it's never assumed to be zero on this contract's side.
interface IBalancerVault {
    function flashLoan(
        IFlashLoanRecipient recipient,
        IERC20[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}
