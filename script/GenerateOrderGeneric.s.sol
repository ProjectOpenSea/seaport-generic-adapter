// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "forge-std/Script.sol";

import { Vm } from "forge-std/Vm.sol";

import { ConsiderationInterface } from
    "seaport-types/interfaces/ConsiderationInterface.sol";

import { ConsiderationItemLib } from "seaport-sol/lib/ConsiderationItemLib.sol";

import { OrderParametersLib } from "seaport-sol/lib/OrderParametersLib.sol";

import { ItemType, OrderType } from "seaport-types/lib/ConsiderationEnums.sol";

import {
    AdvancedOrder,
    BasicOrderParameters,
    ConsiderationItem,
    CriteriaResolver,
    Fulfillment,
    FulfillmentComponent,
    OfferItem,
    Order,
    OrderParameters
} from "seaport-types/lib/ConsiderationStructs.sol";

import {
    AdapterHelperLib,
    Approval,
    Call,
    Call,
    CastOfCharacters,
    Flashloan,
    Item20,
    Item721,
    Item1155,
    ItemTransfer,
    OrderContext
} from "../src/lib/AdapterHelperLib.sol";

import { ConsiderationInterface as ISeaport } from
    "seaport-types/interfaces/ConsiderationInterface.sol";

import { BaseMarketConfig } from "../src/marketplaces/BaseMarketConfig.sol";

import { BlurConfig } from "../src/marketplaces/blur/BlurConfig.sol";

import { FoundationConfig } from
    "../src/marketplaces/foundation/FoundationConfig.sol";

import { LooksRareConfig } from
    "../src/marketplaces/looksRare/LooksRareConfig.sol";

import { LooksRareV2Config } from
    "../src/marketplaces/looksRare-v2/LooksRareV2Config.sol";

import { SeaportOnePointFiveConfig } from
    "../src/marketplaces/seaport-1.5/SeaportOnePointFiveConfig.sol";

import { SudoswapConfig } from "../src/marketplaces/sudoswap/SudoswapConfig.sol";

import { X2Y2Config } from "../src/marketplaces/X2Y2/X2Y2Config.sol";

import { ZeroExConfig } from "../src/marketplaces/zeroEx/ZeroExConfig.sol";

import { FlashloanOffererInterface } from
    "../src/interfaces/FlashloanOffererInterface.sol";

import { GenericAdapterInterface } from
    "../src/interfaces/GenericAdapterInterface.sol";

import { GenericAdapterSidecarInterface } from
    "../src/interfaces/GenericAdapterSidecarInterface.sol";

import { OrderPayload } from "../src/utils/Types.sol";

import { ExternalOrderPayloadHelper } from
    "../src/lib/ExternalOrderPayloadHelper.sol";

import "forge-std/console.sol";

address constant VM_ADDRESS =
    address(uint160(uint256(keccak256("hevm cheat code"))));
Vm constant vm = Vm(VM_ADDRESS);

contract GenerateOrderGeneric is Script, ExternalOrderPayloadHelper {
    using ConsiderationItemLib for ConsiderationItem;
    using ConsiderationItemLib for ConsiderationItem[];
    using OrderParametersLib for OrderParameters;
    using OrderParametersLib for OrderParameters[];
    using AdapterHelperLib for Call;
    using AdapterHelperLib for Call[];
    using AdapterHelperLib for ConsiderationItem[];
    using AdapterHelperLib for ItemTransfer[];
    using AdapterHelperLib for OfferItem[];

    address internal constant seaportAddress =
        address(0x00000000000000ADc04C56Bf30aC9d3c0aAF14dC);

    // BaseMarketConfig blurConfig;
    // BaseMarketConfig blurV2Config;
    // BaseMarketConfig foundationConfig;
    // BaseMarketConfig looksRareConfig;
    // BaseMarketConfig looksRareV2Config;
    // BaseMarketConfig seaportOnePointFiveConfig;
    // BaseMarketConfig sudoswapConfig;
    // BaseMarketConfig x2y2Config;
    // BaseMarketConfig zeroExConfig;

    // FlashloanOffererInterface flashloanOfferer;
    // GenericAdapterInterface adapter;
    // GenericAdapterSidecarInterface sidecar;

    address flashloanOffererAddress;
    address adapterAddress;
    address sidecarAddress;

    CastOfCharacters baseCastOfCharacters;
    CastOfCharacters liveCastOfCharactersFoundation;
    CastOfCharacters liveCastOfCharactersLooksRareV2;
    CastOfCharacters liveCastOfCharactersSeaport;
    CastOfCharacters liveCastOfCharactersSudo;
    CastOfCharacters liveCastOfCharactersX2Y2;
    CastOfCharacters liveCastOfCharactersZeroEx;

    address myAddress;

    constructor() {
        foundationConfig = BaseMarketConfig(new FoundationConfig());
        looksRareV2Config = BaseMarketConfig(new LooksRareV2Config());
        seaportOnePointFiveConfig =
            BaseMarketConfig(new SeaportOnePointFiveConfig());
        sudoswapConfig = BaseMarketConfig(new SudoswapConfig());
        x2y2Config = BaseMarketConfig(new X2Y2Config());
        zeroExConfig = BaseMarketConfig(new ZeroExConfig());
    }

    function setUp() public virtual {
        console.log("Doing setup");

        flashloanOffererAddress =
            address(0x00A7DB0000BD990097e5229ea162cE0047a6006B);
        adapterAddress = address(0x00000000F2E7Fb5F440025F49BbD67133D2A6097);
        sidecarAddress = address(0xb908b211395eA2d0F678778bef915619073C78fd);

        myAddress = address(0);

        baseCastOfCharacters = CastOfCharacters({
            offerer: address(0), // Some offerer from real life for each below.
            fulfiller: myAddress,
            seaport: seaportAddress,
            flashloanOfferer: flashloanOffererAddress,
            adapter: adapterAddress,
            sidecar: sidecarAddress
        });

        liveCastOfCharactersFoundation = baseCastOfCharacters;
        liveCastOfCharactersFoundation.offerer = address(0);

        liveCastOfCharactersLooksRareV2 = baseCastOfCharacters;
        liveCastOfCharactersLooksRareV2.offerer = address(0);

        liveCastOfCharactersSeaport = baseCastOfCharacters;
        liveCastOfCharactersSeaport.offerer = address(0);

        liveCastOfCharactersSudo = baseCastOfCharacters;
        liveCastOfCharactersSudo.offerer = address(0);

        liveCastOfCharactersX2Y2 = baseCastOfCharacters;
        liveCastOfCharactersX2Y2.offerer = address(0);

        liveCastOfCharactersZeroEx = baseCastOfCharacters;
        liveCastOfCharactersZeroEx.offerer = address(0);
    }

    function run() public virtual {
        console.log("Running the aggregation script.");
        console.log("========================================================");

        // Set up the external calls.
        OrderPayload[] memory payloads = new OrderPayload[](5);
        Call[] memory executionCalls = new Call[](5);

        OfferItem[][] memory offerItemsArray = new OfferItem[][](5);
        ConsiderationItem[][] memory considerationItemsArray =
            new ConsiderationItem[][](5);
        ItemTransfer[][] memory itemTransfersArray = new ItemTransfer[][](5);

        OfferItem[] memory allItemsToBeOfferedByAdapter = new OfferItem[](0);
        ConsiderationItem[] memory allItemsToBeProvidedToAdapter =
            new ConsiderationItem[](0);
        ItemTransfer[] memory allSidecarItemTransfers = new ItemTransfer[](0);

        // TODO: look up whether Foundation does fees or not.
        (
            payloads[0],
            offerItemsArray[0],
            considerationItemsArray[0],
            itemTransfersArray[0]
        ) = getPayloadToBuyOfferedERC721WithEther_ListOnChain(
            foundationConfig, // BaseMarketConfig config,
            liveCastOfCharactersFoundation, // CastOfCharacters memory
            Item721({ token: address(0), identifier: 0 }), // Item721 memory
            0 // uint256 price
        );

        (
            payloads[1],
            offerItemsArray[1],
            considerationItemsArray[1],
            itemTransfersArray[1]
        ) = getPayloadToBuyOfferedERC1155WithERC20(
            looksRareV2Config, // BaseMarketConfig config,
            liveCastOfCharactersLooksRareV2, // CastOfCharacters memory
            Item1155({ token: address(0), identifier: 0, amount: 1 }), // Item1155
                // memory
            Item20({ token: address(0), amount: 0 }) // Item20 memory payment
        );

        Item721[] memory desiredItemsSudo = new Item721[](3);
        desiredItemsSudo[0] = Item721({ token: address(0), identifier: 0 });
        desiredItemsSudo[1] = Item721({ token: address(0), identifier: 0 });
        desiredItemsSudo[2] = Item721({ token: address(0), identifier: 0 });

        (
            payloads[2],
            offerItemsArray[2],
            considerationItemsArray[2],
            itemTransfersArray[2]
        ) = getPayloadToBuyManyOfferedERC721WithEther_ListOnChain(
            sudoswapConfig, // BaseMarketConfig config,
            liveCastOfCharactersSudo, // CastOfCharacters memory
            desiredItemsSudo, // Item721 memory desiredItems,
            0 // uint256 price
        );

        Item721[] memory desiredItemsX2Y2 = new Item721[](3);
        desiredItemsX2Y2[0] = Item721({ token: address(0), identifier: 0 });
        desiredItemsX2Y2[1] = Item721({ token: address(0), identifier: 0 });
        desiredItemsX2Y2[2] = Item721({ token: address(0), identifier: 0 });

        Item20[] memory paymentX2Y2 = new Item20[](3);
        paymentX2Y2[0] = Item20({ token: wethAddress, amount: 0 });
        paymentX2Y2[1] = Item20({ token: wethAddress, amount: 0 });
        paymentX2Y2[2] = Item20({ token: wethAddress, amount: 0 });

        (
            payloads[3],
            offerItemsArray[3],
            considerationItemsArray[3],
            itemTransfersArray[3]
        ) = getPayloadToBuyManyOfferedERC721WithWETHDistinctOrders(
            x2y2Config, // BaseMarketConfig config,
            liveCastOfCharactersX2Y2, // CastOfCharacters memory
            desiredItemsX2Y2, // Item721[] memory desiredItems,
            paymentX2Y2 // Item20[] memory payments
        );

        (
            payloads[4],
            offerItemsArray[4],
            considerationItemsArray[4],
            itemTransfersArray[4]
        ) = getPayloadToBuyOfferedERC721WithWETH(
            zeroExConfig, // BaseMarketConfig config,
            liveCastOfCharactersZeroEx, // CastOfCharacters memory
            Item721({ token: address(0), identifier: 0 }), // Item721 memory
            Item20({ token: wethAddress, amount: 0 }) // Item20 memory payment
        );

        for (uint256 i; i < payloads.length; ++i) {
            executionCalls[i] = payloads[i].executeOrder;
        }

        for (uint256 i; i < offerItemsArray.length; ++i) {
            allItemsToBeOfferedByAdapter = allItemsToBeOfferedByAdapter
                ._extendOfferItems(offerItemsArray[i]);
        }

        for (uint256 i; i < considerationItemsArray.length; ++i) {
            allItemsToBeProvidedToAdapter = allItemsToBeProvidedToAdapter
                ._extendConsiderationItems(considerationItemsArray[i]);
        }

        for (uint256 i; i < itemTransfersArray.length; ++i) {
            allSidecarItemTransfers = allSidecarItemTransfers
                ._extendItemTransfers(itemTransfersArray[i]);
        }

        for (uint256 i; i < executionCalls.length; ++i) {
            console.log("Execution call", i);
        }

        for (uint256 i; i < allItemsToBeOfferedByAdapter.length; ++i) {
            console.log("Offer item", i);
        }

        for (uint256 i; i < allItemsToBeProvidedToAdapter.length; ++i) {
            console.log("Consideration item", i);
        }

        for (uint256 i; i < allSidecarItemTransfers.length; ++i) {
            console.log("Item transfer", i);
        }

        (
            AdvancedOrder[] memory adapterOrders,
            Fulfillment[] memory adapterFulfillments
        ) = AdapterHelperLib.createAdapterOrdersAndFulfillments(
            executionCalls, // The calls to external marketplaces.
            new Call[](0), // Sidecar setup calls, unused
            new Call[](0), // Sidecar wrap up calls, unused
            baseCastOfCharacters, // Cast of characters, offerer is unused
            new Flashloan[](0), // Flashloans, will be generated automatically
            allItemsToBeOfferedByAdapter, // Things the call will get the caller
            allItemsToBeProvidedToAdapter, // Things that will go out
            allSidecarItemTransfers // Item shuffling by the sidecar
        );

        for (uint256 i; i < adapterOrders.length; ++i) {
            console.log("Adapter order", i);
        }

        for (uint256 i; i < adapterFulfillments.length; ++i) {
            console.log("Adapter fulfillment", i);
        }

        // Set up the seaport orders.
        Order[] memory nativeSeaportOrders = new Order[](4);
        Fulfillment[] memory nativeSeaportFullfillments = new Fulfillment[](4);
        uint256 sumAmountsForNativeSeaportOrders;

        {
            Item721[] memory desiredItemsSeaport = new Item721[](3);
            desiredItemsSeaport[0] =
                Item721({ token: address(0), identifier: 0 }); // TODO: populate
            desiredItemsSeaport[1] =
                Item721({ token: address(0), identifier: 0 }); // TODO: populate
            desiredItemsSeaport[2] =
                Item721({ token: address(0), identifier: 0 }); // TODO: populate

            CastOfCharacters[] memory castOfCharactersArraySeaport =
                new CastOfCharacters[](3);
            OrderContext[] memory orderContexts = new OrderContext[](3);
            uint256[] memory prices = new uint256[](3);

            for (uint256 i; i < orderContexts.length; ++i) {
                orderContexts[i] = OrderContext({
                    listOnChain: false,
                    routeThroughAdapter: false,
                    castOfCharacters: liveCastOfCharactersSeaport
                });

                castOfCharactersArraySeaport[i] = liveCastOfCharactersSeaport;
                castOfCharactersArraySeaport[i].offerer = address(0); // TODO:
                    // populate

                prices[i] = 0; // TODO: populate
            }

            (
                nativeSeaportOrders,
                nativeSeaportFullfillments,
                sumAmountsForNativeSeaportOrders
            ) = seaportOnePointFiveConfig
                .buildOrderAndFulfillmentManyDistinctOrders(
                orderContexts,
                address(0), // TODO: populate with shitcoins or leave if ETH
                desiredItemsSeaport,
                prices,
                true // skip the attempt to sign the order to avoid revert
            );
        }

        AdvancedOrder[] memory nativeSeaportAdvancedOrders =
            new AdvancedOrder[](4);

        for (uint256 i; i < nativeSeaportOrders.length; ++i) {
            nativeSeaportAdvancedOrders[i] = AdvancedOrder({
                parameters: nativeSeaportOrders[i].parameters,
                numerator: 1,
                denominator: 1,
                signature: "", // ad hoc
                extraData: "" // none required on the native orders
             });
        }

        // 3 adapter orders (adapter order, flashloan, mirror)
        // 3 seaport offer orders (from the API or whatever)
        // 1 seaport taker order (from this script)
        AdvancedOrder[] memory finalOrders = new AdvancedOrder[](7);
        // 2 adapter fulfillments (flashloan, mirror)
        // 4 native seaport fulfillments (one for each NFT plus the taker order)
        Fulfillment[] memory finalFulfillments = new Fulfillment[](6);

        {
            finalOrders[0] = adapterOrders[0];
            finalOrders[1] = adapterOrders[1];
            finalOrders[2] = adapterOrders[2];
            finalOrders[3] = nativeSeaportAdvancedOrders[0];
            finalOrders[4] = nativeSeaportAdvancedOrders[1];
            finalOrders[5] = nativeSeaportAdvancedOrders[2];
            finalOrders[6] = nativeSeaportAdvancedOrders[3];
        }

        {
            finalFulfillments[0] = adapterFulfillments[0];
            finalFulfillments[1] = adapterFulfillments[1];
            finalFulfillments[2] = nativeSeaportFullfillments[0];
            finalFulfillments[3] = nativeSeaportFullfillments[1];
            finalFulfillments[4] = nativeSeaportFullfillments[2];
            finalFulfillments[5] = nativeSeaportFullfillments[3];
        }

        (bool success, bytes memory returnData) = seaportAddress.call{ value: 0 }(
            abi.encodeWithSelector(
                ConsiderationInterface.matchAdvancedOrders.selector,
                finalOrders,
                new CriteriaResolver[](0),
                finalFulfillments,
                address(0)
            )
        );

        if (!success) {
            console.log('returnData');
            console.logBytes(returnData);
            revert("Seaport matchAdvancedOrders failed");
        } else {
            console.log("Seaport matchAdvancedOrders succeeded");
            console.log('returnData');
            console.logBytes(returnData);
        }
    }
}
