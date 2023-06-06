// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.7;

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

contract FoundationConfig is BaseMarketConfig {
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

    function beforeAllPrepareMarketplace(address, address) external override {
        // ERC-20 n/a but currently required by the test suite
        buyerNftApprovalTarget = sellerNftApprovalTarget =
        buyerErc20ApprovalTarget =
            sellerErc20ApprovalTarget = address(foundation);
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

        if (context.routeThroughAdapter) {
            // Call needed to actually execute the order
            TestCallParameters memory baseExecuteOrder = execution.executeOrder;

            // TestCallParameters memory testCallParameters,
            // address seaport,
            // address flashloanOfferer,
            // address adapter,
            // address weth,
            // address nftAddress

            execution.executeOrder = AdapterEncodingHelperLib
                .createSeaportWrappedTestCallParameters(
                baseExecuteOrder,
                address(seaport),
                address(flashloanOfferer), // TODO
                address(adapter), // TODO
                address(weth), // TODO
                address(nft.token)
            );
        }
    }

    function getPayload_BuyOfferedERC721WithEtherOneFeeRecipient(
        TestOrderContext calldata context,
        TestItem721 memory nft,
        uint256 priceEthAmount,
        address feeRecipient,
        uint256
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
