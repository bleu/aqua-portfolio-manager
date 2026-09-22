// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Aqua} from "aqua/Aqua.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Safe} from "safe-smart-account/contracts/Safe.sol";
import {Enum} from "safe-smart-account/contracts/libraries/Enum.sol";
import {MultiSendCallOnly} from "safe-smart-account/contracts/libraries/MultiSendCallOnly.sol";
import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";
import {MakerTraitsLib} from "swap-vm/libs/MakerTraits.sol";
import {TakerTraitsLib} from "swap-vm/libs/TakerTraits.sol";

import {AquaE2EBase} from "./AquaE2EBase.t.sol";
import {PortfolioManagerRouter} from "../../../src/PortfolioManagerRouter.sol";
import {PortfolioManagerArgsCodec} from "../../../src/utils/PortfolioManagerArgsCodec.sol";
import {PortfolioManagerProgramBuilder} from "../../../src/utils/PortfolioManagerProgramBuilder.sol";
import {PortfolioManagerFee} from "../../../src/utils/PortfolioManagerFee.sol";
import {PortfolioManagerStrategyValidator} from "../../../src/PortfolioManagerStrategyValidator.sol";
import {MockTaker} from "../../../lib/swap-vm/test/mocks/MockTaker.sol";

/// @notice Deploys PM contracts and a WETH/DAI Safe with two single-member groups on the Base fork.
/// @dev This fixture omits the Guard to isolate pricing and fees. BasketScopeGuardE2E tests Guard behavior.
abstract contract PortfolioManagerE2EBase is AquaE2EBase {
    uint256 internal constant INITIAL_BALANCE = 100_000e18;
    uint256 internal constant FEE_BPS_SCALE = 1e9;

    /// @dev Below PortfolioManagerFee.TIER_THRESHOLD_BPS (≈0.1225%) — 1/4 tier.
    uint32 internal constant LOW_TIER_FEE_BPS = 0.02e9 / 100; // 2 bps, the existing ADR-0008 default

    /// @dev WETH predeploy address, standard across every OP-stack chain (Base included).
    address internal constant WETH_BASE = 0x4200000000000000000000000000000000000006;
    /// @dev DAI on Base — https://basescan.org/token/0x50c5725949a6f0c72e6c4a641f24049a917db0cb
    address internal constant DAI_BASE = 0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb;
    /// @dev Chainlink ETH/USD on Base — https://basescan.org/address/0x71041dddad3595f9ced3dccfbe3d1f4b0a16bb70
    address internal constant ETH_USD_FEED_BASE = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;
    /// @dev Chainlink DAI/USD on Base — https://basescan.org/address/0x591e79239a7d679378ec8c847e5038150364c78f
    address internal constant DAI_USD_FEED_BASE = 0x591e79239a7d679378eC8c847e5038150364C78F;
    /// @dev Keep feeds fresh to isolate curve and fee behavior.
    uint256 internal constant PM_MAX_STALENESS = 12 hours;

    PortfolioManagerRouter internal router;
    Safe internal pmSafe;
    IERC20 internal pmTokenA;
    IERC20 internal pmTokenB;
    MockTaker internal taker;
    PortfolioManagerStrategyValidator internal strategyValidator;
    MultiSendCallOnly internal multiSendCallOnly;

    PortfolioManagerArgsCodec.Group[] internal groups;

    function setUp() public virtual override {
        super.setUp();

        strategyValidator = new PortfolioManagerStrategyValidator();
        router = new PortfolioManagerRouter(
            address(aqua), WETH_BASE, deployer, "AquaPortfolioManager", "1", address(strategyValidator)
        );
        multiSendCallOnly = new MultiSendCallOnly();
        pmSafe = _newSafe(1); // distinct salt nonce from BasketScopeGuardE2E's/the multi-token fixture's Safes

        pmTokenA = IERC20(WETH_BASE);
        pmTokenB = IERC20(DAI_BASE);
        taker = new MockTaker(aqua, router, address(this));

        groups.push(_singleMemberGroup(0.5e18, address(pmTokenA), ETH_USD_FEED_BASE));
        groups.push(_singleMemberGroup(0.5e18, address(pmTokenB), DAI_USD_FEED_BASE));
    }

    function _singleMemberGroup(uint256 weight, address token, address feed)
        internal
        pure
        returns (PortfolioManagerArgsCodec.Group memory)
    {
        PortfolioManagerArgsCodec.Member[] memory members = new PortfolioManagerArgsCodec.Member[](1);
        members[0] = PortfolioManagerArgsCodec.Member({token: token, feed: feed, maxStaleness: PM_MAX_STALENESS});
        return PortfolioManagerArgsCodec.Group({weight: weight, members: members});
    }

    function _buildOrder(uint32 lpFeeBps) internal view returns (ISwapVM.Order memory) {
        bytes memory program = PortfolioManagerProgramBuilder.build(groups, lpFeeBps);

        return MakerTraitsLib.build(
            MakerTraitsLib.Args({
                maker: address(pmSafe),
                shouldUnwrapWeth: false,
                useAquaInsteadOfSignature: true,
                allowZeroAmountIn: false,
                receiver: address(0),
                hasPreTransferInHook: false,
                hasPostTransferInHook: false,
                hasPreTransferOutHook: false,
                hasPostTransferOutHook: false,
                preTransferInTarget: address(0),
                preTransferInData: "",
                postTransferInTarget: address(0),
                postTransferInData: "",
                preTransferOutTarget: address(0),
                preTransferOutData: "",
                postTransferOutTarget: address(0),
                postTransferOutData: "",
                program: program
            })
        );
    }

    /// @dev Fund the Safe with deal(), approve Aqua, then ship from the Safe.
    /// @param tokenInLedgerAmount TokenA authorization, independent of its INITIAL_BALANCE real funding.
    function _fundAndShip(ISwapVM.Order memory order, uint256 tokenInLedgerAmount) internal returns (bytes32) {
        deal(address(pmTokenA), address(pmSafe), INITIAL_BALANCE);
        deal(address(pmTokenB), address(pmSafe), INITIAL_BALANCE);

        vm.prank(address(pmSafe));
        pmTokenA.approve(address(aqua), type(uint256).max);
        vm.prank(address(pmSafe));
        pmTokenB.approve(address(aqua), type(uint256).max);

        address[] memory tokens = new address[](2);
        tokens[0] = address(pmTokenA);
        tokens[1] = address(pmTokenB);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = tokenInLedgerAmount;
        amounts[1] = INITIAL_BALANCE;

        bool ok = _shipOnly(order, tokens, amounts);
        require(ok, "ship through PM Safe failed");

        bytes32 strategyHash = keccak256(abi.encode(order));
        assertEq(strategyHash, router.hash(order), "strategy hash must match order hash");
        return strategyHash;
    }

    /// @dev Atomically attest and ship from pmSafe through MultiSendCallOnly, preserving the maker as Aqua's caller.
    ///      Makes one external call so callers can target it with expectRevert. Does not fund or approve.
    function _shipOnly(ISwapVM.Order memory order, address[] memory tokens, uint256[] memory amounts)
        internal
        returns (bool)
    {
        bytes memory attestData =
            abi.encodeCall(PortfolioManagerStrategyValidator.attestBuildParameters, (order, tokens));
        bytes memory shipData = abi.encodeCall(Aqua.ship, (address(router), abi.encode(order), tokens, amounts));

        bytes memory batch = abi.encodePacked(
            _encodeMultiSendTx(address(strategyValidator), attestData), _encodeMultiSendTx(address(aqua), shipData)
        );
        bytes memory multiSendData = abi.encodeCall(MultiSendCallOnly.multiSend, (batch));

        vm.prank(deployer);
        return pmSafe.execTransaction(
            address(multiSendCallOnly),
            0,
            multiSendData,
            Enum.Operation.DelegateCall,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            _selfApprovedSignature()
        );
    }

    /// @dev Packed MultiSendCallOnly entry: operation(1), to(20), value(32), dataLength(32), data.
    function _encodeMultiSendTx(address to, bytes memory data) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(0), to, uint256(0), data.length, data);
    }

    function _swapExactIn(ISwapVM.Order memory order, address tokenIn, address tokenOut, uint256 amount)
        internal
        returns (uint256, uint256)
    {
        bytes memory takerData = TakerTraitsLib.build(
            TakerTraitsLib.Args({
                taker: address(taker),
                isExactIn: true,
                shouldUnwrapWeth: false,
                isStrictThresholdAmount: false,
                isFirstTransferFromTaker: false,
                useTransferFromAndAquaPush: false,
                threshold: "",
                to: address(0),
                deadline: 0,
                hasPreTransferInCallback: true,
                hasPreTransferOutCallback: false,
                preTransferInHookData: "",
                postTransferInHookData: "",
                preTransferOutHookData: "",
                postTransferOutHookData: "",
                preTransferInCallbackData: "",
                preTransferOutCallbackData: "",
                instructionsArgs: "",
                signature: ""
            })
        );

        deal(tokenIn, address(taker), amount * 2);
        return taker.swap(order, tokenIn, tokenOut, amount, takerData);
    }
}
