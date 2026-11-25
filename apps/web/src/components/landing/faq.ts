export type FaqItem = { question: string; answer: string[] };

/** Landing page FAQ. Source: Trim Product Handoff, section 13, "FAQ atual (estará na landing page)". */
export const FAQ: FaqItem[] = [
  {
    question: "Which wallets are supported by Trim?",
    answer: [
      "Trim currently supports only Safe Smart Accounts, which allows us to monitor and block incompatible strategies. This helps protect your portfolio from actions that could interfere with your target allocations.",
    ],
  },
  {
    question: "Which Aqua strategies are compatible with Trim?",
    answer: [
      "Trim works alongside Aqua strategies that don’t interfere with your portfolio’s target allocations.",
      "When setting up Trim, you organize your tokens into groups and assign a target allocation to each one. Strategies that trade tokens within the same group are compatible, while those that swap tokens between different groups can interfere with your targets.",
      "For example, if you have one group for stablecoins and another for ETH and BTC, a strategy swapping USDC for USDT would be compatible. However, swapping USDC for ETH would cross those groups and conflict with your target allocations.",
      "Trim monitors and blocks incompatible strategies to help protect your portfolio.",
    ],
  },
  {
    question: "Which tokens are supported by Trim?",
    answer: [
      "Trim supports tokens with compatible Chainlink push-based price feeds. These oracles provide reliable reference prices that Trim uses to enforce your price deviation limit and protect trades from unfavorable execution.",
      "You can view the supported tokens during setup or find the complete list in our documentation.",
    ],
  },
  {
    question: "What happens when I add or remove tokens managed by Trim?",
    answer: [
      "Adding or removing tokens managed by Trim changes your portfolio’s allocation and may trigger rebalancing.",
      "Your price deviation limit helps protect against unfavorable execution. If a trade exceeds your configured tolerance, it is blocked. Rebalancing can resume once execution falls within your limit.",
    ],
  },
  {
    question: "What risks should I consider when using Trim?",
    answer: [
      "Trim manages your portfolio’s token allocation, but your assets remain exposed to market fluctuations.",
      "Changes in token prices, trading activity, and rebalancing can affect your portfolio’s value. Setting targets that differ significantly from your current allocation may also create arbitrage opportunities and result in losses.",
      "Your price deviation limit helps protect trade execution, but it doesn’t eliminate market risk.",
    ],
  },
  {
    question: "How do fees work in Trim?",
    answer: [
      "You choose the LP fee charged whenever Aqua routes a trade through your portfolio. A portion of that fee goes to the protocol, and you earn the remainder.",
      "The protocol’s share depends on your selected LP fee. For example, with a 2% LP fee, approximately 0.33% of the traded amount goes to the protocol, while you earn the remaining 1.67%.",
      "You can check the fee breakdown in our documentation.",
    ],
  },
  {
    question: "Does setting a higher LP fee mean higher earnings?",
    answer: [
      "Not necessarily. A higher LP fee means you earn more from each trade routed through your portfolio, but it can also make your liquidity less competitive, reducing how often it’s selected for trades.",
      "Your total earnings depend on both the fee you set and the volume of trades routed through your portfolio.",
    ],
  },
];
