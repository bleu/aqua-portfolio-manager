import { encodeFunctionData, type Address, type Hex } from "viem";
import { AQUA_ADDRESS, PM_ROUTER_ADDRESS } from "./contracts";

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
