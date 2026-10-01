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
import {BaseMainnetAddresses} from "./generated/BaseMainnetAddresses.sol";

/// @notice Ships a real 2-group basket (majors: WETH+cbBTC, stables: USDC+USDT, 50/50 weight,
///         equal split within each group) through the already-deployed Router/Validator and the
///         user's own Safe, funded ahead of time. One Safe transaction: approve Aqua for all 4
///         tokens, attest, and ship, batched via MultiSendCallOnly (mirrors
///         PortfolioManagerMultiTokenBasketE2E.t.sol's `_shipOnly`, but against a real Safe via
///         `execTransaction` + an approved-hash signature instead of `vm.prank`).
contract ShipStrategy is Script {
    address internal constant ROUTER = 0x02a11927B0a1c701FEB589Ca86886F4ae1F85f02;
    address internal constant VALIDATOR = 0x88F52Fe4A35aD046f37BcF3eB01E99551aa7dA92;

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
        tokens[0] = BaseMainnetAddresses.WETH;
        tokens[1] = BaseMainnetAddresses.CBBTC;
        tokens[2] = BaseMainnetAddresses.USDC;
        tokens[3] = BaseMainnetAddresses.USDT;

        uint256[] memory amounts = new uint256[](4);
        for (uint256 i = 0; i < 4; i++) {
            amounts[i] = IERC20(tokens[i]).balanceOf(safeAddr);
            require(amounts[i] > 0, "token not funded in Safe");
        }

        bytes memory batch = "";
        for (uint256 i = 0; i < 4; i++) {
            batch = abi.encodePacked(
                batch,
                _encodeMultiSendTx(
                    tokens[i], abi.encodeCall(IERC20.approve, (BaseMainnetAddresses.AQUA, type(uint256).max))
                )
            );
        }
        batch = abi.encodePacked(
            batch,
            _encodeMultiSendTx(
                VALIDATOR, abi.encodeCall(PortfolioManagerStrategyValidator.attestBuildParameters, (order, tokens))
            ),
            _encodeMultiSendTx(
                BaseMainnetAddresses.AQUA, abi.encodeCall(Aqua.ship, (ROUTER, abi.encode(order), tokens, amounts))
            )
        );

        bytes memory multiSendData = abi.encodeCall(MultiSendCallOnly.multiSend, (batch));
        bytes memory signature = abi.encodePacked(bytes32(uint256(uint160(owner))), bytes32(0), uint8(1));

        vm.startBroadcast(ownerKey);
        bool ok = safe.execTransaction(
            BaseMainnetAddresses.MULTI_SEND_CALL_ONLY,
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
        members[0] = PortfolioManagerArgsCodec.Member({
            token: BaseMainnetAddresses.WETH,
            feed: BaseMainnetAddresses.ETH_USD_FEED,
            maxStaleness: BaseMainnetAddresses.MAX_STALENESS
        });
        members[1] = PortfolioManagerArgsCodec.Member({
            token: BaseMainnetAddresses.CBBTC,
            feed: BaseMainnetAddresses.CBBTC_USD_FEED,
            maxStaleness: BaseMainnetAddresses.MAX_STALENESS
        });
        return PortfolioManagerArgsCodec.Group({weight: GROUP_WEIGHT, members: members});
    }

    function _stables() internal pure returns (PortfolioManagerArgsCodec.Group memory) {
        PortfolioManagerArgsCodec.Member[] memory members = new PortfolioManagerArgsCodec.Member[](2);
        members[0] = PortfolioManagerArgsCodec.Member({
            token: BaseMainnetAddresses.USDC,
            feed: BaseMainnetAddresses.USDC_USD_FEED,
            maxStaleness: BaseMainnetAddresses.MAX_STALENESS
        });
        members[1] = PortfolioManagerArgsCodec.Member({
            token: BaseMainnetAddresses.USDT,
            feed: BaseMainnetAddresses.USDT_USD_FEED,
            maxStaleness: BaseMainnetAddresses.MAX_STALENESS
        });
        return PortfolioManagerArgsCodec.Group({weight: GROUP_WEIGHT, members: members});
    }

    function _encodeMultiSendTx(address to, bytes memory data) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(0), to, uint256(0), data.length, data);
    }
}
