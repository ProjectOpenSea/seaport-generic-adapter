// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.7;

import { StdCheats } from "forge-std/StdCheats.sol";

import { BaseMarketConfig } from "../../../test/BaseMarketConfig.sol";

import { IFoundation } from "./interfaces/IFoundation.sol";

import { ConsiderationInterface as ISeaport } from
    "seaport-types/interfaces/ConsiderationInterface.sol";

import {
    TestCallParameters,
    TestOrderContext,
    TestOrderPayload,
    TestItem721,
    TestItem1155,
    TestItem20
} from "../../../test/utils/Types.sol";

import { AdapterEncodingHelperLib } from
    "../../lib/AdapterEncodingHelperLib.sol";

import { FlashloanOffererInterface } from
    "../../interfaces/FlashloanOffererInterface.sol";

import { GenericAdapterInterface } from
    "../../interfaces/GenericAdapterInterface.sol";

import { GenericAdapterSidecarInterface } from
    "../../interfaces/GenericAdapterSidecarInterface.sol";

import { Vm } from "forge-std/Vm.sol";

import "forge-std/console.sol";

address constant VM_ADDRESS =
    address(uint160(uint256(keccak256("hevm cheat code"))));
Vm constant vm = Vm(VM_ADDRESS);

contract FoundationConfig is BaseMarketConfig, StdCheats {
    GenericAdapterInterface testAdapter;
    FlashloanOffererInterface testFlashloanOfferer;

    function name() external pure override returns (string memory) {
        return "Foundation";
    }

    function market() public pure override returns (address) {
        return address(foundation);
    }

    IFoundation internal constant foundation =
        IFoundation(0xcDA72070E455bb31C7690a170224Ce43623d0B6f);

    ISeaport internal constant seaport =
        ISeaport(0x00000000000001ad428e4906aE43D8F9852d0dD6);

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    function beforeAllPrepareMarketplace(address, address) external override {
        // ERC-20 n/a but currently required by the test suite
        buyerNftApprovalTarget = sellerNftApprovalTarget =
        buyerErc20ApprovalTarget =
            sellerErc20ApprovalTarget = address(foundation);

        // TODO: figure out how to do this like a civilized person, ideally a
        //       level or two up from here.

        bytes memory bytecode = abi.encodePacked(
            vm.getCode("out/FlashloanOfferer.sol/FlashloanOfferer.json"),
            abi.encode(address(seaport))
        );
        address addr;
        assembly {
            addr := create(0, add(bytecode, 0x20), mload(bytecode))
        }

        testFlashloanOfferer = FlashloanOffererInterface(addr);

        vm.recordLogs();

        testAdapter = GenericAdapterInterface(
            deployCode(
                "out/GenericAdapter.sol/GenericAdapter.json",
                abi.encode(address(seaport), address(testFlashloanOfferer))
            )
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();

        GenericAdapterSidecarInterface testSidecar =
        GenericAdapterSidecarInterface(abi.decode(entries[0].data, (address)));

        flashloanOfferer = address(testFlashloanOfferer);
        adapter = address(testAdapter);
        sidecar = address(testSidecar);
    }

    function getPayload_BuyOfferedERC721WithEther(
        TestOrderContext calldata context,
        TestItem721 calldata nft,
        uint256 ethAmount
    ) external pure override returns (TestOrderPayload memory execution) {
        if (!context.listOnChain) {
            _notImplemented();
        }

        execution.submitOrder = TestCallParameters(
            address(foundation),
            0,
            abi.encodeWithSelector(
                IFoundation.setBuyPrice.selector,
                nft.token,
                nft.identifier,
                ethAmount
            )
        );
        execution.executeOrder = TestCallParameters(
            address(foundation),
            ethAmount,
            abi.encodeWithSelector(
                IFoundation.buyV2.selector,
                nft.token,
                nft.identifier,
                ethAmount,
                address(0)
            )
        );
    }

    function getPayload_BuyOfferedERC721WithEtherOneFeeRecipient(
        TestOrderContext calldata context,
        TestItem721 memory nft,
        uint256 priceEthAmount,
        address feeRecipient,
        uint256
    ) external override returns (TestOrderPayload memory execution) {
        if (!context.listOnChain) {
            console.log("!context.listOnChain");
            _notImplemented();
        }

        console.log("context.listOnChain");

        execution.submitOrder = TestCallParameters(
            address(foundation),
            0,
            abi.encodeWithSelector(
                IFoundation.setBuyPrice.selector,
                nft.token,
                nft.identifier,
                priceEthAmount
            )
        );
        execution.executeOrder = TestCallParameters(
            address(foundation),
            priceEthAmount,
            abi.encodeWithSelector(
                IFoundation.buyV2.selector,
                nft.token,
                nft.identifier,
                priceEthAmount,
                feeRecipient
            )
        );

        if (context.routeThroughAdapter) {
            // Call needed to actually execute the order
            TestCallParameters memory baseExecuteOrder = execution.executeOrder;

            console.log("CALLING MY FUNCTION");

            deal(address(WETH), address(context.fulfiller), priceEthAmount);
            vm.deal(flashloanOfferer, priceEthAmount);
            vm.prank(context.fulfiller);
            (bool success,) = WETH.call(
                abi.encodeWithSignature(
                    "approve(address,uint256)", address(seaport), priceEthAmount
                )
            );

            if (!success) {
                revert("Failed to approve WETH");
            }

            execution.executeOrder = AdapterEncodingHelperLib
                .createSeaportWrappedTestCallParameters(
                baseExecuteOrder,
                address(context.fulfiller),
                address(seaport),
                address(flashloanOfferer),
                address(adapter),
                address(sidecar),
                address(WETH),
                nft
            );
        }
    }

    function getPayload_BuyOfferedERC721WithEtherTwoFeeRecipient(
        TestOrderContext calldata context,
        TestItem721 memory,
        uint256,
        address,
        uint256,
        address,
        uint256
    ) external pure override returns (TestOrderPayload memory) {
        if (!context.listOnChain) {
            _notImplemented();
        }

        // TODO: pending sell referrer support
        _notImplemented();
    }
}
