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
    // This deployment's own router/validator, not a well-known external address -- unlike the
    // token/feed addresses below, there's nothing else in the repo to deduplicate this against.
    address internal constant ROUTER = 0x02a11927B0a1c701FEB589Ca86886F4ae1F85f02;
    address internal constant VALIDATOR = 0x88F52Fe4A35aD046f37BcF3eB01E99551aa7dA92;

    uint32 internal constant LP_FEE_BPS = 200_000; // 2bps on the 1e9 scale, matching this repo's existing default
    uint256 internal constant GROUP_WEIGHT = 0.5e18;

    function run() external {
        // Base mainnet addresses live in packages/addresses/base-mainnet.json, shared with the
        // TypeScript side (packages/addresses/src/index.ts) -- read live, nothing to regenerate.
        // Run this script with `FOUNDRY_PROFILE=deploy forge script ...`: reading outside this
        // project's own root needs foundry.toml's [profile.deploy] fs_permissions.
        string memory addresses = vm.readFile("../addresses/base-mainnet.json");
        address aqua = vm.parseJsonAddress(addresses, ".aqua");
        uint256 maxStaleness = vm.parseJsonUint(addresses, ".maxStalenessSeconds");

        // Parsed once here, threaded through to _majors/_stables and reused below for the
        // approve/ship batch -- not re-parsed from the same JSON paths a second time.
        address[] memory tokens = new address[](4);
        tokens[0] = vm.parseJsonAddress(addresses, ".tokens.WETH.address");
        tokens[1] = vm.parseJsonAddress(addresses, ".tokens.CBBTC.address");
        tokens[2] = vm.parseJsonAddress(addresses, ".tokens.USDC.address");
        tokens[3] = vm.parseJsonAddress(addresses, ".tokens.USDT.address");

        uint256 ownerKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(ownerKey);
        address safeAddr = vm.envAddress("SAFE_ADDRESS");
        Safe safe = Safe(payable(safeAddr));

        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](2);
        groups[0] = _majors(addresses, maxStaleness, tokens[0], tokens[1]);
        groups[1] = _stables(addresses, maxStaleness, tokens[2], tokens[3]);

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

        uint256[] memory amounts = new uint256[](4);
        for (uint256 i = 0; i < 4; i++) {
            amounts[i] = IERC20(tokens[i]).balanceOf(safeAddr);
            require(amounts[i] > 0, "token not funded in Safe");
        }

        bytes memory batch = "";
        for (uint256 i = 0; i < 4; i++) {
            batch = abi.encodePacked(
                batch, _encodeMultiSendTx(tokens[i], abi.encodeCall(IERC20.approve, (aqua, type(uint256).max)))
            );
        }
        batch = abi.encodePacked(
            batch,
            _encodeMultiSendTx(
                VALIDATOR, abi.encodeCall(PortfolioManagerStrategyValidator.attestBuildParameters, (order, tokens))
            ),
            _encodeMultiSendTx(aqua, abi.encodeCall(Aqua.ship, (ROUTER, abi.encode(order), tokens, amounts)))
        );

        bytes memory multiSendData = abi.encodeCall(MultiSendCallOnly.multiSend, (batch));
        bytes memory signature = abi.encodePacked(bytes32(uint256(uint160(owner))), bytes32(0), uint8(1));

        vm.startBroadcast(ownerKey);
        bool ok = safe.execTransaction(
            vm.parseJsonAddress(addresses, ".multiSendCallOnly"),
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

    function _majors(string memory addresses, uint256 maxStaleness, address weth, address cbbtc)
        internal
        pure
        returns (PortfolioManagerArgsCodec.Group memory)
    {
        PortfolioManagerArgsCodec.Member[] memory members = new PortfolioManagerArgsCodec.Member[](2);
        members[0] = PortfolioManagerArgsCodec.Member({
            token: weth, feed: vm.parseJsonAddress(addresses, ".tokens.WETH.feedProxy"), maxStaleness: maxStaleness
        });
        members[1] = PortfolioManagerArgsCodec.Member({
            token: cbbtc, feed: vm.parseJsonAddress(addresses, ".tokens.CBBTC.feedProxy"), maxStaleness: maxStaleness
        });
        return PortfolioManagerArgsCodec.Group({weight: GROUP_WEIGHT, members: members});
    }

    function _stables(string memory addresses, uint256 maxStaleness, address usdc, address usdt)
        internal
        pure
        returns (PortfolioManagerArgsCodec.Group memory)
    {
        PortfolioManagerArgsCodec.Member[] memory members = new PortfolioManagerArgsCodec.Member[](2);
        members[0] = PortfolioManagerArgsCodec.Member({
            token: usdc, feed: vm.parseJsonAddress(addresses, ".tokens.USDC.feedProxy"), maxStaleness: maxStaleness
        });
        members[1] = PortfolioManagerArgsCodec.Member({
            token: usdt, feed: vm.parseJsonAddress(addresses, ".tokens.USDT.feedProxy"), maxStaleness: maxStaleness
        });
        return PortfolioManagerArgsCodec.Group({weight: GROUP_WEIGHT, members: members});
    }

    function _encodeMultiSendTx(address to, bytes memory data) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(0), to, uint256(0), data.length, data);
    }
}
