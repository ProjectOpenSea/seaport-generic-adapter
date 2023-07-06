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
    TestCallParameters,
    TestItem20,
    TestItem721,
    TestItem1155
} from "../../test/utils/Types.sol";

import "forge-std/console.sol";

// TODO: Think about maybe just putting a SpentItem in here.
struct Flashloan {
    uint88 amount;
    ItemType itemType;
    bool shouldCallback;
    address recipient;
}

struct Approval {
    address token;
    ItemType itemType;
}

struct CastOfCharacters {
    address offerer;
    address fulfiller;
    address seaport;
    address flashloanOfferer;
    address adapter;
    address sidecar;
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
        CastOfCharacters memory castOfCharacters,
        Flashloan[] memory flashloans,
        ConsiderationItem[] memory considerationArray,
        TestItem721 memory nft
    ) public view returns (TestCallParameters memory) {
        TestItem721[] memory erc721s = new TestItem721[](1);
        erc721s[0] = nft;

        return createSeaportWrappedTestCallParameters(
            testCallParameters,
            castOfCharacters,
            flashloans,
            considerationArray,
            erc721s,
            new TestItem1155[](0)
        );
    }

    function createSeaportWrappedTestCallParameters(
        TestCallParameters memory testCallParameters,
        CastOfCharacters memory castOfCharacters,
        Flashloan[] memory flashloans,
        ConsiderationItem[] memory considerationArray,
        TestItem721[] memory nfts
    ) public view returns (TestCallParameters memory) {
        return createSeaportWrappedTestCallParameters(
            testCallParameters,
            castOfCharacters,
            flashloans,
            considerationArray,
            nfts,
            new TestItem1155[](0)
        );
    }

    function createSeaportWrappedTestCallParameters(
        TestCallParameters memory testCallParameters,
        CastOfCharacters memory castOfCharacters,
        Flashloan[] memory flashloans,
        ConsiderationItem[] memory considerationArray,
        TestItem1155 memory nft
    ) public view returns (TestCallParameters memory) {
        TestItem1155[] memory erc1155s = new TestItem1155[](1);
        erc1155s[0] = nft;

        return createSeaportWrappedTestCallParameters(
            testCallParameters,
            castOfCharacters,
            flashloans,
            considerationArray,
            new TestItem721[](0),
            erc1155s
        );
    }

    function createSeaportWrappedTestCallParameters(
        TestCallParameters memory testCallParameters,
        CastOfCharacters memory castOfCharacters,
        Flashloan[] memory flashloans,
        ConsiderationItem[] memory considerationArray,
        TestItem1155[] memory nfts
    ) public view returns (TestCallParameters memory) {
        TestItem721[] memory erc721s = new TestItem721[](0);

        return createSeaportWrappedTestCallParameters(
            testCallParameters,
            castOfCharacters,
            flashloans,
            considerationArray,
            erc721s,
            nfts
        );
    }

    function createSeaportWrappedTestCallParameters(
        TestCallParameters memory testCallParameters,
        CastOfCharacters memory castOfCharacters,
        Flashloan[] memory flashloans,
        ConsiderationItem[] memory considerationArray,
        TestItem721[] memory erc721s,
        TestItem1155[] memory erc1155s
    )
        public
        view
        returns (TestCallParameters memory wrappedTestCallParameter)
    {
        TestCallParameters[] memory testCallParametersArray =
            new TestCallParameters[](1);
        testCallParametersArray[0] = testCallParameters;

        return createSeaportWrappedTestCallParameters(
            testCallParametersArray,
            castOfCharacters,
            flashloans,
            considerationArray,
            new TestItem20[](0),
            erc721s,
            erc1155s
        );
    }

    function createSeaportWrappedTestCallParameters(
        TestCallParameters[] memory testCallParametersArray,
        CastOfCharacters memory castOfCharacters,
        Flashloan[] memory flashloans,
        ConsiderationItem[] memory considerationArray,
        TestItem721[] memory erc721s,
        TestItem1155[] memory erc1155s
    )
        public
        view
        returns (TestCallParameters memory wrappedTestCallParameter)
    {
        return createSeaportWrappedTestCallParameters(
            testCallParametersArray,
            castOfCharacters,
            flashloans,
            considerationArray,
            new TestItem20[](0),
            erc721s,
            erc1155s
        );
    }

    function createSeaportWrappedTestCallParameters(
        TestCallParameters memory testCallParameters,
        CastOfCharacters memory castOfCharacters,
        Flashloan[] memory flashloans,
        ConsiderationItem[] memory considerationArray,
        TestItem20[] memory erc20s
    )
        public
        view
        returns (TestCallParameters memory wrappedTestCallParameter)
    {
        TestCallParameters[] memory testCallParametersArray =
            new TestCallParameters[](1);
        testCallParametersArray[0] = testCallParameters;

        return createSeaportWrappedTestCallParameters(
            testCallParametersArray,
            castOfCharacters,
            flashloans,
            considerationArray,
            erc20s,
            new TestItem721[](0),
            new TestItem1155[](0)
        );
    }

    function createSeaportWrappedTestCallParameters(
        TestCallParameters memory testCallParameters,
        CastOfCharacters memory castOfCharacters,
        Flashloan[] memory flashloans,
        ConsiderationItem[] memory considerationArray,
        TestItem20[] memory erc20s,
        TestItem721[] memory nfts
    )
        public
        view
        returns (TestCallParameters memory wrappedTestCallParameter)
    {
        TestCallParameters[] memory testCallParametersArray =
            new TestCallParameters[](1);
        testCallParametersArray[0] = testCallParameters;

        return createSeaportWrappedTestCallParameters(
            testCallParametersArray,
            castOfCharacters,
            flashloans,
            considerationArray,
            erc20s,
            nfts,
            new TestItem1155[](0)
        );
    }

    function createSeaportWrappedTestCallParameters(
        TestCallParameters[] memory testCallParametersArray,
        CastOfCharacters memory castOfCharacters,
        Flashloan[] memory flashloans,
        ConsiderationItem[] memory considerationArray,
        TestItem20[] memory erc20s,
        TestItem721[] memory erc721s,
        TestItem1155[] memory erc1155s
    )
        public
        view
        returns (TestCallParameters memory wrappedTestCallParameter)
    {
        AdvancedOrder[] memory orders;
        Fulfillment[] memory fulfillments;
        (orders, fulfillments) =
        createSeaportWrappedTestCallParametersReturnGranular(
            testCallParametersArray,
            castOfCharacters,
            flashloans,
            considerationArray,
            erc20s,
            erc721s,
            erc1155s
        );

        wrappedTestCallParameter.data = abi.encodeWithSelector(
            ConsiderationInterface.matchAdvancedOrders.selector,
            orders,
            new CriteriaResolver[](0),
            fulfillments,
            address(0)
        );

        uint256 value;

        for (uint256 i; i < testCallParametersArray.length; ++i) {
            value += testCallParametersArray[i].value;
        }

        wrappedTestCallParameter.value = value;
        wrappedTestCallParameter.target = castOfCharacters.seaport;
    }

    struct AdapterWrapperInfra {
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
        uint256 value;
        uint256 totalFlashloanValueRequested;
    }

    function createSeaportWrappedTestCallParametersReturnGranular(
        TestCallParameters[] memory testCallParametersArray,
        CastOfCharacters memory castOfCharacters,
        Flashloan[] memory flashloans,
        ConsiderationItem[] memory considerationArray,
        TestItem20[] memory erc20s,
        TestItem721[] memory erc721s,
        TestItem1155[] memory erc1155s
    )
        public
        view
        returns (
            AdvancedOrder[] memory orders,
            Fulfillment[] memory fulfillments
        )
    {
        AdapterWrapperInfra memory infra = AdapterWrapperInfra(
            considerationArray.length == 0
                ? new ConsiderationItem[](1)
                : considerationArray,
            OrderParametersLib.empty(),
            AdvancedOrderLib.empty(),
            new AdvancedOrder[](3),
            Flashloan(0, ItemType.NATIVE, false, address(0)),
            flashloans,
            Call(address(0), false, 0, bytes("")),
            new Call[](1),
            new bytes(0),
            new Fulfillment[](3),
            0,
            0
        );

        for (uint256 i; i < testCallParametersArray.length; ++i) {
            infra.value += testCallParametersArray[i].value;
        }

        {
            // Create the adapter order.
            infra.order =
                AdvancedOrderLib.empty().withNumerator(1).withDenominator(1);

            // Default to this consideration array.
            if (
                keccak256(abi.encode(infra.considerationArray[0]))
                    == keccak256(abi.encode(ConsiderationItemLib.empty()))
            ) {
                infra.considerationArray[0] = ConsiderationItemLib.empty()
                    .withItemType(ItemType.NATIVE).withToken(address(0))
                    .withIdentifierOrCriteria(0).withStartAmount(infra.value)
                    .withEndAmount(infra.value).withRecipient(address(0));
            }

            {
                infra.orderParameters = OrderParametersLib.empty().withOrderType(
                    OrderType.FULL_OPEN
                ).withStartTime(block.timestamp).withEndTime(
                    block.timestamp + 100
                ).withTotalOriginalConsiderationItems(0).withOfferer(
                    castOfCharacters.adapter
                );
                infra.orderParameters =
                    infra.orderParameters.withSalt(gasleft());
                infra.orderParameters =
                    infra.orderParameters.withOrderType(OrderType.CONTRACT);
                infra.orderParameters = infra.orderParameters.withOffer(
                    new OfferItem[](0)
                ).withConsideration(infra.considerationArray)
                    .withTotalOriginalConsiderationItems(
                    infra.considerationArray.length
                );

                infra.order = infra.order.withParameters(infra.orderParameters);
            }

            infra.calls =
            new Call[](testCallParametersArray.length + erc20s.length + erc721s.length + erc1155s.length);

            {
                for (uint256 i = 0; i < testCallParametersArray.length; i++) {
                    infra.calls[i] = Call(
                        address(testCallParametersArray[i].target),
                        false,
                        testCallParametersArray[i].value,
                        testCallParametersArray[i].data
                    );
                }

                Call[] memory tokenCalls = _createTokenTransferCalls(
                    address(castOfCharacters.sidecar),
                    address(castOfCharacters.fulfiller),
                    erc20s,
                    erc721s,
                    erc1155s
                );

                // Populate the calls array with the NFT transfer calls from the
                // helper.
                for (uint256 i = 0; i < tokenCalls.length; i++) {
                    infra.calls[testCallParametersArray.length + i] =
                        tokenCalls[i];
                }
            }

            {
                infra.extraData =
                    createGenericAdapterContext(new Approval[](0), infra.calls);
            }

            infra.order = infra.order.withExtraData(infra.extraData);
            infra.orders[1] = infra.order;
        }

        if (flashloans.length > 0) {
            {
                infra.order =
                    AdvancedOrderLib.empty().withNumerator(1).withDenominator(1);
            }

            {
                for (uint256 i = 0; i < flashloans.length; i++) {
                    infra.totalFlashloanValueRequested +=
                        infra.flashloans[i].amount;
                }

                infra.considerationArray = new ConsiderationItem[](1);

                // Come back and think about the case where multiple flashloans
                // of different types are required.
                infra.considerationArray[0] = ConsiderationItemLib.empty()
                    .withItemType(infra.flashloans[0].itemType).withToken(
                    address(0)
                ).withIdentifierOrCriteria(0).withStartAmount(
                    infra.totalFlashloanValueRequested
                ).withEndAmount(infra.totalFlashloanValueRequested)
                    .withRecipient(address(0));
            }

            {
                infra.orderParameters = OrderParametersLib.empty();
                infra.orderParameters =
                    infra.orderParameters.withSalt(gasleft());
                infra.orderParameters = infra.orderParameters.withOfferer(
                    address(castOfCharacters.fulfiller)
                );
                infra.orderParameters = infra.orderParameters.withOrderType(
                    OrderType.FULL_OPEN
                ).withStartTime(block.timestamp);
                infra.orderParameters =
                    infra.orderParameters.withEndTime(block.timestamp + 100);
                infra.orderParameters =
                    infra.orderParameters.withTotalOriginalConsiderationItems(0);
                infra.orderParameters = infra.orderParameters.withOfferer(
                    castOfCharacters.flashloanOfferer
                );
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
                infra.extraData = createFlashloanContext(
                    address(castOfCharacters.fulfiller), flashloans
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
                        address(castOfCharacters.fulfiller)
                    );
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

            // Create the fulfillments.
            infra.fulfillments = new Fulfillment[](0);
        }

        return (infra.orders, infra.fulfillments);
    }

    function _createTokenTransferCalls(
        address from,
        address to,
        TestItem20[] memory test20s,
        TestItem721[] memory test721s,
        TestItem1155[] memory test1155s
    ) public pure returns (Call[] memory calls) {
        Call memory call;
        calls = new Call[](test20s.length + test721s.length + test1155s.length);

        for (uint256 i; i < test20s.length; ++i) {
            call = Call(
                address(test20s[i].token),
                false,
                0,
                abi.encodeWithSelector(
                    ERC20.transferFrom.selector,
                    address(from),
                    address(to),
                    test20s[i].amount
                )
            );

            calls[i] = call;
        }

        for (uint256 i; i < test721s.length; ++i) {
            call = Call(
                address(test721s[i].token),
                false,
                0,
                abi.encodeWithSelector(
                    ERC721.transferFrom.selector,
                    address(from),
                    address(to),
                    test721s[i].identifier
                )
            );

            calls[i + test20s.length] = call;
        }

        for (uint256 i; i < test1155s.length; ++i) {
            call = Call(
                address(test1155s[i].token),
                false,
                0,
                abi.encodeWithSelector(
                    ERC1155.safeTransferFrom.selector,
                    address(from),
                    address(to),
                    test1155s[i].identifier,
                    test1155s[i].amount,
                    bytes("")
                )
            );

            calls[i + test20s.length + test721s.length] = call;
        }
    }
}
