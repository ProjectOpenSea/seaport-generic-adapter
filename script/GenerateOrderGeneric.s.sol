// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "forge-std/Script.sol";

import { Vm } from "forge-std/Vm.sol";

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
        console.log("Running some script");

        OrderPayload[] memory payloads = new OrderPayload[](5);

        // TODO: look up whether Foundation does fees or not.
        payloads[0] = getPayloadToBuyOfferedERC721WithEther_ListOnChain(
            foundationConfig, // BaseMarketConfig config,
            liveCastOfCharactersFoundation, // CastOfCharacters memory
            Item721({ token: address(0), identifier: 0 }), // Item721 memory
            0 // uint256 price
        );

        payloads[1] = getPayloadToBuyOfferedERC1155WithERC20(
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

        payloads[2] = getPayloadToBuyManyOfferedERC721WithEther_ListOnChain(
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

        payloads[3] = getPayloadToBuyManyOfferedERC721WithWETHDistinctOrders(
            x2y2Config, // BaseMarketConfig config,
            liveCastOfCharactersX2Y2, // CastOfCharacters memory
            desiredItemsX2Y2, // Item721[] memory desiredItems,
            paymentX2Y2 // Item20[] memory payments
        );

        payloads[4] = getPayloadToBuyOfferedERC721WithWETH(
            zeroExConfig, // BaseMarketConfig config,
            liveCastOfCharactersZeroEx, // CastOfCharacters memory
            Item721({ token: address(0), identifier: 0 }), // Item721 memory
            Item20({ token: wethAddress, amount: 0 }) // Item20 memory payment
        );

        // // TODO: think about how to rework the external payload lib to either
        // give me back transfers
        // // TODO: either move everything to OfferItem/ConsiderationItem or at
        // least make a converter function.

        // (AdvancedOrder[] memory adapterOrders, Fulfillment[] memory
        // adapterFulfillments) = AdapterHelperLib
        //     .createAdapterOrdersAndFulfillments(
        //     infra.executionPayloads,
        //     new Call[](0),
        //     new Call[](0),
        //     baseCastOfCharacters,
        //     new Flashloan[](0),
        //     infra.adapterOfferArray,
        //     infra.adapterConsiderationArray,
        //     infra.itemTransfers
        // );
    }
}
