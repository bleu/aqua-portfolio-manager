// Minimal ABIs -- only the functions/events this server actually calls. Kept hand-written and
// scoped tight rather than importing the full Foundry build artifact, so this package has no
// build-order dependency on `packages/contracts` (see README's "Why no artifact import" note).

const orderTupleComponent = {
  name: "order",
  type: "tuple",
  components: [
    { name: "maker", type: "address" },
    { name: "traits", type: "uint256" },
    { name: "data", type: "bytes" },
  ],
} as const;

export const arbitrageurAbi = [
  {
    type: "function",
    name: "quoteExactIn",
    stateMutability: "view",
    inputs: [
      orderTupleComponent,
      { name: "tokenIn", type: "address" },
      { name: "tokenOut", type: "address" },
      { name: "amountIn", type: "uint256" },
    ],
    outputs: [{ name: "amountOut", type: "uint256" }],
  },
  {
    type: "function",
    name: "executeFlashArbitrage",
    stateMutability: "nonpayable",
    inputs: [
      {
        name: "params",
        type: "tuple",
        components: [
          orderTupleComponent,
          { name: "tokenIn", type: "address" },
          { name: "tokenOut", type: "address" },
          { name: "amountIn", type: "uint256" },
          { name: "minCurveAmountOut", type: "uint256" },
          { name: "fyndTarget", type: "address" },
          { name: "fyndSpender", type: "address" },
          { name: "fyndCalldata", type: "bytes" },
          { name: "deadline", type: "uint40" },
        ],
      },
    ],
    outputs: [],
  },
  {
    type: "event",
    name: "FlashArbitrageExecuted",
    inputs: [
      { name: "orderHash", type: "bytes32", indexed: true },
      { name: "tokenIn", type: "address", indexed: true },
      { name: "tokenOut", type: "address", indexed: true },
      { name: "amountIn", type: "uint256", indexed: false },
      { name: "curveAmountOut", type: "uint256", indexed: false },
      { name: "repaid", type: "uint256", indexed: false },
      { name: "profit", type: "uint256", indexed: false },
    ],
  },
] as const;

export { erc20Abi } from "viem";
