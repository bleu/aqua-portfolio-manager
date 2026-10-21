// Only the events this indexer watches -- matches lib/aqua's own real event signatures exactly
// (packages/contracts/lib/aqua), not a guess.
export const AquaAbi = [
  {
    type: "event",
    name: "Shipped",
    inputs: [
      { name: "maker", type: "address", indexed: false },
      { name: "app", type: "address", indexed: false },
      { name: "strategyHash", type: "bytes32", indexed: false },
      { name: "strategy", type: "bytes", indexed: false },
    ],
  },
  {
    type: "event",
    name: "Pushed",
    inputs: [
      { name: "maker", type: "address", indexed: false },
      { name: "app", type: "address", indexed: false },
      { name: "strategyHash", type: "bytes32", indexed: false },
      { name: "token", type: "address", indexed: false },
      { name: "amount", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "Docked",
    inputs: [
      { name: "maker", type: "address", indexed: false },
      { name: "app", type: "address", indexed: false },
      { name: "strategyHash", type: "bytes32", indexed: false },
    ],
  },
] as const;
