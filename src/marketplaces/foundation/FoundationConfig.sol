// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.7;

import { BaseMarketConfig } from "../../../test/BaseMarketConfig.sol";

import { IFoundation } from "./interfaces/IFoundation.sol";

import {
    CallParameters,
    TestOrderContext,
    TestOrderPayload,
    Item721,
    Item1155,
    Item20
} from "../../../test/utils/Types.sol";

import { AdapterHelperLib } from "../../lib/AdapterHelperLib.sol";

contract FoundationConfig is BaseMarketConfig {
    function name() external pure override returns (string memory) {
        return "Foundation";
    }

    function market() public pure override returns (address) {
        return address(foundation);
    }

    IFoundation internal constant foundation =
        IFoundation(0xcDA72070E455bb31C7690a170224Ce43623d0B6f);

    function beforeAllPrepareMarketplace(address, address) external override {
        // ERC-20 n/a but currently required by the test suite

        buyerNftApprovalTarget = sellerNftApprovalTarget =
        buyerErc20ApprovalTarget =
            sellerErc20ApprovalTarget = address(foundation);
    }

    function getPayload_BuyOfferedERC721WithEther(
        TestOrderContext calldata context,
        Item721 calldata nft,
        uint256 ethAmount
    ) external pure override returns (TestOrderPayload memory execution) {
        if (!context.listOnChain) {
            _notImplemented();
        }

        execution.submitOrder = CallParameters(
            address(foundation),
            0,
            abi.encodeWithSelector(
                IFoundation.setBuyPrice.selector,
                nft.token,
                nft.identifier,
                ethAmount
            )
        );
        execution.executeOrder = CallParameters(
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
        Item721 memory nft,
        uint256 priceEthAmount,
        address feeRecipient,
        uint256 feeEthAmount
    ) external pure override returns (TestOrderPayload memory execution) {
        if (!context.listOnChain) {
            _notImplemented();
        }

        execution.submitOrder = CallParameters(
            address(foundation),
            0,
            abi.encodeWithSelector(
                IFoundation.setBuyPrice.selector,
                nft.token,
                nft.identifier,
                priceEthAmount
            )
        );
        execution.executeOrder = CallParameters(
            address(foundation),
            priceEthAmount + feeEthAmount,
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
        Item721 memory,
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
