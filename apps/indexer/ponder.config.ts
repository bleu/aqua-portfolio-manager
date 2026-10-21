// See docs/adr/0014-production-arbitrageur-design.md for the design this implements, and
// README.md for the overall picture. Migrated from Envio HyperIndex to Ponder: Envio's free-tier
// HyperSync access rate-limited a full-history sync (from Aqua's own genesis block) to an
// impractical crawl; Ponder syncs over plain JSON-RPC, so it scales with whatever RPC endpoint
// it's given instead of a shared free-tier indexing service.
import { createConfig, factory } from "ponder";
import { AquaAbi } from "./abis/AquaAbi";
import { ChainlinkAggregatorAbi } from "./abis/ChainlinkAggregatorAbi";
import { ChainlinkProxyAbi } from "./abis/ChainlinkProxyAbi";
import { Erc20Abi } from "./abis/Erc20Abi";
import { PortfolioManagerValidatorAbi } from "./abis/PortfolioManagerValidatorAbi";

// Aqua's own deployment block on Base is 38281777 (verified directly: eth_getCode is empty at
// 38281776, present at 38281777) -- ADR-0011's off-chain "check prior active strategies" check
// wants `strategy` rows covering a maker's full history, not just activity since our own Router
// existed, so that's the block this should start from.
//
// It doesn't, for a reason outside this repo: the configured BASE_RPC_URL is a pruned RPC node,
// not a full archive one -- confirmed directly by testing, with the exact error "pruned history
// unavailable: requested 38420064, earliest available 52500000". This is the earliest block that
// endpoint can actually serve. Getting real genesis-to-now history needs an archive-tier RPC
// (either upgrading the current provider's plan or pointing BASE_RPC_URL at a different one) --
// a billing/provider decision, not something fixable here. Until then, this covers everything
// from shortly before this deployment's own real contracts went live onward, which includes every
// strategy anyone can actually test against today.
const AQUA_GENESIS_BLOCK = 52_500_000;

// This deployment's own real contracts (packages/contracts/broadcast/Deploy.s.sol/8453/
// run-latest.json) -- the ERC20/Chainlink side of this schema (Wallet Balance Change / Oracle
// Price, ADR-0014) only exists to serve apps/arbitrageur, which has no use for history predating
// this deployment. Scoping these to it, not Aqua's genesis, avoids an enormous, pointless scan of
// every Transfer ever emitted by four of Base's most active tokens.
const DEPLOYMENT_BLOCK = 52827562;

const CHAINLINK_PROXIES = {
  weth: "0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70", // ETH/USD
  cbbtc: "0x07DA0E54543a844a80ABE69c8A12F22B3aA59f9D", // cbBTC/USD
  usdt: "0xf19d560eB8d2ADf07BD6D13ed03e1D11215721F9", // USDT/USD
  usdc: "0x7e860098F58bBFC8648a4311b374B1D669a2bc6B", // USDC/USD
} as const;

// Each proxy's `aggregator()` result as of 2026-09-28 (see ../../packages/addresses/src/index.ts's
// SEED_AGGREGATOR_TO_PROXY, which src/index.ts's handler also reads). A swap between
// DEPLOYMENT_BLOCK and whenever a feed's first `AggregatorConfirmed` lands after that is covered
// by this seed list being watched from DEPLOYMENT_BLOCK directly; every swap from here forward is
// covered by the `factory()` contract below, which watches AggregatorConfirmed itself.
const CHAINLINK_SEED_AGGREGATORS = [
  "0x05c84a58FE042275b37db038bAAcD15F410c7bB0", // ETH/USD
  "0x51cE3091Cf646587E02Cad83b580992f8723e718", // cbBTC/USD
  "0x84640bB7b71B0963E8EB57AD379A0B204eb2fdc8", // USDT/USD
  "0x68bE4C50235205Ede361ac8244B1ee221CDDA5E2", // USDC/USD
] as const;

export default createConfig({
  chains: {
    base: {
      id: 8453,
      // The paid DRPC endpoint -- a public RPC can't sustain a full-history `eth_getLogs` crawl
      // at a reasonable pace (confirmed: the Envio free tier hit an equivalent wall from the
      // other direction, HyperSync's own rate limit).
      rpc: process.env.BASE_RPC_URL!,
      // Without this, Ponder sizes each eth_getLogs request by block count alone, not response
      // size -- USDC/USDT/WETH/cbBTC's Transfer volume on Base packs thousands of logs into a
      // span of a few dozen blocks, and the resulting single JSON.parse of that response crashed
      // the indexer with "JavaScript heap out of memory" on a real deploy. A fixed, small range
      // bounds response size directly, independent of how dense any one window turns out to be.
      ethGetLogsBlockRange: 50,
    },
  },
  contracts: {
    Aqua: {
      abi: AquaAbi,
      chain: "base",
      address: "0x499943e74fb0ce105688beee8ef2abec5d936d31",
      startBlock: AQUA_GENESIS_BLOCK,
    },
    PortfolioManagerValidator: {
      abi: PortfolioManagerValidatorAbi,
      chain: "base",
      // The real, current deployment -- not ShipTestStrategy.s.sol's old VALIDATOR constant, an
      // earlier test deployment. Only affects strategy.groupNames enrichment for our own app;
      // strategy detection itself comes from Aqua's own Shipped/Docked events regardless of which
      // validator attested it.
      address: "0xf554918152B8a4543E41e6eA381eD425A03A93cE",
      startBlock: AQUA_GENESIS_BLOCK,
    },
    // ADR-0014's token allow list (USDC, USDT, WETH, cbBTC) -- one contract definition since
    // every ERC20 shares the same Transfer event, listed once per address below. The handler
    // filters to Transfers touching a known Strategy Wallet; every other Transfer on these
    // tokens (the vast majority) is indexed too and discarded in-handler, not filtered at the
    // source, since the wallet set is only known from already-indexed strategy data.
    ERC20: {
      abi: Erc20Abi,
      chain: "base",
      address: [
        "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913", // USDC
        "0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2", // USDT
        "0x4200000000000000000000000000000000000006", // WETH
        "0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf", // cbBTC
      ],
      startBlock: DEPLOYMENT_BLOCK,
    },
    // ADR-0014's Oracle Price record. Each feed's well-known address is an `EACAggregatorProxy`
    // that never emits `AnswerUpdated` itself -- only its current underlying aggregator does,
    // and Chainlink can swap that aggregator over time. AggregatorConfirmed is what announces a
    // swap.
    ChainlinkProxy: {
      abi: ChainlinkProxyAbi,
      chain: "base",
      address: Object.values(CHAINLINK_PROXIES),
      startBlock: DEPLOYMENT_BLOCK,
    },
    // The known aggregator behind each feed as of setup -- watched directly from
    // DEPLOYMENT_BLOCK, since a `factory()` contract (below) only discovers a child address from
    // the moment its own creation event is indexed forward, not retroactively.
    ChainlinkAggregatorSeed: {
      abi: ChainlinkAggregatorAbi,
      chain: "base",
      address: CHAINLINK_SEED_AGGREGATORS,
      startBlock: DEPLOYMENT_BLOCK,
    },
    // Every aggregator a feed proxy swaps to *after* DEPLOYMENT_BLOCK -- discovered dynamically
    // from ChainlinkProxy's own AggregatorConfirmed event, the same way Envio's contractRegister
    // handler did.
    ChainlinkAggregatorDynamic: {
      abi: ChainlinkAggregatorAbi,
      chain: "base",
      address: factory({
        address: Object.values(CHAINLINK_PROXIES),
        event: ChainlinkProxyAbi[0],
        parameter: "latest",
      }),
      startBlock: DEPLOYMENT_BLOCK,
    },
  },
});
