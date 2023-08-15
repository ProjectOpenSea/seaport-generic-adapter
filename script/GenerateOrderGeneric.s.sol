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

import { FoundationConfig } from
    "../src/marketplaces/foundation/FoundationConfig.sol";

// TODO: Come back and see if it's feasible to untangle the mess of nonces.
// import { LooksRareV2Config } from
//     "../src/marketplaces/looksRare-v2/LooksRareV2Config.sol";

import { SeaportOnePointFiveConfig } from
    "../src/marketplaces/seaport-1.5/SeaportOnePointFiveConfig.sol";

import { SudoswapConfig } from "../src/marketplaces/sudoswap/SudoswapConfig.sol";

import { UniswapConfig } from "../src/marketplaces/uniswap/UniswapConfig.sol";

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

    address flashloanOffererAddress;
    address adapterAddress;
    address sidecarAddress;

    CastOfCharacters baseCastOfCharacters;
    CastOfCharacters liveCastOfCharactersUniswap;
    CastOfCharacters liveCastOfCharactersFoundation;
    CastOfCharacters liveCastOfCharactersSeaport;
    CastOfCharacters liveCastOfCharactersSudo;
    CastOfCharacters liveCastOfCharactersZeroEx;

    address myAddress;
    uint256 privateKey;

    constructor() {
        foundationConfig = BaseMarketConfig(new FoundationConfig());
        seaportOnePointFiveConfig =
            BaseMarketConfig(new SeaportOnePointFiveConfig());
        sudoswapConfig = BaseMarketConfig(new SudoswapConfig());
        uniswapConfig = BaseMarketConfig(new UniswapConfig());
        zeroExConfig = BaseMarketConfig(new ZeroExConfig());
    }

    function setUp() public virtual {
        flashloanOffererAddress =
            address(0x00A7DB0000BD990097e5229ea162cE0047a6006B);
        adapterAddress = address(0x00000000F2E7Fb5F440025F49BbD67133D2A6097);
        sidecarAddress = address(0xb908b211395eA2d0F678778bef915619073C78fd);

        myAddress = vm.envAddress("MY_ADDRESS");

        baseCastOfCharacters = CastOfCharacters({
            offerer: address(0), // Some offerer from real life for each below.
            fulfiller: myAddress,
            seaport: seaportAddress,
            flashloanOfferer: flashloanOffererAddress,
            adapter: adapterAddress,
            sidecar: sidecarAddress
        });

        liveCastOfCharactersFoundation = baseCastOfCharacters;
        liveCastOfCharactersSeaport = baseCastOfCharacters;
        liveCastOfCharactersSudo = baseCastOfCharacters;
        liveCastOfCharactersZeroEx = baseCastOfCharacters;

        privateKey = vm.envUint("PRIVATE_KEY");
    }

    function run() public virtual {
        console.log("Running the aggregation script.");
        console.log("========================================================");

        // NOTE: None of these external calls require a taker side signature,
        // but eventually I'll want to have an arg to pass in a pk to generate
        // it on the fly.

        // NOTE: None of these external calls require a maker side signature,
        // but eventually I'll want to have an arg to pass in an existing
        // signature so that the config functions can wedge it in.

        // // TODO: put this somewhere sensible.
        // address usdcAddress = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

        // Set up the external calls.
        OrderPayload[] memory payloads = new OrderPayload[](4);
        Call[] memory executionCalls = new Call[](4);

        OfferItem[][] memory offerItemsArray = new OfferItem[][](4);
        ConsiderationItem[][] memory considerationItemsArray =
            new ConsiderationItem[][](4);
        ItemTransfer[][] memory itemTransfersArray = new ItemTransfer[][](4);

        OfferItem[] memory allItemsToBeOfferedByAdapter = new OfferItem[](0);
        ConsiderationItem[] memory allItemsToBeProvidedToAdapter =
            new ConsiderationItem[](0);
        ItemTransfer[] memory allSidecarItemTransfers = new ItemTransfer[](0);

        // TODO: Think about the fact that I want this call to fund the sidecar
        // and then not do anything else. Maybe this is an ABC case with the
        // native seaport order.

        (payloads[0],,,) = getDataToBuyOfferedERC20WithEther_ListOnChain(
            uniswapConfig, // BaseMarketConfig config,
            liveCastOfCharactersUniswap, // CastOfCharacters memory
            Item20({
                token: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
                amount: 200000000 // 200 USDC
             }), // Item20 memory (exact out in uniswap terms)
            0.1 ether // uint256 price (maximum in, in uniswap terms)
        );

        (
            ,
            offerItemsArray[0],
            considerationItemsArray[0],
            itemTransfersArray[0]
        ) = getDataToBuyOfferedERC20WithEther_ListOnChain_FulfillThroughAdapter(
            uniswapConfig, // BaseMarketConfig config,
            liveCastOfCharactersUniswap, // CastOfCharacters memory
            Item20({
                token: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
                amount: 200000000 // 200 USDC
             }), // Item20 memory (exact out in uniswap terms)
            0.1 ether // uint256 price (maximum in, in uniswap terms)
        );

        // https://foundation.app/@plasm0/ai-0975/3
        // Offerer does not need to be set

        (payloads[1],,,) = getDataToBuyOfferedERC721WithEther_ListOnChain(
            foundationConfig, // BaseMarketConfig config,
            liveCastOfCharactersFoundation, // CastOfCharacters memory
            Item721({
                token: address(0xA266ACAA1F44c2c744556C0fFa499E2d39E48557),
                identifier: 3
            }), // Item721 memory
            0.01005 ether // uint256 price // NOTE: this 0.00005 might be
                // unnecessary
        );

        (
            ,
            offerItemsArray[1],
            considerationItemsArray[1],
            itemTransfersArray[1]
        ) = getDataToBuyOfferedERC721WithEther_ListOnChain_FulfillThroughAdapter(
            foundationConfig, // BaseMarketConfig config,
            liveCastOfCharactersFoundation, // CastOfCharacters memory
            Item721({
                token: address(0xA266ACAA1F44c2c744556C0fFa499E2d39E48557),
                identifier: 3
            }), // Item721 memory
            0.01005 ether // uint256 price // NOTE: this 0.00005 might be
                // unnecessary
        );

        // https://sudoswap.xyz/#/browse/buy/0xcd76d0cf64bf4a58d898905c5adad5e1e838e0d3
        // Offerer does not need to be set

        Item721[] memory desiredItemsSudo = new Item721[](3);
        desiredItemsSudo[0] = Item721({
            token: address(0xCd76D0Cf64Bf4A58D898905C5adAD5e1E838E0d3),
            identifier: 2298
        });
        desiredItemsSudo[1] = Item721({
            token: address(0xCd76D0Cf64Bf4A58D898905C5adAD5e1E838E0d3),
            identifier: 2519
        });
        desiredItemsSudo[2] = Item721({
            token: address(0xCd76D0Cf64Bf4A58D898905C5adAD5e1E838E0d3),
            identifier: 3807
        });

        (payloads[2],,,) = getDataToBuyManyOfferedERC721WithEther_ListOnChain(
            sudoswapConfig, // BaseMarketConfig config,
            liveCastOfCharactersSudo, // CastOfCharacters memory
            desiredItemsSudo, // Item721 memory desiredItems,
            0.0506 ether // uint256 price
        );

        (
            ,
            offerItemsArray[2],
            considerationItemsArray[2],
            itemTransfersArray[2]
        ) =
        getDataToBuyManyOfferedERC721WithEther_ListOnChain_FulfillThroughAdapter(
            sudoswapConfig, // BaseMarketConfig config,
            liveCastOfCharactersSudo, // CastOfCharacters memory
            desiredItemsSudo, // Item721 memory desiredItems,
            0.0506 ether // uint256 price
        );

        // https://nft.coinbase.com/nft/ethereum/0x76be3b62873462d2142405439777e971754e8e77/10789
        liveCastOfCharactersZeroEx.offerer =
            address(0x58afcEC9F52951BaeF490eF6E4A9a09Bfdd53bB7);

        (payloads[3],,,) = getDataToBuyOfferedERC1155WithEther_ListOnChain(
            zeroExConfig, // BaseMarketConfig config,
            liveCastOfCharactersZeroEx, // CastOfCharacters memory
            Item1155({
                token: address(0x76BE3b62873462d2142405439777e971754E8E77),
                identifier: 10789,
                amount: 1
            }), // Item1155 memory
            0.009 ether // uint256 price
        );

        (
            ,
            offerItemsArray[3],
            considerationItemsArray[3],
            itemTransfersArray[3]
        ) =
        getDataToBuyOfferedERC1155WithEther_ListOnChain_FulfillThroughAdapter(
            zeroExConfig, // BaseMarketConfig config,
            liveCastOfCharactersZeroEx, // CastOfCharacters memory
            Item1155({
                token: address(0x76BE3b62873462d2142405439777e971754E8E77),
                identifier: 10789,
                amount: 1
            }), // Item1155 memory
            0.009 ether // uint256 price
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

        console.log("Execution call length, should be 4");
        console.log(executionCalls.length);

        console.log("Offer item length, should be 6");
        console.log(allItemsToBeOfferedByAdapter.length);

        console.log("Consideration item length, should be 4");
        console.log(allItemsToBeProvidedToAdapter.length);

        console.log("Item transfer length, should be ?");
        console.log(allSidecarItemTransfers.length);

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
                privateKey
            );
        }

        AdvancedOrder[] memory nativeSeaportAdvancedOrders =
            new AdvancedOrder[](6);

        {
            for (uint256 i; i < nativeSeaportOrders.length; ++i) {
                nativeSeaportAdvancedOrders[i] = AdvancedOrder({
                    parameters: nativeSeaportOrders[i].parameters,
                    numerator: 1,
                    denominator: 1,
                    signature: "", // fill in 3 listings with real signatures
                    extraData: "" // none required on the native orders
                 });
            }
        }

        {
            AdvancedOrder memory orderOffer1155;
            AdvancedOrder memory orderConsider1155;

            {
                address offerer = address(0); // TODO
                Item20 memory price = Item20({
                    token: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
                    amount: 200000000
                }); // USDC
                Item1155 memory desiredItem = Item1155(address(0), 0, 1);
                bytes memory actualSignature = bytes("a"); // TODO

                BasicOrderParameters memory params = seaportOnePointFiveConfig
                    .getComponents_BuyOfferedERC20WithERC1155(
                    offerer, price, desiredItem, 0, actualSignature
                );

                orderOffer1155 = _createSeaportOrderFromBasicParams(params);

                // The PK is not really required, ad hoc would work.
                params = seaportOnePointFiveConfig
                    .getComponents_BuyOfferedERC1155WithERC20(
                    myAddress, desiredItem, price, privateKey, ""
                );

                orderConsider1155 = _createSeaportOrderFromBasicParams(params);
            }
            nativeSeaportAdvancedOrders[nativeSeaportAdvancedOrders.length - 2]
            = orderOffer1155;
            nativeSeaportAdvancedOrders[nativeSeaportAdvancedOrders.length - 1]
            = orderConsider1155;
        }

        // 3 adapter orders (adapter order, flashloan, mirror)
        // 3 seaport offer orders (from the API or whatever)
        // 1 seaport taker order (from this script)
        // 1 seaport 1155<>20 order (from the API or whatever)
        // 1 seaport 20<>1155 order (from this script)
        AdvancedOrder[] memory finalOrders = new AdvancedOrder[](9);
        // 2 adapter fulfillments (flashloan, mirror)
        // 6 native seaport fulfillments (one for each 721, plus the taker
        // order, plus one for each side of the 1155<>20)
        Fulfillment[] memory finalFulfillments = new Fulfillment[](8);

        {
            finalOrders[0] = adapterOrders[0]; // Flashloan
            finalOrders[1] = adapterOrders[1]; // Mirror
            finalOrders[2] = adapterOrders[2]; // Adapter
            finalOrders[3] = nativeSeaportAdvancedOrders[0];
            finalOrders[4] = nativeSeaportAdvancedOrders[1];
            finalOrders[5] = nativeSeaportAdvancedOrders[2]; // 3 721<>ETH
            finalOrders[6] = nativeSeaportAdvancedOrders[3]; // 1 ETH<>721
            finalOrders[7] = nativeSeaportAdvancedOrders[4]; // 1155<>ERC20
            finalOrders[8] = nativeSeaportAdvancedOrders[5]; // ERC20<>1155
        }

        {
            Fulfillment memory order1155FulfillmentOne;
            Fulfillment memory order1155FulfillmentTwo;
            {
                FulfillmentComponent[] memory offerComponentsOne =
                    new FulfillmentComponent[](1);
                FulfillmentComponent[] memory considerationComponentsOne =
                    new FulfillmentComponent[](1);

                FulfillmentComponent[] memory offerComponentsTwo =
                    new FulfillmentComponent[](1);
                FulfillmentComponent[] memory considerationComponentsTwo =
                    new FulfillmentComponent[](1);

                {
                    offerComponentsOne[0] =
                        FulfillmentComponent({ orderIndex: 7, itemIndex: 0 });
                    considerationComponentsOne[0] =
                        FulfillmentComponent({ orderIndex: 8, itemIndex: 0 });

                    offerComponentsTwo[0] =
                        FulfillmentComponent({ orderIndex: 8, itemIndex: 0 });
                    considerationComponentsTwo[0] =
                        FulfillmentComponent({ orderIndex: 7, itemIndex: 0 });
                }

                order1155FulfillmentOne = Fulfillment({
                    offerComponents: offerComponentsOne,
                    considerationComponents: considerationComponentsOne
                });
                order1155FulfillmentTwo = Fulfillment({
                    offerComponents: offerComponentsTwo,
                    considerationComponents: considerationComponentsTwo
                });
            }

            finalFulfillments[0] = adapterFulfillments[0];
            finalFulfillments[1] = adapterFulfillments[1];
            finalFulfillments[2] = nativeSeaportFullfillments[0];
            finalFulfillments[3] = nativeSeaportFullfillments[1];
            finalFulfillments[4] = nativeSeaportFullfillments[2];
            finalFulfillments[5] = nativeSeaportFullfillments[3];
            finalFulfillments[6] = order1155FulfillmentOne;
            finalFulfillments[7] = order1155FulfillmentTwo;
        }

        // TODO: uncomment when close to th finish line.
        // (bool success, bytes memory returnData) = seaportAddress.call{ value:
        // 0 }(
        //     abi.encodeWithSelector(
        //         ConsiderationInterface.matchAdvancedOrders.selector,
        //         finalOrders,
        //         new CriteriaResolver[](0),
        //         finalFulfillments,
        //         address(0)
        //     )
        // );

        // if (!success) {
        //     console.log("returnData");
        //     console.logBytes(returnData);
        //     revert("Seaport matchAdvancedOrders failed");
        // } else {
        //     console.log("Seaport matchAdvancedOrders succeeded");
        //     console.log("returnData");
        //     console.logBytes(returnData);
        // }
    }

    // TODO: refactor.
    function _createSeaportOrderFromBasicParams(
        BasicOrderParameters memory basicParams
    ) internal view returns (AdvancedOrder memory) {
        OrderParameters memory params = OrderParameters({
            offerer: basicParams.offerer,
            zone: basicParams.zone,
            offer: new OfferItem[](1),
            consideration: new ConsiderationItem[](1),
            orderType: OrderType.FULL_OPEN,
            startTime: basicParams.startTime,
            endTime: basicParams.endTime,
            zoneHash: basicParams.zoneHash,
            salt: basicParams.salt + gasleft(),
            conduitKey: basicParams.offererConduitKey,
            totalOriginalConsiderationItems: 1
        });

        uint256 basicOrderType = uint256(basicParams.basicOrderType);

        OfferItem memory offerItem;
        offerItem.itemType = basicOrderType > 15
            ? ItemType.ERC20
            : basicOrderType > 11
                ? ItemType.ERC1155
                : basicOrderType > 7
                    ? ItemType.ERC721
                    : basicOrderType > 3 ? ItemType.ERC1155 : ItemType.ERC721;
        offerItem.token = basicParams.offerToken;
        offerItem.identifierOrCriteria = basicParams.offerIdentifier;
        offerItem.startAmount = basicParams.offerAmount;
        offerItem.endAmount = basicParams.offerAmount;

        params.offer[0] = offerItem;

        ConsiderationItem memory considerationItem;

        considerationItem.itemType = basicOrderType < 8
            ? ItemType.NATIVE
            : basicOrderType < 16
                ? ItemType.ERC20
                : basicOrderType < 20 ? ItemType.ERC721 : ItemType.ERC1155;
        considerationItem.token = basicParams.considerationToken;
        considerationItem.identifierOrCriteria =
            basicParams.considerationIdentifier;
        considerationItem.startAmount = basicParams.considerationAmount;
        considerationItem.endAmount = basicParams.considerationAmount;
        considerationItem.recipient = basicParams.offerer;

        params.consideration[0] = considerationItem;

        AdvancedOrder memory advancedOrder = AdvancedOrder({
            parameters: params,
            numerator: 1,
            denominator: 1,
            signature: "",
            extraData: new bytes(0)
        });

        return advancedOrder;
    }
}
