// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC20 } from "solady/src/tokens/ERC20.sol";

import { ERC721 } from "solady/src/tokens/ERC721.sol";

import { ERC1155 } from "solady/src/tokens/ERC1155.sol";

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

import {
    CallParameters,
    Item20,
    Item721,
    Item1155
} from "../../test/utils/Types.sol";

import "forge-std/console.sol";

/**
 * @dev A Flashloan is a struct that specifies the amount, type, and recipient
 *      of a flashloan, and whether or not the cleanup function should be
 *      called.  The amount is the amount of native tokens requested. The amount
 *      requested has to be less than or equal to the amount offered in the
 *      consideration. The type is the type of consideration that will be
 *      provided. shouldCallback is a boolean that specifies whether the cleanup
 *      function on the adapter should be called. The recipient is the address
 *      that will receive the flashloan, e.g. the address of the adapter.
 *
 */
struct Flashloan {
    uint88 amount;
    ItemType itemType;
    bool shouldCallback;
    address recipient;
}

/**
 * @dev A Fulfillment is a struct that specifies the address and item type of
 *      a token that needs to be approved.
 *
 */
struct Approval {
    address token;
    ItemType itemType;
}

/**
 * @dev The CastOfCharacters is a struct that specifies the addresses of the
 *      participants in a given order. The offerer is the address that created
 *      the liquidity that's being consumed. The fulfiller is the address that
 *      is calling Seaport to consume the liquidity.
 *
 */
struct CastOfCharacters {
    address offerer;
    address fulfiller;
    address seaport;
    address flashloanOfferer;
    address adapter;
    address sidecar;
}

struct ItemTransfer {
    address from;
    address to;
    address token;
    uint256 identifier;
    uint256 amount;
    ItemType itemType;
}

/**
 * @title AdapterHelperLib
 * @author snotrocket.eth
 * @notice AdapterHelperLib is a library for generating the context
 *         arguments expected by the Flashloan Offerer and the Generic Adapter.
 */
library AdapterHelperLib {
    using AdvancedOrderLib for AdvancedOrder;
    using ConsiderationItemLib for ConsiderationItem;
    using ConsiderationItemLib for ConsiderationItem[];
    using OfferItemLib for OfferItem;
    using OfferItemLib for OfferItem[];
    using OrderParametersLib for OrderParameters;

    /**
     * @dev Create the context/extraData argument that goes into an
     *      AdvancedOrder. This function will encode the high level requirements
     *      specified by the arguments into a single bytes field according to
     *      the excpectations of the FlashloanOfferer. When the FlashloanOfferer
     *      receives the call to its generateOrder function, it will decode the
     *      extraData field into instructions for handling the flashloan.
     *
     * @param cleanupRecipient The address that should receive the leftover
     *                         native tokens after the order has been processed.
     * @param flashloans       An array of structs, each of which specifies the
     *                         amount, type, and recipient of a flashloan, and
     *                         whether or not the cleanup function should be
     *                         called.
     *
     * @return extraData The extraData for the order that triggers a flashloan.
     */
    function createFlashloanContext(
        address cleanupRecipient,
        Flashloan[] memory flashloans
    ) public pure returns (bytes memory extraData) {
        // When the flashloan offerer receives the call to generateOrder, it
        // will decode the extraData field into instructions for handling the
        // flashloan.

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

    /**
     * @dev Create the context/extraData argument that goes into an
     *      AdvancedOrder. This function will encode the high level requirements
     *      specified by the arguments into a single bytes field according to
     *      the excpectations of the Generic Adapter. When the Generic Adapter
     *      receives the call to its generateOrder function, it will decode the
     *      extraData field into instructions for handling both approvals and
     *      calls to be made by the sidecar.
     *
     * @param approvals An array of structs, each of which specifies the token
     *                  and item type of an approval that needs to be made.
     * @param calls     An array of structs, each of which specifies the target,
     *                  value, and callData of a call that needs to be made.
     *
     */
    function createGenericAdapterContext(
        Approval[] memory approvals,
        Call[] memory calls
    ) public pure returns (bytes memory extraData) {
        // Set the length of the approvals array in the second word.
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

    ////////////////////////////////////////////////////////////////////////////
    //                      A bunch of different interfaces.                  //
    //                  The meat is at the bottom of all these.               //
    ////////////////////////////////////////////////////////////////////////////

    function createSeaportWrappedCallParameters(
        CallParameters memory callParameters,
        CastOfCharacters memory castOfCharacters,
        OfferItem[] memory adapterOffer,
        ConsiderationItem[] memory adapterConsideration,
        Item721 memory nft
    ) public view returns (CallParameters memory) {
        Flashloan[] memory flashloans = new Flashloan[](0);

        if (callParameters.value > 0) {
            flashloans = _getFlashloanArrayFromParams(
                uint88(callParameters.value),
                ItemType.NATIVE,
                true,
                castOfCharacters.adapter
            );
        }

        ItemTransfer[] memory itemTransfers = new ItemTransfer[](1);
        itemTransfers[0] = ItemTransfer({
            from: castOfCharacters.sidecar,
            to: castOfCharacters.fulfiller,
            token: nft.token,
            identifier: nft.identifier,
            amount: 1,
            itemType: ItemType.ERC721
        });

        return createSeaportWrappedCallParameters(
            callParameters,
            castOfCharacters,
            flashloans,
            adapterOffer,
            adapterConsideration,
            itemTransfers
        );
    }

    function createSeaportWrappedCallParameters(
        CallParameters memory callParameters,
        CastOfCharacters memory castOfCharacters,
        OfferItem[] memory adapterOffer,
        ConsiderationItem[] memory adapterConsideration,
        Item721[] memory nfts
    ) public view returns (CallParameters memory) {
        Flashloan[] memory flashloans = new Flashloan[](0);

        if (callParameters.value > 0) {
            flashloans = _getFlashloanArrayFromParams(
                uint88(callParameters.value),
                ItemType.NATIVE,
                true,
                castOfCharacters.adapter
            );
        }

        ItemTransfer[] memory itemTransfers = new ItemTransfer[](nfts.length);
        for (uint256 i; i < nfts.length; i++) {
            itemTransfers[i] = ItemTransfer({
                from: castOfCharacters.sidecar,
                to: castOfCharacters.fulfiller,
                token: nfts[i].token,
                identifier: nfts[i].identifier,
                amount: 1,
                itemType: ItemType.ERC721
            });
        }

        return createSeaportWrappedCallParameters(
            callParameters,
            castOfCharacters,
            flashloans,
            adapterOffer,
            adapterConsideration,
            itemTransfers
        );
    }

    function createSeaportWrappedCallParameters(
        CallParameters memory callParameters,
        CastOfCharacters memory castOfCharacters,
        OfferItem[] memory adapterOffer,
        ConsiderationItem[] memory adapterConsideration,
        Item1155 memory nft
    ) public view returns (CallParameters memory) {
        Flashloan[] memory flashloans = new Flashloan[](0);

        if (callParameters.value > 0) {
            flashloans = _getFlashloanArrayFromParams(
                uint88(callParameters.value),
                ItemType.NATIVE,
                true,
                castOfCharacters.adapter
            );
        }

        ItemTransfer[] memory itemTransfers = new ItemTransfer[](1);
        itemTransfers[0] = ItemTransfer({
            from: castOfCharacters.sidecar,
            to: castOfCharacters.fulfiller,
            token: nft.token,
            identifier: nft.identifier,
            amount: nft.amount,
            itemType: ItemType.ERC1155
        });

        return createSeaportWrappedCallParameters(
            callParameters,
            castOfCharacters,
            flashloans,
            adapterOffer,
            adapterConsideration,
            itemTransfers
        );
    }

    function createSeaportWrappedCallParameters(
        CallParameters memory callParameters,
        CastOfCharacters memory castOfCharacters,
        OfferItem[] memory adapterOffer,
        ConsiderationItem[] memory adapterConsideration,
        Item20[] memory erc20s
    ) public view returns (CallParameters memory) {
        CallParameters[] memory callParametersArray = new CallParameters[](1);
        callParametersArray[0] = callParameters;
        Flashloan[] memory flashloans = new Flashloan[](0);

        if (callParameters.value > 0) {
            flashloans = new Flashloan[](1);
            Flashloan memory flashloan = Flashloan({
                amount: uint88(callParameters.value),
                itemType: ItemType.NATIVE,
                shouldCallback: true,
                recipient: castOfCharacters.adapter
            });
            flashloans[0] = flashloan;
        }

        ItemTransfer[] memory itemTransfers = new ItemTransfer[](erc20s.length);
        for (uint256 i; i < erc20s.length; i++) {
            itemTransfers[i] = ItemTransfer({
                from: castOfCharacters.sidecar,
                to: castOfCharacters.fulfiller,
                token: erc20s[i].token,
                identifier: 0,
                amount: erc20s[i].amount,
                itemType: ItemType.ERC20
            });
        }

        return createSeaportWrappedCallParameters(
            callParametersArray,
            castOfCharacters,
            new Call[](0),
            new Call[](0),
            flashloans,
            adapterOffer,
            adapterConsideration,
            itemTransfers
        );
    }

    function createSeaportWrappedCallParameters(
        CallParameters memory callParameters,
        CastOfCharacters memory castOfCharacters,
        OfferItem[] memory adapterOffer,
        ConsiderationItem[] memory adapterConsideration,
        ItemTransfer[] memory itemTransfers
    ) public view returns (CallParameters memory) {
        CallParameters[] memory callParametersArray = new CallParameters[](1);
        callParametersArray[0] = callParameters;

        return createSeaportWrappedCallParameters(
            callParametersArray,
            castOfCharacters,
            new Call[](0),
            new Call[](0),
            new Flashloan[](0),
            adapterOffer,
            adapterConsideration,
            itemTransfers
        );
    }

    function createSeaportWrappedCallParameters(
        CallParameters memory callParameters,
        CastOfCharacters memory castOfCharacters,
        Flashloan[] memory flashloans,
        OfferItem[] memory adapterOffer,
        ConsiderationItem[] memory adapterConsideration,
        ItemTransfer[] memory itemTransfers
    ) public view returns (CallParameters memory) {
        CallParameters[] memory callParametersArray = new CallParameters[](1);
        callParametersArray[0] = callParameters;

        return createSeaportWrappedCallParameters(
            callParametersArray,
            castOfCharacters,
            new Call[](0),
            new Call[](0),
            flashloans,
            adapterOffer,
            adapterConsideration,
            itemTransfers
        );
    }

    function createSeaportWrappedCallParameters(
        CallParameters[] memory callParametersArray,
        CastOfCharacters memory castOfCharacters,
        Call[] memory sidecarSetUpCalls,
        Call[] memory sidecarWrapUpCalls,
        Flashloan[] memory flashloans,
        OfferItem[] memory adapterOffer,
        ConsiderationItem[] memory adapterConsideration,
        ItemTransfer[] memory itemTransfers
    ) public view returns (CallParameters memory wrappedCallParameters) {
        AdvancedOrder[] memory orders;
        Fulfillment[] memory fulfillments;
        (orders, fulfillments) =
        createSeaportWrappedCallParametersReturnGranular(
            callParametersArray,
            castOfCharacters,
            sidecarSetUpCalls,
            sidecarWrapUpCalls,
            flashloans,
            adapterOffer,
            adapterConsideration,
            itemTransfers
        );

        wrappedCallParameters.data = abi.encodeWithSelector(
            ConsiderationInterface.matchAdvancedOrders.selector,
            orders,
            new CriteriaResolver[](0),
            fulfillments,
            address(0)
        );

        uint256 value;

        for (uint256 i; i < callParametersArray.length; ++i) {
            value += callParametersArray[i].value;
        }

        wrappedCallParameters.value = value;
        wrappedCallParameters.target = castOfCharacters.seaport;
    }

    struct AdapterWrapperInfra {
        CallParameters[] callParametersArray;
        CastOfCharacters castOfCharacters;
        Call[] sidecarSetUpCalls;
        Call[] sidecarWrapUpCalls;
        ItemTransfer[] itemTransfers;
        OfferItem[] adapterOffer;
        ConsiderationItem[] adapterConsideration;
        OrderParameters orderParameters;
        AdvancedOrder order;
        AdvancedOrder[] orders;
        Flashloan flashloan;
        Flashloan[] flashloans;
        Call call;
        Call[] calls;
        bytes extraData;
        Fulfillment[] fulfillments;
        uint256 value;
        uint256 totalFlashloanValueRequested;
    }

    /**
     * @dev This function is used to create a set of orders and fulfillments
     *      that can be passed into matchAdvancedOrders to fulfill an arbitrary
     *      number of orders on external marketplaces. It expects that the calls
     *      to external marketplaces are pre-rolled into the callParameters
     *      array. This function will wrap up those calls into an order that
     *      hits the generic adapter, which passes them along to the sidecar. It
     *      also creates a single pair of orders for an arbitrary number of
     *      flashloans, if any are passed in. It returns the orders and
     *      fulfillments separately.
     *
     * @param callParametersArray An array of CallParameters structs
     *                                that contain the target, value, and
     *                                calldata for the calls to external
     *                                marketplaces.
     * @param castOfCharacters        A CastOfCharacters struct that contains
     *                                the addresses of the relevant
     *                                participants.
     * @param flashloans              An array of Flashloan structs that contain
     *                                the flashloan parameters.
     * @param adapterOffer            An array of OfferItem structs that
     *                                contain the offer for the generic
     *                                adapter order. A purchaser of NFTs from
     *                                external marketplaces will put the stuff
     *                                they expect to get from the function call
     *                                in here and Seaport will ensure that they
     *                                either get the stuff or the tx reverts.
     * @param adapterConsideration    An array of ConsiderationItem structs that
     *                                contain the consideration for the generic
     *                                adapter order. The consideration will be
     *                                passed along to the sidecar, where it's
     *                                used to fulfill the orders on external
     *                                marketplaces.
     * @param itemTransfers           An array of itemTransfer structs that
     *                                contain the info for instructing the
     *                                sidecar to transfer an item.
     *
     */
    function createSeaportWrappedCallParametersReturnGranular(
        CallParameters[] memory callParametersArray,
        CastOfCharacters memory castOfCharacters,
        Call[] memory sidecarSetUpCalls,
        Call[] memory sidecarWrapUpCalls,
        Flashloan[] memory flashloans,
        OfferItem[] memory adapterOffer,
        ConsiderationItem[] memory adapterConsideration,
        ItemTransfer[] memory itemTransfers
    )
        public
        view
        returns (
            AdvancedOrder[] memory orders,
            Fulfillment[] memory fulfillments
        )
    {
        AdapterWrapperInfra memory infra = AdapterWrapperInfra({
            callParametersArray: callParametersArray,
            castOfCharacters: castOfCharacters,
            sidecarSetUpCalls: sidecarSetUpCalls,
            sidecarWrapUpCalls: sidecarWrapUpCalls,
            itemTransfers: itemTransfers,
            adapterOffer: adapterOffer,
            adapterConsideration: adapterConsideration,
            orderParameters: OrderParametersLib.empty(),
            order: AdvancedOrderLib.empty(),
            orders: new AdvancedOrder[](3),
            flashloan: Flashloan(0, ItemType.NATIVE, false, address(0)),
            flashloans: flashloans,
            call: Call(address(0), false, 0, bytes("")),
            calls: new Call[](1),
            extraData: new bytes(0),
            fulfillments: new Fulfillment[](3),
            value: 0,
            totalFlashloanValueRequested: 0
        });

        // Set the value to send.
        for (uint256 i; i < callParametersArray.length; ++i) {
            infra.value += callParametersArray[i].value;
        }

        // Only create a default flashloan if it's necessary and none is passed
        // in explicitly.
        if (infra.value > 0 && flashloans.length == 0) {
            infra.flashloans = new Flashloan[](1);
            Flashloan memory flashloan = Flashloan({
                amount: uint88(infra.value),
                itemType: ItemType.NATIVE, // TODO: make this flexible (weth)
                shouldCallback: true,
                recipient: castOfCharacters.adapter
            });
            infra.flashloans[0] = flashloan;
        }

        _createAdapterOrder(infra);

        if (infra.flashloans.length > 0) {
            _createFlashloanOrdersAndFulfillments(infra);
        }

        _createFulfillments(infra);

        return (infra.orders, infra.fulfillments);
    }

    function _createAdapterOrder(AdapterWrapperInfra memory infra)
        internal
        view
    {
        // Create the adapter order.
        infra.order =
            AdvancedOrderLib.empty().withNumerator(1).withDenominator(1);

        {
            infra.orderParameters = OrderParametersLib.empty().withOrderType(
                OrderType.FULL_OPEN
            ).withStartTime(block.timestamp).withEndTime(block.timestamp + 100)
                .withTotalOriginalConsiderationItems(0).withOfferer(
                infra.castOfCharacters.adapter
            );
            infra.orderParameters = infra.orderParameters.withSalt(gasleft());
            infra.orderParameters =
                infra.orderParameters.withOrderType(OrderType.CONTRACT);
            infra.orderParameters = infra.orderParameters.withOffer(
                infra.adapterOffer
            ).withConsideration(infra.adapterConsideration)
                .withTotalOriginalConsiderationItems(
                infra.adapterConsideration.length
            );

            infra.order = infra.order.withParameters(infra.orderParameters);
        }

        infra.calls =
        new Call[](infra.sidecarSetUpCalls.length + infra.callParametersArray.length + infra.itemTransfers.length + infra.sidecarWrapUpCalls.length);

        {
            for (uint256 i; i < infra.sidecarSetUpCalls.length; i++) {
                infra.calls[i] = infra.sidecarSetUpCalls[i];
            }

            for (uint256 i = 0; i < infra.callParametersArray.length; i++) {
                infra.calls[infra.sidecarSetUpCalls.length + i] = Call(
                    address(infra.callParametersArray[i].target),
                    false,
                    infra.callParametersArray[i].value,
                    infra.callParametersArray[i].data
                );
            }

            Call[] memory tokenCalls =
                _createTokenTransferCalls(infra.itemTransfers);

            // Populate the calls array with the NFT transfer calls from the
            // helper.
            for (uint256 i = 0; i < tokenCalls.length; i++) {
                infra.calls[infra.sidecarSetUpCalls.length
                    + infra.callParametersArray.length + i] = tokenCalls[i];
            }

            for (uint256 i = 0; i < infra.sidecarWrapUpCalls.length; i++) {
                infra.calls[infra.sidecarSetUpCalls.length
                    + infra.callParametersArray.length + tokenCalls.length + i] =
                    infra.sidecarWrapUpCalls[i];
            }
        }

        {
            infra.extraData =
                createGenericAdapterContext(new Approval[](0), infra.calls);
        }

        infra.order = infra.order.withExtraData(infra.extraData);
        infra.orders[1] = infra.order;
    }

    function _createFlashloanOrdersAndFulfillments(
        AdapterWrapperInfra memory infra
    ) internal view {
        {
            infra.order =
                AdvancedOrderLib.empty().withNumerator(1).withDenominator(1);
        }

        {
            for (uint256 i = 0; i < infra.flashloans.length; i++) {
                infra.totalFlashloanValueRequested += infra.flashloans[i].amount;
            }

            infra.adapterConsideration = new ConsiderationItem[](1);

            // Come back and think about the case where multiple flashloans
            // of different types are required.
            infra.adapterConsideration[0] = ConsiderationItemLib.empty()
                .withItemType(infra.flashloans[0].itemType).withToken(address(0))
                .withIdentifierOrCriteria(0).withStartAmount(
                infra.totalFlashloanValueRequested
            ).withEndAmount(infra.totalFlashloanValueRequested).withRecipient(
                address(0)
            );
        }

        {
            infra.orderParameters = OrderParametersLib.empty();
            infra.orderParameters = infra.orderParameters.withSalt(gasleft());
            infra.orderParameters = infra.orderParameters.withOfferer(
                address(infra.castOfCharacters.fulfiller)
            );
            infra.orderParameters = infra.orderParameters.withOrderType(
                OrderType.FULL_OPEN
            ).withStartTime(block.timestamp);
            infra.orderParameters =
                infra.orderParameters.withEndTime(block.timestamp + 100);
            infra.orderParameters =
                infra.orderParameters.withTotalOriginalConsiderationItems(0);
            infra.orderParameters = infra.orderParameters.withOfferer(
                infra.castOfCharacters.flashloanOfferer
            );
            infra.orderParameters =
                infra.orderParameters.withOrderType(OrderType.CONTRACT);
            infra.orderParameters =
                infra.orderParameters.withOffer(new OfferItem[](0));
            infra.orderParameters = infra.orderParameters.withConsideration(
                infra.adapterConsideration
            );
            infra.orderParameters =
                infra.orderParameters.withTotalOriginalConsiderationItems(1);

            infra.order.withParameters(infra.orderParameters);
        }

        {
            infra.extraData = createFlashloanContext(
                address(infra.castOfCharacters.fulfiller), infra.flashloans
            );

            // Add it all to the order.
            infra.order.withExtraData(infra.extraData);
            infra.orders[0] = infra.order;
        }

        // Build the mirror order.
        {
            infra.order =
                AdvancedOrderLib.empty().withNumerator(1).withDenominator(1);
            // Create the parameters for the order.
            {
                OfferItem[] memory offerItems = new OfferItem[](1);
                offerItems[0] = OfferItemLib.empty().withItemType(
                    infra.flashloans[0].itemType
                ).withToken(address(0)).withIdentifierOrCriteria(0)
                    .withStartAmount(infra.totalFlashloanValueRequested)
                    .withEndAmount(infra.totalFlashloanValueRequested);

                infra.orderParameters = OrderParametersLib.empty();
                infra.orderParameters =
                    infra.orderParameters.withSalt(gasleft());
                infra.orderParameters = infra.orderParameters.withOfferer(
                    address(infra.castOfCharacters.fulfiller)
                );
                infra.orderParameters =
                    infra.orderParameters.withOrderType(OrderType.FULL_OPEN);
                infra.orderParameters =
                    infra.orderParameters.withStartTime(block.timestamp);
                infra.orderParameters =
                    infra.orderParameters.withEndTime(block.timestamp + 100);
                infra.orderParameters = infra.orderParameters.withConsideration(
                    new ConsiderationItem[](0)
                );
                infra.orderParameters =
                    infra.orderParameters.withTotalOriginalConsiderationItems(0);
                infra.orderParameters =
                    infra.orderParameters.withOffer(offerItems);
                infra.order = infra.order.withParameters(infra.orderParameters);
                infra.orders[2] = infra.order;
            }
        }
    }

    function _createFulfillments(AdapterWrapperInfra memory infra)
        internal
        pure
    {
        if (infra.flashloans.length > 0) {
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

            // Create the fulfillments.
            infra.fulfillments = new Fulfillment[](0);
        }
    }

    function _createTokenTransferCalls(ItemTransfer[] memory itemTransfers)
        internal
        pure
        returns (Call[] memory calls)
    {
        Call memory call;
        calls = new Call[](itemTransfers.length);

        for (uint256 i; i < itemTransfers.length; ++i) {
            if (itemTransfers[i].itemType == ItemType.ERC20) {
                call = Call(
                    address(itemTransfers[i].token),
                    false,
                    0,
                    abi.encodeWithSelector(
                        ERC20.transferFrom.selector,
                        itemTransfers[i].from,
                        itemTransfers[i].to,
                        itemTransfers[i].amount
                    )
                );

                calls[i] = call;
            } else if (itemTransfers[i].itemType == ItemType.ERC721) {
                call = Call(
                    address(itemTransfers[i].token),
                    false,
                    0,
                    abi.encodeWithSelector(
                        ERC721.transferFrom.selector,
                        itemTransfers[i].from,
                        itemTransfers[i].to,
                        itemTransfers[i].identifier
                    )
                );

                calls[i] = call;
            } else if (itemTransfers[i].itemType == ItemType.ERC1155) {
                call = Call(
                    address(itemTransfers[i].token),
                    false,
                    0,
                    abi.encodeWithSelector(
                        ERC1155.safeTransferFrom.selector,
                        itemTransfers[i].from,
                        itemTransfers[i].to,
                        itemTransfers[i].identifier,
                        itemTransfers[i].amount,
                        bytes("")
                    )
                );

                calls[i] = call;
            }
        }
    }

    function _getFlashloanArrayFromParams(
        uint256 value,
        ItemType itemType,
        bool shouldCallback,
        address recipient
    ) internal pure returns (Flashloan[] memory flashloans) {
        flashloans = new Flashloan[](1);
        flashloans[0] = Flashloan({
            amount: uint88(value),
            itemType: itemType,
            shouldCallback: shouldCallback,
            recipient: recipient
        });
    }
}
