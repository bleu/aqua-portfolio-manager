import { encodeFunctionData, zeroAddress, type Address, type Hex } from "viem";
import { AQUA_ADDRESS, PM_ROUTER_ADDRESS } from "./contracts";

const SAFE_GUARD_ABI = [
  {
    type: "function",
    name: "setGuard",
    stateMutability: "nonpayable",
    inputs: [{ name: "guard", type: "address" }],
    outputs: [],
  },
] as const;

const AQUA_DOCK_ABI = [
  {
    type: "function",
    name: "dock",
    stateMutability: "nonpayable",
    inputs: [
      { name: "app", type: "address" },
      { name: "strategyHash", type: "bytes32" },
      { name: "tokens", type: "address[]" },
    ],
    outputs: [],
  },
] as const;

/** Builds the single `Aqua.dock()` call that deactivates the connected Safe's Portfolio Manager
 *  strategy -- see Aqua.sol's own `dock()`: it only flips each token's ledger entry to a closed
 *  marker, it never moves a token, so this never touches the Safe's actual balances. `tokens`
 *  must be the exact set the strategy shipped with (Aqua reverts otherwise, DockingShouldCloseAllTokens) --
 *  always read from the indexer's `strategy.tokens`, never reconstructed from current basket drafts. */
export function buildDockTransaction(strategyHash: Hex, tokens: Address[]): { to: Address; data: Hex } {
  return {
    to: AQUA_ADDRESS,
    data: encodeFunctionData({
      abi: AQUA_DOCK_ABI,
      functionName: "dock",
      args: [PM_ROUTER_ADDRESS, strategyHash, tokens],
    }),
  };
}

/** Builds the call that clears whatever BasketScopeGuard the ship wizard installed for the
 *  strategy being docked (see safeProposal.ts's own "setGuard" step). The guard's basket mapping
 *  is fixed at deploy time and bound to that one strategy's hash -- once it's docked, that hash
 *  can never ship again anyway (Aqua's own immutability rule), so the guard has nothing left to
 *  usefully protect, only a future, differently-grouped strategy left to block by mistake.
 *  Caller should skip sending this when readInstalledGuard (safeProposal.ts) already reports
 *  zeroAddress, same "don't ask for a pointless signature" rule the ship wizard's own
 *  isStepAlreadyDone follows. */
export function buildRemoveGuardTransaction(safeAddress: Address): { to: Address; data: Hex } {
  return {
    to: safeAddress,
    data: encodeFunctionData({ abi: SAFE_GUARD_ABI, functionName: "setGuard", args: [zeroAddress] }),
  };
}
