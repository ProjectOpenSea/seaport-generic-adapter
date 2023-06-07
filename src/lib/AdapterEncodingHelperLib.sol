// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC721 } from "solady/src/tokens/ERC721.sol";

import { AdvancedOrderLib } from "seaport-sol/lib/AdvancedOrderLib.sol";

import { ConsiderationItemLib } from "seaport-sol/lib/ConsiderationItemLib.sol";

import { OfferItemLib } from "seaport-sol/lib/OfferItemLib.sol";

import { OrderParametersLib } from "seaport-sol/lib/OrderParametersLib.sol";

import { SpentItemLib } from "seaport-sol/lib/SpentItemLib.sol";

import { ItemType, OrderType } from "seaport-types/lib/ConsiderationEnums.sol";

import { ConsiderationInterface } from
    "seaport-types/interfaces/ConsiderationInterface.sol";

import { Call } from "../interfaces/GenericAdapterSidecarInterface.sol";

import {
    AdvancedOrder,
    ConsiderationItem,
    CriteriaResolver,
    Fulfillment,
    FulfillmentComponent,
    OfferItem,
    OrderParameters
} from "seaport-sol/SeaportStructs.sol";

import { TestCallParameters, TestItem721 } from "../../test/utils/Types.sol";

import "forge-std/console.sol";

interface IWETH {
    function deposit() external payable;

    function withdraw(uint256) external;

    function balanceOf(address) external view returns (uint256);

    function approve(address, uint256) external returns (bool);
}

struct Flashloan {
    uint88 amount;
    bool shouldCallback;
    address recipient;
}

struct Approval {
    address token;
    ItemType itemType;
}

/**
 * @title AdapterEncodingHelperLib
 * @author snotrocket.eth
 * @notice AdapterEncodingHelperLib is a library for generating the context
 *         arguments expected by the Flashloan Offerer and the Generic Adapter.
 */
library AdapterEncodingHelperLib {
    using AdvancedOrderLib for AdvancedOrder;
    using ConsiderationItemLib for ConsiderationItem;
    using ConsiderationItemLib for ConsiderationItem[];
    using OfferItemLib for OfferItem;
    using OfferItemLib for OfferItem[];
    using OrderParametersLib for OrderParameters;

    function createFlashloanContext(
        address cleanupRecipient,
        Flashloan[] memory flashloans
    ) public pure returns (bytes memory extraData) {
        // Create the value that will populate the extraData field.
        // When the flashloan offerer receives the call to
        // generateOrder, it will decode the extraData field into
        // instructions for handling the flashloan.

        // A word for the encoding, a byte for the number of flashloans, 20
        // bytes for the cleanup recipient, and 32 bytes for each flashloan.
        uint256 flashloanContextArgSize = 32 + 1 + 20 + (32 * flashloans.length);

        extraData = new bytes(flashloanContextArgSize);

        // The first byte is the SIP encoding (0). The 1s are just
        // placeholders. They're ignored by the flashloan offerer.
        // The 4 bytes of 0s at the end will eventually contain the
        // size of the extraData field.
        uint256 firstWord =
            0x0011111111111111111111111111111111111111111111111111111100000000;
        firstWord = firstWord | flashloanContextArgSize;

        // Set the cleanup recipient in the first 20 bytes of the
        // second word.
        uint256 secondWord = uint256(uint160(cleanupRecipient)) << 96;
        // Set the flashloan length.
        secondWord = secondWord | ((flashloans.length) << 88);

        // Pack the first two words into the extraData field.
        extraData = abi.encodePacked(firstWord, secondWord);

        uint256 amount;
        uint256 shouldCallback;
        uint256 recipient;
        uint256 packedFlashloan;

        // Iterate over each flashloan and stick the values where they belong.
        for (uint256 i; i < flashloans.length; i++) {
            // Pack each Flashloan into a word of memory.
            Flashloan memory flashloan = flashloans[i];
            amount = flashloan.amount;
            shouldCallback = flashloan.shouldCallback ? 1 : 0;
            recipient = uint256(uint160(flashloan.recipient));

            assembly {
                packedFlashloan :=
                    or(shl(168, amount), or(shl(160, shouldCallback), recipient))
            }

            // Make Space for the next flashloan.
            extraData = abi.encodePacked(extraData, bytes32(0));

            // Iterate over each byte of the packed flashloan and stick it
            // in the extraData field.
            for (uint256 j = 0; j < 32; j++) {
                extraData[53 + (i * 32) + j] = bytes32(packedFlashloan)[j];
            }
        }

        return extraData;
    }

    function createGenericAdapterContext(
        Approval[] memory approvals,
        Call[] memory calls
    ) public pure returns (bytes memory extraData) {
        // Create the value that will populate the extraData field on a generic
        // adapter call. When the generic adapter receives the call to
        // generateOrder, it will decode the extraData field into instructions
        // for handling both approvals and calls to be made by the sidecar.

        uint256 secondWord = 0 | ((approvals.length) << 248);

        // The first word can be all zeros for now. The size will be added to
        // the last four bytes later.
        extraData = abi.encodePacked(bytes32(0), secondWord);

        // Iterate over approvals and stick them in the extraData field.
        for (uint256 i; i < approvals.length; ++i) {
            Approval memory approval = approvals[i];
            // The approval type is even for ERC20 or odd for ERC721 / 1155 and
            // is converted to 0 or 1.
            uint256 approvalType;

            assembly {
                approvalType := gt(mload(add(0x20, approval)), 1)
            }

            uint256 approvalToken = uint256(uint160(approval.token));

            // Pack the approval into a word of memory.
            uint256 packedApproval =
                (approvalType << 248) | (approvalToken << 88);

            // Make Space for the next approval (this is overkill but should be
            // harmless because it's cleaned up later).
            extraData = abi.encodePacked(extraData, bytes32(0));

            // Iterate over each byte of the packed approval and stick it
            // in the extraData field.
            for (uint256 j = 0; j < 21; j++) {
                // One word for encoding, one word for total approvals, 21 bytes
                // per approval.
                extraData[33 + (i * 21) + j] = bytes32(packedApproval)[j];
            }
        }

        {
            // Trim down the trailing zeros on the extraData field.
            uint256 encodingAndApprovalSize = (32 + 1 + (21 * approvals.length));
            bytes memory trimmedExtraData = new bytes(encodingAndApprovalSize);

            for (uint256 j = 0; j < encodingAndApprovalSize; j++) {
                trimmedExtraData[j] = extraData[j];
            }

            extraData = trimmedExtraData;
        }

        // Add the calls to the extraData field.
        bytes memory contextArgCalldataPortion = abi.encode(calls);
        extraData = abi.encodePacked(extraData, contextArgCalldataPortion);

        // Add the size of the extraData field to the first word.
        uint256 extraDataSize = extraData.length;

        for (uint256 i; i < 32; i++) {
            extraData[i] = bytes32(extraDataSize)[i];
        }
    }

    struct AdapterWrapInfra {
        ConsiderationItem[] considerationArray;
        OrderParameters orderParameters;
        AdvancedOrder order;
        AdvancedOrder[] orders;
        Flashloan flashloan;
        Flashloan[] flashloans;
        Call call;
        Call[] calls;
        bytes extraData;
        Fulfillment[] fulfillments;
    }

    function createSeaportWrappedTestCallParameters(
        TestCallParameters memory testCallParameters,
        address fulfiller,
        address seaport,
        address flashloanOfferer,
        address adapter,
        address sidecar,
        address weth,
        TestItem721 memory nft
    )
        public
        view
        returns (TestCallParameters memory wrappedTestCallParameter)
    {
        {
            wrappedTestCallParameter.target = seaport;
            wrappedTestCallParameter.value = testCallParameters.value;
        }

        console.log("IN MY FUNCTION");

        // TODO: Straighten this out. And then use it throughout to fix stack
        // pressure issues.
        AdapterWrapInfra memory infra = AdapterWrapInfra(
            new ConsiderationItem[](1),
            OrderParametersLib.empty(),
            AdvancedOrderLib.empty(),
            new AdvancedOrder[](3),
            Flashloan(0, false, address(0)),
            new Flashloan[](1),
            Call(address(0), false, 0, bytes("")),
            new Call[](1),
            new bytes(0),
            new Fulfillment[](3)
        );

        {
            // Create the adapter order.
            infra.order =
                AdvancedOrderLib.empty().withNumerator(1).withDenominator(1);

            infra.considerationArray[0] = ConsiderationItemLib.empty()
                .withItemType(ItemType.NATIVE).withToken(address(0))
                .withIdentifierOrCriteria(0).withStartAmount(
                testCallParameters.value
            ).withEndAmount(testCallParameters.value).withRecipient(address(0));

            {
                infra.orderParameters = OrderParametersLib.empty().withOrderType(
                    OrderType.FULL_OPEN
                ).withStartTime(block.timestamp).withEndTime(
                    block.timestamp + 100
                ).withConsideration(new ConsiderationItem[](0))
                    .withTotalOriginalConsiderationItems(0).withOfferer(adapter);
                infra.orderParameters =
                    infra.orderParameters.withOrderType(OrderType.CONTRACT);
                infra.orderParameters = infra.orderParameters.withOffer(
                    new OfferItem[](0)
                ).withConsideration(infra.considerationArray)
                    .withTotalOriginalConsiderationItems(1);

                infra.order = infra.order.withParameters(infra.orderParameters);
            }

            infra.calls = new Call[](2);

            {
                infra.call = Call(
                    address(testCallParameters.target),
                    false,
                    testCallParameters.value,
                    testCallParameters.data
                );

                infra.calls[0] = infra.call;

                infra.call = Call(
                    address(nft.token),
                    false,
                    0,
                    abi.encodeWithSelector(
                        ERC721.transferFrom.selector,
                        address(sidecar), // TODO: get the sidecar address and pass it through.
                        address(fulfiller),
                        nft.identifier
                    )
                );

                infra.calls[1] = infra.call;
            }

            {
                // Include approvals for the NFT and the WETH.
                Approval[] memory approvals = new Approval[](2);
                Approval memory approvalNFT =
                    Approval(nft.token, ItemType.ERC721);
                Approval memory approvalWETH = Approval(weth, ItemType.ERC20);
                approvals[0] = approvalNFT;
                approvals[1] = approvalWETH;

                infra.extraData =
                    createGenericAdapterContext(approvals, infra.calls);
            }

            infra.order = infra.order.withExtraData(infra.extraData);
            infra.orders[1] = infra.order;
        }

        // Create the flashloan, if necessary.
        if (testCallParameters.value > 0) {
            {
                infra.order =
                    AdvancedOrderLib.empty().withNumerator(1).withDenominator(1);
            }

            {
                // Remember to deal the WETH before yeeting this.
                infra.considerationArray[0] = ConsiderationItemLib.empty()
                    .withItemType(ItemType.NATIVE).withToken(address(0))
                    .withIdentifierOrCriteria(0).withStartAmount(
                    testCallParameters.value
                ).withEndAmount(testCallParameters.value).withRecipient(
                    address(0)
                );
            }

            {
                // Think about how to handle this.
                infra.orderParameters = OrderParametersLib.empty();
                infra.orderParameters =
                    infra.orderParameters.withOfferer(address(fulfiller));
                infra.orderParameters = infra.orderParameters.withOrderType(
                    OrderType.FULL_OPEN
                ).withStartTime(block.timestamp);
                infra.orderParameters =
                    infra.orderParameters.withEndTime(block.timestamp + 100);
                infra.orderParameters =
                    infra.orderParameters.withTotalOriginalConsiderationItems(0);
                infra.orderParameters =
                    infra.orderParameters.withOfferer(flashloanOfferer);
                infra.orderParameters =
                    infra.orderParameters.withOrderType(OrderType.CONTRACT);
                infra.orderParameters =
                    infra.orderParameters.withOffer(new OfferItem[](0));
                infra.orderParameters = infra.orderParameters.withConsideration(
                    infra.considerationArray
                );
                infra.orderParameters =
                    infra.orderParameters.withTotalOriginalConsiderationItems(1);

                infra.order.withParameters(infra.orderParameters);
            }

            {
                infra.flashloan =
                    Flashloan(uint88(testCallParameters.value), true, adapter);
                infra.flashloans = new Flashloan[](1);
                infra.flashloans[0] = infra.flashloan;

                infra.extraData =
                    createFlashloanContext(address(fulfiller), infra.flashloans);

                // Add it all to the order.
                infra.order.withExtraData(infra.extraData);
                infra.orders[0] = infra.order;
            }

            // TODO: Make sure the native and weth sides are squared up properly.

            // Build the mirror order.
            {
                infra.order =
                    AdvancedOrderLib.empty().withNumerator(1).withDenominator(1);
                // Create the parameters for the order.
                {
                    OfferItem[] memory offerItems = new OfferItem[](1);
                    offerItems[0] = OfferItemLib.empty().withItemType(
                        ItemType.NATIVE
                    ).withToken(address(0)).withIdentifierOrCriteria(0)
                        .withStartAmount(testCallParameters.value).withEndAmount(
                        testCallParameters.value
                    );

                    infra.orderParameters = OrderParametersLib.empty();
                    infra.orderParameters =
                        infra.orderParameters.withOfferer(address(fulfiller));
                    infra.orderParameters =
                        infra.orderParameters.withOrderType(OrderType.FULL_OPEN);
                    infra.orderParameters =
                        infra.orderParameters.withStartTime(block.timestamp);
                    infra.orderParameters =
                        infra.orderParameters.withEndTime(block.timestamp + 100);
                    infra.orderParameters = infra
                        .orderParameters
                        .withConsideration(new ConsiderationItem[](0));
                    infra.orderParameters = infra
                        .orderParameters
                        .withTotalOriginalConsiderationItems(0);
                    infra.orderParameters =
                        infra.orderParameters.withOffer(offerItems);
                    infra.order =
                        infra.order.withParameters(infra.orderParameters);
                    infra.orders[2] = infra.order;
                }
            }

            // Create the fulfillments.
            infra.fulfillments = new Fulfillment[](2);
            {
                FulfillmentComponent[] memory offerComponentsFlashloan =
                    new FulfillmentComponent[](1);
                FulfillmentComponent[] memory considerationComponentsFlashloan =
                    new FulfillmentComponent[](1);
                FulfillmentComponent[] memory offerComponentsMirror =
                    new FulfillmentComponent[](1);
                FulfillmentComponent[] memory considerationComponentsMirror =
                    new FulfillmentComponent[](1);

                offerComponentsFlashloan[0] = FulfillmentComponent(0, 0);
                considerationComponentsFlashloan[0] = FulfillmentComponent(2, 0);
                offerComponentsMirror[0] = FulfillmentComponent(2, 0);
                considerationComponentsMirror[0] = FulfillmentComponent(0, 0);

                infra.fulfillments[0] = Fulfillment(
                    offerComponentsFlashloan, considerationComponentsFlashloan
                );
                infra.fulfillments[1] = Fulfillment(
                    offerComponentsMirror, considerationComponentsMirror
                );
            }
        } else {
            infra.orders = new AdvancedOrder[](1);
            infra.orders[0] = infra.order;

            // Create the fulfillments?
            infra.fulfillments = new Fulfillment[](0);
        }

        console.log("infra.fulfillments.length", infra.fulfillments.length);

        wrappedTestCallParameter.data = abi.encodeWithSelector(
            ConsiderationInterface.matchAdvancedOrders.selector,
            infra.orders,
            new CriteriaResolver[](0),
            infra.fulfillments,
            address(0)
        );
    }
}
