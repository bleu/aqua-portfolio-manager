// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Aqua} from "aqua/Aqua.sol";
import {Safe} from "safe-smart-account/contracts/Safe.sol";
import {Enum} from "safe-smart-account/contracts/libraries/Enum.sol";
import {MultiSendCallOnly} from "safe-smart-account/contracts/libraries/MultiSendCallOnly.sol";
import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";
import {MakerTraitsLib} from "swap-vm/libs/MakerTraits.sol";
import {PortfolioManagerArgsCodec} from "../src/utils/PortfolioManagerArgsCodec.sol";
import {PortfolioManagerProgramBuilder} from "../src/utils/PortfolioManagerProgramBuilder.sol";
import {PortfolioManagerStrategyValidator} from "../src/PortfolioManagerStrategyValidator.sol";

/// @notice Ships a real 2-group basket (majors: WETH+cbBTC, stables: USDC+USDT, 50/50 weight,
///         equal split within each group) through the already-deployed Router/Validator and the
///         user's own Safe, funded ahead of time. One Safe transaction: approve Aqua for all 4
///         tokens, attest, and ship, batched via MultiSendCallOnly (mirrors
///         PortfolioManagerMultiTokenBasketE2E.t.sol's `_shipOnly`, but against a real Safe via
///         `execTransaction` + an approved-hash signature instead of `vm.prank`).
contract ShipStrategy is Script {
    address internal constant AQUA_BASE = 0x499943E74FB0cE105688beeE8Ef2ABec5D936d31;
    address internal constant MULTI_SEND_CALL_ONLY = 0x9641d764fc13c8B624c04430C7356C1C7C8102e2;

    address internal constant ROUTER = 0x02a11927B0a1c701FEB589Ca86886F4ae1F85f02;
    address internal constant VALIDATOR = 0x88F52Fe4A35aD046f37BcF3eB01E99551aa7dA92;

    address internal constant WETH = 0x4200000000000000000000000000000000000006;
    address internal constant CBBTC = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;
    address internal constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address internal constant USDT = 0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2;

    address internal constant ETH_USD_FEED = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;
    address internal constant CBBTC_USD_FEED = 0x07DA0E54543a844a80ABE69c8A12F22B3aA59f9D;
    address internal constant USDC_USD_FEED = 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B;
    address internal constant USDT_USD_FEED = 0xf19d560eB8d2ADf07BD6D13ed03e1D11215721F9;

    uint256 internal constant MAX_STALENESS = 12 hours;
    uint32 internal constant LP_FEE_BPS = 200_000; // 2bps on the 1e9 scale, matching this repo's existing default
    uint256 internal constant GROUP_WEIGHT = 0.5e18;

    function run() external {
        uint256 ownerKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(ownerKey);
        address safeAddr = vm.envAddress("SAFE_ADDRESS");
        Safe safe = Safe(payable(safeAddr));

        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](2);
        groups[0] = _majors();
        groups[1] = _stables();

        bytes memory program = PortfolioManagerProgramBuilder.build(groups, LP_FEE_BPS, 0);
        ISwapVM.Order memory order = MakerTraitsLib.build(
            MakerTraitsLib.Args({
                maker: safeAddr,
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

        address[] memory tokens = new address[](4);
        tokens[0] = WETH;
        tokens[1] = CBBTC;
        tokens[2] = USDC;
        tokens[3] = USDT;

        uint256[] memory amounts = new uint256[](4);
        for (uint256 i = 0; i < 4; i++) {
            amounts[i] = IERC20(tokens[i]).balanceOf(safeAddr);
            require(amounts[i] > 0, "token not funded in Safe");
        }

        bytes memory batch = "";
        for (uint256 i = 0; i < 4; i++) {
            batch = abi.encodePacked(
                batch, _encodeMultiSendTx(tokens[i], abi.encodeCall(IERC20.approve, (AQUA_BASE, type(uint256).max)))
            );
        }
        batch = abi.encodePacked(
            batch,
            _encodeMultiSendTx(
                VALIDATOR, abi.encodeCall(PortfolioManagerStrategyValidator.attestBuildParameters, (order, tokens))
            ),
            _encodeMultiSendTx(AQUA_BASE, abi.encodeCall(Aqua.ship, (ROUTER, abi.encode(order), tokens, amounts)))
        );

        bytes memory multiSendData = abi.encodeCall(MultiSendCallOnly.multiSend, (batch));
        bytes memory signature = abi.encodePacked(bytes32(uint256(uint160(owner))), bytes32(0), uint8(1));

        vm.startBroadcast(ownerKey);
        bool ok = safe.execTransaction(
            MULTI_SEND_CALL_ONLY,
            0,
            multiSendData,
            Enum.Operation.DelegateCall,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            signature
        );
        vm.stopBroadcast();

        require(ok, "ship through Safe failed");

        bytes32 strategyHash = keccak256(abi.encode(order));
        console.log("strategy shipped, hash:");
        console.logBytes32(strategyHash);
    }

    function _majors() internal pure returns (PortfolioManagerArgsCodec.Group memory) {
        PortfolioManagerArgsCodec.Member[] memory members = new PortfolioManagerArgsCodec.Member[](2);
        members[0] = PortfolioManagerArgsCodec.Member({token: WETH, feed: ETH_USD_FEED, maxStaleness: MAX_STALENESS});
        members[1] = PortfolioManagerArgsCodec.Member({token: CBBTC, feed: CBBTC_USD_FEED, maxStaleness: MAX_STALENESS});
        return PortfolioManagerArgsCodec.Group({weight: GROUP_WEIGHT, members: members});
    }

    function _stables() internal pure returns (PortfolioManagerArgsCodec.Group memory) {
        PortfolioManagerArgsCodec.Member[] memory members = new PortfolioManagerArgsCodec.Member[](2);
        members[0] = PortfolioManagerArgsCodec.Member({token: USDC, feed: USDC_USD_FEED, maxStaleness: MAX_STALENESS});
        members[1] = PortfolioManagerArgsCodec.Member({token: USDT, feed: USDT_USD_FEED, maxStaleness: MAX_STALENESS});
        return PortfolioManagerArgsCodec.Group({weight: GROUP_WEIGHT, members: members});
    }

    function _encodeMultiSendTx(address to, bytes memory data) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(0), to, uint256(0), data.length, data);
    }
}
