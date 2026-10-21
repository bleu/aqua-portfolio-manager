// Only the event this indexer watches. Standard Chainlink EACAggregatorProxy signature.
export const ChainlinkProxyAbi = [
  {
    type: "event",
    name: "AggregatorConfirmed",
    inputs: [
      { name: "previous", type: "address", indexed: true },
      { name: "latest", type: "address", indexed: true },
    ],
  },
] as const;
