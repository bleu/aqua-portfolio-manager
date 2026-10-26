/** Every Chainlink-registered Base-mainnet token (BLEUDEV-412's 40-token universe). Mirrored here
 *  from packages/addresses/base-mainnet-feeds.json since that shared package isn't on this
 *  branch's history yet -- re-sync if the canonical list changes before the branches merge. */
export type TokenFeed = {
  symbol: string;
  tokenAddress: string;
  feedProxy: string;
  feedDecimals: number;
};

/** Logos for the most commonly held tokens, sourced from Trust Wallet's public asset repo (WBTC's
 *  reuses Ethereum mainnet's entry -- same token, no separate Base-specific logo there) and
 *  CoinGecko for cbBTC (not yet in Trust Wallet's Base asset list). Scoped to just these tokens
 *  for now rather than all 40 -- expand this map if more of the list needs real icons later. */
export const POPULAR_TOKEN_ICONS: Record<string, string> = {
  USDC: "https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/base/assets/0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913/logo.png",
  USDT: "https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/base/assets/0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2/logo.png",
  DAI: "https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/base/assets/0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb/logo.png",
  WETH: "https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/base/assets/0x4200000000000000000000000000000000000006/logo.png",
  CBETH: "https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/base/assets/0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22/logo.png",
  WBTC: "https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/ethereum/assets/0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599/logo.png",
  CBBTC: "https://coin-images.coingecko.com/coins/images/40143/small/cbbtc.webp",
};

export const TOKEN_FEEDS: TokenFeed[] = [
  { symbol: "AAVE", tokenAddress: "0x63706e401c06ac8513145b7687A14804d17f814b", feedProxy: "0x3d6774EF702A10b20FCa8Ed40FC022f7E4938e07", feedDecimals: 8 },
  { symbol: "AERO", tokenAddress: "0x940181a94A35A4569E4529A3CDfB74e38FD98631", feedProxy: "0x4EC5970fC728C5f65ba413992CD5fF6FD70fcfF0", feedDecimals: 8 },
  { symbol: "AVNT", tokenAddress: "0x696F9436B67233384889472Cd7cD58A6fB5DF4f1", feedProxy: "0x50997b806B574501cC34a2a6d845e4dc1Bd9Aa8c", feedDecimals: 8 },
  { symbol: "AXL", tokenAddress: "0x23ee2343B892b1BB63503a4FAbc840E0e2C6810f", feedProxy: "0x676C4C6C31D97A5581D3204C04A8125B350E2F9D", feedDecimals: 8 },
  { symbol: "CBBTC", tokenAddress: "0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf", feedProxy: "0x07DA0E54543a844a80ABE69c8A12F22B3aA59f9D", feedDecimals: 8 },
  { symbol: "CBDOGE", tokenAddress: "0xcbD06E5A2B0C65597161de254AA074E489dEb510", feedProxy: "0x95051De9Db5Cac61682f64505006f2991dEaB3c2", feedDecimals: 8 },
  { symbol: "CBETH", tokenAddress: "0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22", feedProxy: "0xd7818272B9e248357d13057AAb0B417aF31E817d", feedDecimals: 8 },
  { symbol: "CBXRP", tokenAddress: "0xcb585250f852C6c6bf90434AB21A00f02833a4af", feedProxy: "0xEEe1a9D5A0C36d99972C057Cb959267e88Ab9160", feedDecimals: 8 },
  { symbol: "COMP", tokenAddress: "0x9e1028F5F1D5eDE59748FFceE5532509976840E0", feedProxy: "0x9DDa783DE64A9d1A60c49ca761EbE528C35BA428", feedDecimals: 8 },
  { symbol: "DAI", tokenAddress: "0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb", feedProxy: "0x591e79239a7d679378eC8c847e5038150364C78F", feedDecimals: 8 },
  { symbol: "DEGEN", tokenAddress: "0x4ed4E862860beD51a9570b96d89aF5E1B0Efefed", feedProxy: "0xE62BcE5D7CB9d16AB8b4D622538bc0A50A5799c2", feedDecimals: 8 },
  { symbol: "EURC", tokenAddress: "0x60a3E35Cc302bFA44Cb288Bc5a4F316Fdb1adb42", feedProxy: "0xDAe398520e2B67cd3f27aeF9Cf14D93D927f8250", feedDecimals: 8 },
  { symbol: "GHO", tokenAddress: "0x6Bb7a212910682DCFdbd5BCBb3e28FB4E8da10Ee", feedProxy: "0x42868EFcee13C0E71af89c04fF7d96f5bec479b0", feedDecimals: 8 },
  { symbol: "HOME", tokenAddress: "0x4BfAa776991E85e5f8b1255461cbbd216cFc714f", feedProxy: "0x121934C415937863d64ef93436169444633EE0d8", feedDecimals: 18 },
  { symbol: "JITOSOL", tokenAddress: "0x97bE14Dd8f994A5364573BC035D85309E7CB34de", feedProxy: "0x0ca181015d21A5ed19baFC17F2138883C2b16D54", feedDecimals: 18 },
  { symbol: "LBTC", tokenAddress: "0xecAc9C5F704e954931349Da37F60E39f515c11c1", feedProxy: "0x9e07546c9Fe8868855CD04B26051a26D1599E270", feedDecimals: 8 },
  { symbol: "LINK", tokenAddress: "0x88Fb150BDc53A65fe94Dea0c9BA0a6dAf8C6e196", feedProxy: "0x17CAb8FE31E32f08326e5E27412894e49B0f9D65", feedDecimals: 8 },
  { symbol: "MAMO", tokenAddress: "0x7300B37DfdfAb110d83290A29DfB31B1740219fE", feedProxy: "0xeF7541b388a77C1709a3d44BfBfC5c1ED3F0Ac94", feedDecimals: 8 },
  { symbol: "MORPHO", tokenAddress: "0xBAa5CC21fd487B8Fcc2F632f3F4E8D37262a0842", feedProxy: "0xe95e258bb6615d47515Fc849f8542dA651f12bF6", feedDecimals: 8 },
  { symbol: "OP", tokenAddress: "0x5b8a884496792F754dB6F92F6EacCEb376ed8e40", feedProxy: "0x3E3A6bD129A63564FE7abde85FA67c3950569060", feedDecimals: 8 },
  { symbol: "OUSD", tokenAddress: "0xB2000000000000000000002fEb517dFeC7415344", feedProxy: "0xa718561C4592217b9fa301ADdD183FE4F347E096", feedDecimals: 8 },
  { symbol: "RSR", tokenAddress: "0xaB36452DbAC151bE02b16Ca17d8919826072f64a", feedProxy: "0xAa98aE504658766Dfe11F31c5D95a0bdcABDe0b1", feedDecimals: 8 },
  { symbol: "SHIB", tokenAddress: "0xFCa95aeb5bF44aE355806A5ad14659c940dC6BF7", feedProxy: "0xC8D5D660bb585b68fa0263EeD7B4224a5FC99669", feedDecimals: 8 },
  { symbol: "SNX", tokenAddress: "0x22e6966B799c4D5B13BE962E1D117b56327FDa66", feedProxy: "0xe3971Ed6F1A5903321479Ef3148B5950c0612075", feedDecimals: 8 },
  { symbol: "STG", tokenAddress: "0xE3B53AF74a4BF62Ae5511055290838050bf764Df", feedProxy: "0x63Af8341b62E683B87bB540896bF283D96B4D385", feedDecimals: 8 },
  { symbol: "SUSDE", tokenAddress: "0x211Cc4DD073734dA055fbF44a2b4667d5E5fE5d2", feedProxy: "0x79cf4a31B29D69191f0b6E97916eB93FEB81E533", feedDecimals: 8 },
  { symbol: "TBTC", tokenAddress: "0x236aa50979D5f3De3Bd1Eeb40E81137F22ab794b", feedProxy: "0x6D75BFB5A5885f841b132198C9f0bE8c872057BF", feedDecimals: 8 },
  { symbol: "TRUMP", tokenAddress: "0x57F5fbD3DE65DFC0bd3630F732969e5fb97E6d37", feedProxy: "0x7bAfa1Af54f17cC0775a1Cf813B9fF5dED2C51E5", feedDecimals: 8 },
  { symbol: "USDAI", tokenAddress: "0x0A1a1A107E45b7Ced86833863f482BC5f4ed82EF", feedProxy: "0xFCb2C36ac8A91cE9D3c94590ED239E1f683467fe", feedDecimals: 8 },
  { symbol: "USDC", tokenAddress: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913", feedProxy: "0x7e860098F58bBFC8648a4311b374B1D669a2bc6B", feedDecimals: 8 },
  { symbol: "USDS", tokenAddress: "0x820C137fa70C8691f0e44Dc420a5e53c168921Dc", feedProxy: "0x2330aaE3bca5F05169d5f4597964D44522F62930", feedDecimals: 8 },
  { symbol: "USDT", tokenAddress: "0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2", feedProxy: "0xf19d560eB8d2ADf07BD6D13ed03e1D11215721F9", feedDecimals: 8 },
  { symbol: "USR", tokenAddress: "0x35E5dB674D8e93a03d814FA0ADa70731efe8a4b9", feedProxy: "0x4a595E0a62E50A2E5eC95A70c8E612F9746af006", feedDecimals: 8 },
  { symbol: "VIRTUAL", tokenAddress: "0x0b3e328455c4059EEb9e3f84b5543F74E24e7E1b", feedProxy: "0xEaf310161c9eF7c813A14f8FEF6Fb271434019F7", feedDecimals: 8 },
  { symbol: "VVV", tokenAddress: "0xacfE6019Ed1A7Dc6f7B508C02d1b04ec88cC21bf", feedProxy: "0xaABc55Ca55D70B034e4daA2551A224239890282F", feedDecimals: 18 },
  { symbol: "WBTC", tokenAddress: "0x0555E30da8f98308EdB960aa94C0Db47230d2B9c", feedProxy: "0xCCADC697c55bbB68dc5bCdf8d3CBe83CdD4E071E", feedDecimals: 8 },
  { symbol: "WELL", tokenAddress: "0xA88594D404727625A9437C3f886C7643872296AE", feedProxy: "0xc15d9944dAefE2dB03e53bef8DDA25a56832C5fe", feedDecimals: 8 },
  { symbol: "WETH", tokenAddress: "0x4200000000000000000000000000000000000006", feedProxy: "0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70", feedDecimals: 8 },
  { symbol: "YFI", tokenAddress: "0x9EaF8C1E34F05a589EDa6BAfdF391Cf6Ad3CB239", feedProxy: "0xD40e758b5eC80820B68DFC302fc5Ce1239083548", feedDecimals: 8 },
  { symbol: "ZRO", tokenAddress: "0x6985884C4392D348587B19cb9eAAf157F13271cd", feedProxy: "0xdc31a4CCfCA039BeC6222e20BE7770E12581bfEB", feedDecimals: 8 },
];

/** Both PortfolioManagerTokenRegistry and PortfolioManagerFeedRegistry were bulk-populated by
 *  packages/contracts/script/Deploy.s.sol from this same list (base-mainnet-feeds.json) in one
 *  loop, registering each entry's token and feed in lockstep -- so a token's registry index and
 *  its feed's registry index are both exactly its 1-based position in TOKEN_FEEDS. Verified
 *  against the real deployment: tokenAt(1)/feedAt(1) and tokenAt(40)/feedAt(40) on Base mainnet
 *  both matched this array's first and last entries. Index 0 is reserved (resolves to the zero
 *  address) in both registries, hence the +1. Throws for a token outside this 40-token universe --
 *  the wizard's basket picker only ever offers tokens from this list, so that should never happen
 *  for a strategy actually built through it. */
export function getRegistryIndex(tokenAddress: string): number {
  const index = TOKEN_FEEDS.findIndex((t) => t.tokenAddress.toLowerCase() === tokenAddress.toLowerCase());
  if (index === -1) {
    throw new Error(`${tokenAddress} is not in the registered Base-mainnet token/feed universe.`);
  }
  return index + 1;
}

/** Best-effort symbol lookup for a bare token address (e.g. from indexer data, which only ever
 *  carries addresses) -- falls back to a truncated address for a token outside this universe
 *  rather than throwing, since this is a read-only display helper, not a validation gate. */
export function symbolForToken(tokenAddress: string): string {
  const match = TOKEN_FEEDS.find((t) => t.tokenAddress.toLowerCase() === tokenAddress.toLowerCase());
  return match?.symbol ?? `${tokenAddress.slice(0, 6)}...${tokenAddress.slice(-4)}`;
}
