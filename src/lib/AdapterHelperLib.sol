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

import "forge-std/console.sol";

struct Item721 {
    address token;
    uint256 identifier;
}

struct Item1155 {
    address token;
    uint256 identifier;
    uint256 amount;
}

struct Item20 {
    address token;
    uint256 amount;
}

/**
 * @dev A Flashloan is a struct that specifies the amount, type, and recipient
 *      of a flashloan, and whether or not the cleanup function should be
 *      called.  The amount is the amount of native tokens requested. The amount
 *      requested has to be less than or equal to the amount offered in the
 *      consideration. The type is the type of consideration that will be
 *      provided. shouldCallback is a boolean that specifies whether the cleanup
 *      function on the adapter should be called. The recipient is the address
 *      that will receive the flashloan, e.g. the address of the adapter.
 */
struct Flashloan {
    uint88 amount;
    ItemType itemType;
    address token;
    bool shouldCallback;
    address recipient;
}

/**
 * @dev A Fulfillment is a struct that specifies the address and item type of
 *      a token that needs to be approved.
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
 */
struct CastOfCharacters {
    address offerer;
    address fulfiller;
    address seaport;
    address flashloanOfferer;
    address adapter;
    address sidecar;
}

/**
 * @dev An ItemTransfer is a struct that specifies the details of a transfer of
 *      an item by the sidecar.
 */
struct ItemTransfer {
    address from;
    address to;
    address token;
    uint256 identifier;
    uint256 amount;
    ItemType itemType;
}

struct OrderContext {
    bool listOnChain;
    bool routeThroughAdapter;
    CastOfCharacters castOfCharacters;
}

// // Maybe
// struct OrderContext {
//     Call[] sidecarMarketplaceCalls;
//     Flashloan[] flashloans;
//     Approval[] approvals;
//     CastOfCharacters[] castOfCharactersArray;
//     ItemTransfer[] itemTransfers;
// }

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
            amount = flashloans[i].amount;
            shouldCallback = flashloans[i].shouldCallback ? 1 : 0;
            recipient = uint256(uint160(flashloans[i].recipient));

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
    //                      A few different interfaces.                       //
    //                  The meat is at the bottom of all these.               //
    ////////////////////////////////////////////////////////////////////////////

    function createSeaportWrappedCallParameters(
        Call memory sidecarMarketplaceCall,
        CastOfCharacters memory castOfCharacters,
        OfferItem[] memory adapterOffer,
        ConsiderationItem[] memory adapterConsideration,
        ItemTransfer[] memory itemTransfers
    ) public returns (Call memory) {
        Call[] memory sidecarMarketplaceCalls = new Call[](1);
        sidecarMarketplaceCalls[0] = sidecarMarketplaceCall;

        return createSeaportWrappedCallParameters(
            sidecarMarketplaceCalls,
            new Call[](0),
            new Call[](0),
            castOfCharacters,
            new Flashloan[](0),
            adapterOffer,
            adapterConsideration,
            itemTransfers
        );
    }

    function createSeaportWrappedCallParameters(
        Call memory sidecarMarketplaceCall,
        CastOfCharacters memory castOfCharacters,
        Flashloan[] memory flashloans,
        OfferItem[] memory adapterOffer,
        ConsiderationItem[] memory adapterConsideration,
        ItemTransfer[] memory itemTransfers
    ) public returns (Call memory) {
        Call[] memory sidecarMarketplaceCalls = new Call[](1);
        sidecarMarketplaceCalls[0] = sidecarMarketplaceCall;

        return createSeaportWrappedCallParameters(
            sidecarMarketplaceCalls,
            new Call[](0),
            new Call[](0),
            castOfCharacters,
            flashloans,
            adapterOffer,
            adapterConsideration,
            itemTransfers
        );
    }

    function createSeaportWrappedCallParameters(
        Call[] memory sidecarMarketplaceCalls,
        Call[] memory sidecarSetUpCalls,
        Call[] memory sidecarWrapUpCalls,
        CastOfCharacters memory castOfCharacters,
        Flashloan[] memory flashloans,
        OfferItem[] memory adapterOffer,
        ConsiderationItem[] memory adapterConsideration,
        ItemTransfer[] memory itemTransfers
    ) public returns (Call memory wrappedCallParameters) {
        AdvancedOrder[] memory orders;
        Fulfillment[] memory fulfillments;
        (orders, fulfillments) = createAdapterOrdersAndFulfillments(
            sidecarMarketplaceCalls,
            sidecarSetUpCalls,
            sidecarWrapUpCalls,
            castOfCharacters,
            flashloans,
            adapterOffer,
            adapterConsideration,
            itemTransfers
        );

        wrappedCallParameters.callData = abi.encodeWithSelector(
            ConsiderationInterface.matchAdvancedOrders.selector,
            orders,
            new CriteriaResolver[](0),
            fulfillments,
            address(0)
        );

        uint256 value;

        for (uint256 i; i < sidecarMarketplaceCalls.length; ++i) {
            value += sidecarMarketplaceCalls[i].value;
        }

        wrappedCallParameters.value = value;
        wrappedCallParameters.target = castOfCharacters.seaport;
    }

    /**
     * @dev This function is used to create a set of orders and fulfillments
     *      that can be passed into matchAdvancedOrders to fulfill an arbitrary
     *      number of orders on external marketplaces. It expects that the calls
     *      to external marketplaces are pre-rolled into the
     *      sidecarMarketplaceCall array. This function will wrap up those calls
     *      into an order that hits the generic adapter, which passes them along
     *      to the sidecar. It also creates a single pair of orders for an
     *      arbitrary number of flashloans, if any are passed in. It returns the
     *      orders and fulfillments separately.
     *
     * @param sidecarSetUpCalls       An array of Call structs that contain
     *                                the calls to be made by the sidecar before
     *                                the calls to external marketplaces.
     * @param sidecarMarketplaceCalls An array of Call structs
     *                                that contain the target, value, and
     *                                calldata for the calls to external
     *                                marketplaces.
     * @param sidecarWrapUpCalls      An array of Call structs that contain
     *                                the calls to be made by the sidecar after
     *                                the calls to external marketplaces.
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
    function createAdapterOrdersAndFulfillments(
        Call[] memory sidecarMarketplaceCalls,
        Call[] memory sidecarSetUpCalls,
        Call[] memory sidecarWrapUpCalls,
        CastOfCharacters memory castOfCharacters,
        Flashloan[] memory flashloans,
        OfferItem[] memory adapterOffer,
        ConsiderationItem[] memory adapterConsideration,
        ItemTransfer[] memory itemTransfers
    )
        public
        returns (
            AdvancedOrder[] memory orders,
            Fulfillment[] memory fulfillments
        )
    {
        uint256 value;

        // Set the value to send.
        for (uint256 i; i < sidecarMarketplaceCalls.length; ++i) {
            value += sidecarMarketplaceCalls[i].value;
        }

        // Only create a default flashloan if it's necessary and none is passed
        // in explicitly.
        if (value > 0 && flashloans.length == 0) {
            flashloans = new Flashloan[](1);
            Flashloan memory flashloan = Flashloan({
                amount: uint88(value),
                itemType: ItemType.NATIVE, // TODO: make this flexible (weth)
                token: address(0),
                shouldCallback: true,
                recipient: castOfCharacters.adapter
            });
            flashloans[0] = flashloan;
        }

        // For now, assume it's just one adapter order.
        uint256 flashloanOrderCount = flashloans.length * 2;
        uint256 totalOrderCount = flashloanOrderCount + 1;

        orders = new AdvancedOrder[](totalOrderCount);

        if (flashloans.length > 0) {
            AdvancedOrder[] memory flashloanOrders =
                new AdvancedOrder[](flashloanOrderCount);
            flashloanOrders =
                _createFlashloanOrders(flashloans, castOfCharacters);

            for (uint256 i; i < flashloanOrders.length; i++) {
                orders[i] = flashloanOrders[i];
            }
        }

        orders[orders.length - 1] = _createAdapterOrder(
            sidecarMarketplaceCalls,
            sidecarSetUpCalls,
            sidecarWrapUpCalls,
            castOfCharacters,
            adapterOffer,
            adapterConsideration,
            itemTransfers
        );

        fulfillments = _createFulfillments(flashloans);

        return (orders, fulfillments);
    }

    // Public wrapper for _createAdapterOrder.
    function createAdapterOrder(
        Call[] memory sidecarMarketplaceCalls,
        Call[] memory sidecarSetUpCalls,
        Call[] memory sidecarWrapUpCalls,
        CastOfCharacters memory castOfCharacters,
        OfferItem[] memory adapterOffer,
        ConsiderationItem[] memory adapterConsideration,
        ItemTransfer[] memory itemTransfers
    ) public returns (AdvancedOrder memory order) {
        return _createAdapterOrder(
            sidecarMarketplaceCalls,
            sidecarSetUpCalls,
            sidecarWrapUpCalls,
            castOfCharacters,
            adapterOffer,
            adapterConsideration,
            itemTransfers
        );
    }

    function _createAdapterOrder(
        Call[] memory sidecarMarketplaceCalls,
        Call[] memory sidecarSetUpCalls,
        Call[] memory sidecarWrapUpCalls,
        CastOfCharacters memory castOfCharacters,
        OfferItem[] memory adapterOffer,
        ConsiderationItem[] memory adapterConsideration,
        ItemTransfer[] memory itemTransfers
    ) internal returns (AdvancedOrder memory adapterOrder) {
        // Create the adapter order.
        adapterOrder =
            AdvancedOrderLib.empty().withNumerator(1).withDenominator(1);

        {
            OrderParameters memory orderParameters = OrderParametersLib.empty()
                .withOrderType(OrderType.FULL_OPEN).withStartTime(block.timestamp)
                .withEndTime(block.timestamp + 100)
                .withTotalOriginalConsiderationItems(0).withOfferer(
                castOfCharacters.adapter
            );
            orderParameters = orderParameters.withSalt(gasleft());
            orderParameters = orderParameters.withOrderType(OrderType.CONTRACT);
            orderParameters = orderParameters.withOffer(adapterOffer)
                .withConsideration(adapterConsideration)
                .withTotalOriginalConsiderationItems(adapterConsideration.length);

            adapterOrder = adapterOrder.withParameters(orderParameters);
        }

        Call[] memory calls =
        new Call[](sidecarSetUpCalls.length + sidecarMarketplaceCalls.length + itemTransfers.length + sidecarWrapUpCalls.length);

        {
            for (uint256 i; i < sidecarSetUpCalls.length; i++) {
                calls[i] = sidecarSetUpCalls[i];
            }

            for (uint256 i = 0; i < sidecarMarketplaceCalls.length; i++) {
                calls[sidecarSetUpCalls.length + i] = Call(
                    address(sidecarMarketplaceCalls[i].target),
                    false,
                    sidecarMarketplaceCalls[i].value,
                    sidecarMarketplaceCalls[i].callData
                );
            }

            Call[] memory tokenCalls = _createTokenTransferCalls(itemTransfers);

            // Populate the calls array with the NFT transfer calls from the
            // helper.
            for (uint256 i = 0; i < tokenCalls.length; i++) {
                calls[sidecarSetUpCalls.length + sidecarMarketplaceCalls.length
                    + i] = tokenCalls[i];
            }

            for (uint256 i = 0; i < sidecarWrapUpCalls.length; i++) {
                calls[sidecarSetUpCalls.length + sidecarMarketplaceCalls.length
                    + tokenCalls.length + i] = sidecarWrapUpCalls[i];
            }
        }

        adapterOrder = adapterOrder.withExtraData(
            createGenericAdapterContext(
                _generateNecessaryApprovals(castOfCharacters, adapterOffer),
                calls
            )
        );

        return adapterOrder;
    }

    function _generateNecessaryApprovals(
        CastOfCharacters memory castOfCharacters,
        OfferItem[] memory adapterOffer
    ) internal returns (Approval[] memory approvals) {
        Approval[] memory tempApprovals = new Approval[](0);

        // Automatically add approvals if they're needed.
        for (uint256 i; i < adapterOffer.length; ++i) {
            address token = adapterOffer[i].token;

            if (adapterOffer[i].itemType == ItemType.ERC20) {
                (bool success, bytes memory approvedBalanceBytes) = token.call(
                    abi.encodeWithSelector(
                        ERC20.allowance.selector,
                        castOfCharacters.adapter,
                        castOfCharacters.seaport
                    )
                );

                if (success == false) {
                    revert("ERC20 approval status check failed.");
                }

                uint256 approvedBalance = uint256(bytes32(approvedBalanceBytes));

                if (!(approvedBalance == type(uint256).max)) {
                    // Create a temporary Approval array with extra space for
                    // the new approval.
                    tempApprovals = new Approval[](approvals.length + 1);
                    // Populate the temporary array with the existing approvals.
                    for (uint256 j; j < approvals.length; ++j) {
                        tempApprovals[j] = approvals[j];
                    }
                    // Add the new approval to the temporary array.
                    tempApprovals[approvals.length] =
                        Approval({ token: token, itemType: ItemType.ERC20 });
                    // Set the approvals array to the temporary array.
                    approvals = tempApprovals;
                }
            } else if (
                adapterOffer[i].itemType == ItemType.ERC721
                    || adapterOffer[i].itemType == ItemType.ERC1155
            ) {
                (bool success, bytes memory returnData) = token.call(
                    abi.encodeWithSelector(
                        ERC721.isApprovedForAll.selector,
                        castOfCharacters.adapter,
                        castOfCharacters.seaport
                    )
                );

                if (success == false) {
                    revert("NFT approval status check failed.");
                }

                bool tokenAlreadyApproved = uint256(bytes32(returnData)) == 1;

                if (!tokenAlreadyApproved) {
                    // Create a temporary Approval array with extra space for
                    // the new approval.
                    tempApprovals = new Approval[](approvals.length + 1);
                    // Populate the temporary array with the existing approvals.
                    for (uint256 j; j < approvals.length; ++j) {
                        tempApprovals[j] = approvals[j];
                    }
                    // Add the new approval to the temporary array.
                    tempApprovals[approvals.length] = Approval({
                        token: token,
                        itemType: adapterOffer[i].itemType
                    });
                    // Set the approvals array to the temporary array.
                    approvals = tempApprovals;
                }
            } else {
                revert("Invalid item type");
            }
        }
    }

    function _createFlashloanOrders(
        Flashloan[] memory flashloans,
        CastOfCharacters memory castOfCharacters
    ) internal view returns (AdvancedOrder[] memory orders) {
        orders = new AdvancedOrder[](flashloans.length * 2);

        for (uint256 i = 0; i < flashloans.length; i++) {
            {
                // Build the flashloan request order.
                ConsiderationItem[] memory flashloanRequestConsiderationTemp =
                    new ConsiderationItem[](1);

                flashloanRequestConsiderationTemp[0] = ConsiderationItemLib
                    .empty().withItemType(flashloans[i].itemType).withToken(
                    flashloans[i].token
                ).withIdentifierOrCriteria(0).withStartAmount(
                    flashloans[i].amount
                ).withEndAmount(flashloans[i].amount).withRecipient(address(0));

                OrderParameters memory orderParametersTemp =
                    OrderParametersLib.empty();

                orderParametersTemp = orderParametersTemp.withSalt(gasleft());
                orderParametersTemp = orderParametersTemp.withOfferer(
                    address(castOfCharacters.fulfiller)
                );
                orderParametersTemp = orderParametersTemp.withOrderType(
                    OrderType.FULL_OPEN
                ).withStartTime(block.timestamp);
                orderParametersTemp =
                    orderParametersTemp.withEndTime(block.timestamp + 100);
                orderParametersTemp = orderParametersTemp.withOfferer(
                    castOfCharacters.flashloanOfferer
                );
                orderParametersTemp =
                    orderParametersTemp.withOrderType(OrderType.CONTRACT);
                orderParametersTemp =
                    orderParametersTemp.withOffer(new OfferItem[](0));
                orderParametersTemp = orderParametersTemp.withConsideration(
                    flashloanRequestConsiderationTemp
                );
                orderParametersTemp =
                    orderParametersTemp.withTotalOriginalConsiderationItems(1);

                AdvancedOrder memory orderTemp;
                orderTemp = orderTemp.withParameters(orderParametersTemp)
                    .withNumerator(1).withDenominator(1);

                Flashloan[] memory tempFlashloans = new Flashloan[](1);
                tempFlashloans[0] = flashloans[i];

                bytes memory extraDataTemp = createFlashloanContext(
                    address(castOfCharacters.fulfiller), tempFlashloans
                );

                // Add it all to the order.
                orderTemp = orderTemp.withExtraData(extraDataTemp);
                orders[i * 2] = orderTemp;
            }

            {
                // Build the mirror order.

                // Create the parameters for the order.
                OfferItem[] memory offerItems = new OfferItem[](1);
                offerItems[0] = OfferItemLib.empty().withItemType(
                    flashloans[i].itemType
                ).withToken(flashloans[i].token).withIdentifierOrCriteria(0)
                    .withStartAmount(flashloans[i].amount).withEndAmount(
                    flashloans[i].amount
                );

                OrderParameters memory orderParametersTemp =
                    OrderParametersLib.empty();

                orderParametersTemp = OrderParametersLib.empty();
                orderParametersTemp = orderParametersTemp.withSalt(gasleft());
                orderParametersTemp = orderParametersTemp.withOfferer(
                    address(castOfCharacters.fulfiller)
                );
                orderParametersTemp =
                    orderParametersTemp.withOrderType(OrderType.FULL_OPEN);
                orderParametersTemp =
                    orderParametersTemp.withStartTime(block.timestamp);
                orderParametersTemp =
                    orderParametersTemp.withEndTime(block.timestamp + 100);
                orderParametersTemp = orderParametersTemp.withConsideration(
                    new ConsiderationItem[](0)
                );
                orderParametersTemp =
                    orderParametersTemp.withTotalOriginalConsiderationItems(0);
                orderParametersTemp = orderParametersTemp.withOffer(offerItems);

                AdvancedOrder memory orderTemp;
                orderTemp = orderTemp.withNumerator(1).withDenominator(1);
                orderTemp = orderTemp.withParameters(orderParametersTemp);
                orders[(i * 2) + 1] = orderTemp;
            }
        }
    }

    function _createFulfillments(Flashloan[] memory flashloans)
        internal
        pure
        returns (Fulfillment[] memory fulfillments)
    {
        if (flashloans.length > 0) {
            // Create the fulfillments.
            uint256 fulfillmentsLength = flashloans.length * 2;
            fulfillments = new Fulfillment[](fulfillmentsLength);

            for (uint256 i; i < flashloans.length; i++) {
                FulfillmentComponent[] memory offerComponentsFlashloan =
                    new FulfillmentComponent[](1);
                FulfillmentComponent[] memory considerationComponentsFlashloan =
                    new FulfillmentComponent[](1);
                FulfillmentComponent[] memory offerComponentsMirror =
                    new FulfillmentComponent[](1);
                FulfillmentComponent[] memory considerationComponentsMirror =
                    new FulfillmentComponent[](1);

                uint256 flashloanOrderIndex = i * 2;
                uint256 mirrorOrderIndex = (i * 2) + 1;

                offerComponentsFlashloan[0] =
                    FulfillmentComponent(flashloanOrderIndex, 0);
                considerationComponentsFlashloan[0] =
                    FulfillmentComponent(mirrorOrderIndex, 0);
                offerComponentsMirror[0] =
                    FulfillmentComponent(mirrorOrderIndex, 0);
                considerationComponentsMirror[0] =
                    FulfillmentComponent(flashloanOrderIndex, 0);

                fulfillments[flashloanOrderIndex] = Fulfillment(
                    offerComponentsFlashloan, considerationComponentsFlashloan
                );
                fulfillments[mirrorOrderIndex] = Fulfillment(
                    offerComponentsMirror, considerationComponentsMirror
                );
            }
        } else {
            fulfillments = new Fulfillment[](0);
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
                        ERC20.transfer.selector,
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

    function _extendOfferItems(
        OfferItem[] memory currentItems,
        OfferItem[] memory newItems
    ) internal pure returns (OfferItem[] memory) {
        OfferItem[] memory result =
            new OfferItem[](currentItems.length + newItems.length);

        for (uint256 i = 0; i < currentItems.length; i++) {
            result[i] = currentItems[i];
        }

        for (uint256 i = 0; i < newItems.length; i++) {
            result[i + currentItems.length] = newItems[i];
        }

        return result;
    }

    function _extendConsiderationItems(
        ConsiderationItem[] memory currentItems,
        ConsiderationItem[] memory newItems
    ) internal pure returns (ConsiderationItem[] memory) {
        ConsiderationItem[] memory result =
            new ConsiderationItem[](currentItems.length + newItems.length);

        for (uint256 i = 0; i < currentItems.length; i++) {
            result[i] = currentItems[i];
        }

        for (uint256 i = 0; i < newItems.length; i++) {
            result[i + currentItems.length] = newItems[i];
        }

        return result;
    }

    function _extendItemTransfers(
        ItemTransfer[] memory currentItemTransfers,
        ItemTransfer[] memory newItemTransfers
    ) internal pure returns (ItemTransfer[] memory) {
        ItemTransfer[] memory result =
        new ItemTransfer[](currentItemTransfers.length + newItemTransfers.length);

        for (uint256 i = 0; i < currentItemTransfers.length; i++) {
            result[i] = currentItemTransfers[i];
        }

        for (uint256 i = 0; i < newItemTransfers.length; i++) {
            result[i + currentItemTransfers.length] = newItemTransfers[i];
        }

        return result;
    }
}
