// Only the event this indexer watches. Standard Chainlink AggregatorV3Interface signature.
export const ChainlinkAggregatorAbi = [
  {
    type: "event",
    name: "AnswerUpdated",
    inputs: [
      { name: "current", type: "int256", indexed: true },
      { name: "roundId", type: "uint256", indexed: true },
      { name: "updatedAt", type: "uint256", indexed: false },
    ],
  },
] as const;
