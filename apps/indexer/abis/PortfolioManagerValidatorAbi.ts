// Matches packages/contracts/src/interfaces/IPortfolioManagerStrategyValidator.sol exactly.
export const PortfolioManagerValidatorAbi = [
  {
    type: "event",
    name: "BuildParametersAttested",
    inputs: [
      { name: "strategyHash", type: "bytes32", indexed: true },
      { name: "groupNames", type: "string[]", indexed: false },
    ],
  },
] as const;
