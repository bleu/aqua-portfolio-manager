import { DAI, USDC, USDT, WBTC, WETH } from "./mockData";
import type { Token } from "./types";

export type BasketDraft = {
  id: string;
  name: string;
  color: string;
  tokenAddresses: string[];
};

export type SafeToken = Token & {
  balance: number;
  value: number;
};

/** Every token the connected Safe holds, with its real on-chain balance and oracle-valued USD amount.
 *  The 5 above the line have a nonzero mock balance; everything below is 0 -- not held yet, but
 *  pickable, matching every Chainlink feed the protocol has registered
 *  (packages/addresses/base-mainnet-feeds.json, BLEUDEV-412/ADR-0018). */
export const safeTokens: SafeToken[] = [
  { ...USDC, balance: 6200, value: 6200 },
  { ...USDT, balance: 2100, value: 2100 },
  { ...DAI, balance: 1700, value: 1700 },
  { ...WETH, balance: 1.52, value: 4270 },
  { ...WBTC, balance: 0, value: 0 },
  { symbol: "AAVE", address: "0x63706e401c06ac8513145b7687A14804d17f814b", balance: 0, value: 0 },
  { symbol: "AERO", address: "0x940181a94A35A4569E4529A3CDfB74e38FD98631", balance: 0, value: 0 },
  { symbol: "AVNT", address: "0x696F9436B67233384889472Cd7cD58A6fB5DF4f1", balance: 0, value: 0 },
  { symbol: "AXL", address: "0x23ee2343B892b1BB63503a4FAbc840E0e2C6810f", balance: 0, value: 0 },
  { symbol: "CBBTC", address: "0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf", balance: 0, value: 0 },
  { symbol: "CBDOGE", address: "0xcbD06E5A2B0C65597161de254AA074E489dEb510", balance: 0, value: 0 },
  { symbol: "CBETH", address: "0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22", balance: 0, value: 0 },
  { symbol: "CBXRP", address: "0xcb585250f852C6c6bf90434AB21A00f02833a4af", balance: 0, value: 0 },
  { symbol: "COMP", address: "0x9e1028F5F1D5eDE59748FFceE5532509976840E0", balance: 0, value: 0 },
  { symbol: "DEGEN", address: "0x4ed4E862860beD51a9570b96d89aF5E1B0Efefed", balance: 0, value: 0 },
  { symbol: "EURC", address: "0x60a3E35Cc302bFA44Cb288Bc5a4F316Fdb1adb42", balance: 0, value: 0 },
  { symbol: "GHO", address: "0x6Bb7a212910682DCFdbd5BCBb3e28FB4E8da10Ee", balance: 0, value: 0 },
  { symbol: "HOME", address: "0x4BfAa776991E85e5f8b1255461cbbd216cFc714f", balance: 0, value: 0 },
  { symbol: "JITOSOL", address: "0x97bE14Dd8f994A5364573BC035D85309E7CB34de", balance: 0, value: 0 },
  { symbol: "LBTC", address: "0xecAc9C5F704e954931349Da37F60E39f515c11c1", balance: 0, value: 0 },
  { symbol: "LINK", address: "0x88Fb150BDc53A65fe94Dea0c9BA0a6dAf8C6e196", balance: 0, value: 0 },
  { symbol: "MAMO", address: "0x7300B37DfdfAb110d83290A29DfB31B1740219fE", balance: 0, value: 0 },
  { symbol: "MORPHO", address: "0xBAa5CC21fd487B8Fcc2F632f3F4E8D37262a0842", balance: 0, value: 0 },
  { symbol: "OP", address: "0x5b8a884496792F754dB6F92F6EacCEb376ed8e40", balance: 0, value: 0 },
  { symbol: "OUSD", address: "0xB2000000000000000000002fEb517dFeC7415344", balance: 0, value: 0 },
  { symbol: "RSR", address: "0xaB36452DbAC151bE02b16Ca17d8919826072f64a", balance: 0, value: 0 },
  { symbol: "SHIB", address: "0xFCa95aeb5bF44aE355806A5ad14659c940dC6BF7", balance: 0, value: 0 },
  { symbol: "SNX", address: "0x22e6966B799c4D5B13BE962E1D117b56327FDa66", balance: 0, value: 0 },
  { symbol: "STG", address: "0xE3B53AF74a4BF62Ae5511055290838050bf764Df", balance: 0, value: 0 },
  { symbol: "SUSDE", address: "0x211Cc4DD073734dA055fbF44a2b4667d5E5fE5d2", balance: 0, value: 0 },
  { symbol: "TBTC", address: "0x236aa50979D5f3De3Bd1Eeb40E81137F22ab794b", balance: 0, value: 0 },
  { symbol: "TRUMP", address: "0x57F5fbD3DE65DFC0bd3630F732969e5fb97E6d37", balance: 0, value: 0 },
  { symbol: "USDAI", address: "0x0A1a1A107E45b7Ced86833863f482BC5f4ed82EF", balance: 0, value: 0 },
  { symbol: "USDS", address: "0x820C137fa70C8691f0e44Dc420a5e53c168921Dc", balance: 0, value: 0 },
  { symbol: "USR", address: "0x35E5dB674D8e93a03d814FA0ADa70731efe8a4b9", balance: 0, value: 0 },
  { symbol: "VIRTUAL", address: "0x0b3e328455c4059EEb9e3f84b5543F74E24e7E1b", balance: 0, value: 0 },
  { symbol: "VVV", address: "0xacfE6019Ed1A7Dc6f7B508C02d1b04ec88cC21bf", balance: 0, value: 0 },
  { symbol: "WELL", address: "0xA88594D404727625A9437C3f886C7643872296AE", balance: 0, value: 0 },
  { symbol: "YFI", address: "0x9EaF8C1E34F05a589EDa6BAfdF391Cf6Ad3CB239", balance: 0, value: 0 },
  { symbol: "ZRO", address: "0x6985884C4392D348587B19cb9eAAf157F13271cd", balance: 0, value: 0 },
];

export const initialBaskets: BasketDraft[] = [
  { id: "stablecoins", name: "Stablecoins", color: "#6366f1", tokenAddresses: [USDC.address, USDT.address, DAI.address] },
  { id: "crypto-majors", name: "Crypto majors", color: "#a855f7", tokenAddresses: [WETH.address, WBTC.address] },
];
