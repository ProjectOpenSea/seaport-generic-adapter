// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

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

import { TestCallParameters } from "../../test/utils/Types.sol";

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
    // using SpentItemLib for SpentItem;
    // using SpentItemLib for SpentItem[];

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

    function createSeaportWrappedTestCallParameters(
        TestCallParameters memory testCallParameters,
        address seaport,
        address flashloanOfferer,
        address adapter,
        address weth,
        address nftAddress
    )
        public
        view
        returns (TestCallParameters memory wrappedTestCallParameter)
    {
        wrappedTestCallParameter.target = seaport;
        uint256 value = testCallParameters.value;
        wrappedTestCallParameter.value = value;

        ConsiderationItem[] memory considerationArray =
            new ConsiderationItem[](1);
        OrderParameters memory orderParameters;
        AdvancedOrder memory order;
        AdvancedOrder[] memory orders = new AdvancedOrder[](3);
        bytes memory extraData;
        Fulfillment[] memory fulfillments;

        // Create the adapter order.
        order = AdvancedOrderLib.empty().withNumerator(1).withDenominator(1);

        considerationArray[0] = ConsiderationItemLib.empty().withItemType(
            ItemType.NATIVE
        ).withToken(address(0)).withIdentifierOrCriteria(0).withStartAmount(
            value
        ).withEndAmount(value).withRecipient(address(0));

        {
            orderParameters = OrderParametersLib.fromDefault(
                "baseOrderParameters"
            ).withOfferer(adapter);
            orderParameters = orderParameters.withOrderType(OrderType.CONTRACT);
            orderParameters = orderParameters.withOffer(new OfferItem[](0))
                .withConsideration(considerationArray)
                .withTotalOriginalConsiderationItems(1);

            order = order.withParameters(orderParameters);
        }

        {
            Call[] memory calls = new Call[](1);

            Call memory callMarketplace = Call(
                address(testCallParameters.target),
                false,
                value,
                testCallParameters.data
            );

            calls[0] = callMarketplace;

            // Include approvals for the NFT and the WETH.
            Approval[] memory approvals = new Approval[](2);
            Approval memory approvalNFT = Approval(nftAddress, ItemType.ERC721);
            Approval memory approvalWETH = Approval(weth, ItemType.ERC20);
            approvals[0] = approvalNFT;
            approvals[1] = approvalWETH;

            extraData = createGenericAdapterContext(approvals, calls);
        }

        order = order.withExtraData(extraData);
        orders[1] = order;

        // Create the flashloan, if necessary.
        if (value > 0) {
            order = AdvancedOrderLib.empty().withNumerator(1).withDenominator(1);

            // Remember to deal the WETH before yeeting this.
            considerationArray[0] = ConsiderationItemLib.empty().withItemType(
                ItemType.ERC20
            ).withToken(address(weth)).withIdentifierOrCriteria(0)
                .withStartAmount(value).withEndAmount(value).withRecipient(
                address(0)
            );

            {
                // Think about how to handle this.
                orderParameters = OrderParametersLib.empty().withOfferer(
                    address(this)
                ).withOrderType(OrderType.FULL_OPEN).withStartTime(
                    block.timestamp
                ).withEndTime(block.timestamp + 100)
                    .withTotalOriginalConsiderationItems(0) // TODO: make sure this address is the offerer.
                    .withOfferer(flashloanOfferer);
                orderParameters =
                    orderParameters.withOrderType(OrderType.CONTRACT);
                orderParameters = orderParameters.withOffer(new OfferItem[](0));
                orderParameters =
                    orderParameters.withConsideration(considerationArray);
                orderParameters =
                    orderParameters.withTotalOriginalConsiderationItems(1);

                order.withParameters(orderParameters);
            }

            Flashloan memory flashloan = Flashloan(uint88(value), true, adapter);
            Flashloan[] memory flashloans = new Flashloan[](1);
            flashloans[0] = flashloan;

            extraData = createFlashloanContext(address(this), flashloans);

            // Add it all to the order.
            order.withExtraData(extraData);
            orders[0] = order;

            // TODO: Make sure the native and weth sides are squared up properly.

            // Build the mirror order.
            {
                order =
                    AdvancedOrderLib.empty().withNumerator(1).withDenominator(1);
                // Create the parameters for the order.
                {
                    OfferItem[] memory offerItems = new OfferItem[](1);
                    offerItems[0] = OfferItemLib.empty().withItemType(
                        ItemType.NATIVE
                    ).withToken(address(0)).withIdentifierOrCriteria(0)
                        .withStartAmount(value).withEndAmount(value);

                    orderParameters = OrderParametersLib.empty().withOfferer(
                        address(this)
                    ).withOrderType(OrderType.FULL_OPEN).withStartTime(
                        block.timestamp
                    ).withEndTime(block.timestamp + 100).withConsideration(
                        new ConsiderationItem[](0)
                    ).withTotalOriginalConsiderationItems(0).withOffer(
                        offerItems
                    );

                    order = order.withParameters(orderParameters);
                    orders[2] = order;
                }
            }

            // Create the fulfillments.
            fulfillments = new Fulfillment[](2);
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

                fulfillments[0] = Fulfillment(
                    offerComponentsFlashloan, considerationComponentsFlashloan
                );
                fulfillments[1] = Fulfillment(
                    offerComponentsMirror, considerationComponentsMirror
                );
            }
        } else {
            orders = new AdvancedOrder[](1);
            orders[0] = order;

            // Create the fulfillments?
            fulfillments = new Fulfillment[](0);
        }

        abi.encodeWithSelector(
            ConsiderationInterface.matchAdvancedOrders.selector,
            orders,
            new CriteriaResolver[](0),
            fulfillments,
            address(0)
        );
    }
}
