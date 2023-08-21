// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "forge-std/Script.sol";

import { Vm } from "forge-std/Vm.sol";

import { IERC20 } from "forge-std/interfaces/IERC20.sol";

import { IERC721 } from "forge-std/interfaces/IERC721.sol";

import { IERC1155 } from "forge-std/interfaces/IERC1155.sol";

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
    Fee,
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

import { IZeroEx } from "../src/marketplaces/zeroEx/interfaces/IZeroEx.sol";

import "../src/marketplaces/zeroEx/lib/LibNFTOrder.sol";

import "../src/marketplaces/zeroEx/lib/LibSignature.sol";

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

import { StdCheats } from "forge-std/StdCheats.sol";

address constant VM_ADDRESS =
    address(uint160(uint256(keccak256("hevm cheat code"))));
Vm constant vm = Vm(VM_ADDRESS);

// TODO: write a parallel test for this.

contract GenerateOrderGeneric is Script, ExternalOrderPayloadHelper, StdCheats {
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

        // deployCodeTo(string memory what, bytes memory args, address where)
        vm.allowCheatcodes(flashloanOffererAddress);
        deployCodeTo(
            "out/FlashloanOfferer.sol/FlashloanOfferer.json",
            abi.encode(address(seaportAddress)),
            flashloanOffererAddress
        );

        vm.allowCheatcodes(adapterAddress);
        deployCodeTo(
            "out/GenericAdapter.sol/GenericAdapter.json",
            abi.encode(address(seaportAddress), address(flashloanOffererAddress)),
            adapterAddress
        );

        sidecarAddress = address(0xb02B8BaC470D3d181f38512656F9ccc100F7AA7f);

        myAddress = vm.envAddress("MY_ADDRESS");

        baseCastOfCharacters = CastOfCharacters({
            offerer: address(0), // Some offerer from real life for each below.
            fulfiller: myAddress,
            seaport: seaportAddress,
            flashloanOfferer: flashloanOffererAddress,
            adapter: adapterAddress,
            sidecar: sidecarAddress
        });

        liveCastOfCharactersUniswap = baseCastOfCharacters;
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
        // address primeTokenAddress =
        // 0xb23d80f5FefcDDaa212212F028021B41DEd428CF;

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

        // TODO: read the traces thoroughly and make sure they make sense.

        // TODO: Think about adding a 'tokenReceiver' field to cast of
        // characters.

        // Offerer does not need to be set for a uniswap call.

        // TODO: The PRIME is ending up in my address but it needs to go to the
        // adapter. EDIT: It would be safer for me to have the PRIME go to the
        // adapter, then the adapter can send it to me, but I'm out of time for
        // now, so it's just going to go straight to me and then from me to the
        // people selling parallel 1155s through native seaport orders. So, the
        // offerItemsArray should be temporarily empty bc I expect nothing to go
        // from the adapter to me via seaport at the end of the uniswap trade.
        // I'm just funding the purchase of 1155s.

        (payloads[0],,,) = getDataToBuyOfferedERC20WithEther_ListOnChain(
            uniswapConfig, // BaseMarketConfig config,
            liveCastOfCharactersUniswap, // CastOfCharacters memory
            Item20({
                token: 0xb23d80f5FefcDDaa212212F028021B41DEd428CF, // Prime
                amount: 60000000000000000000 // 60 Prime
             }), // Item20 memory (exact out in uniswap terms)
            0.15 ether // uint256 price (maximum in, in uniswap terms)
        );

        (
            ,
            , //offerItemsArray[0], // what I require from the adapter
            considerationItemsArray[0], // what I am willing to give the adapter
            itemTransfersArray[0]
        ) = getDataToBuyOfferedERC20WithEther_ListOnChain_FulfillThroughAdapter(
            uniswapConfig, // BaseMarketConfig config,
            liveCastOfCharactersUniswap, // CastOfCharacters memory
            Item20({
                token: 0xb23d80f5FefcDDaa212212F028021B41DEd428CF, // Prime
                amount: 60000000000000000000 // 60 Prime
             }), // Item20 memory (exact out in uniswap terms)
            0.15 ether // uint256 price (maximum in, in uniswap terms)
        );

        // TODO: think about how to obviate the need for the double call.

        // https://foundation.app/@plasm0/ai-0975/3
        // https://opensea.io/assets/ethereum/0xA266ACAA1F44c2c744556C0fFa499E2d39E48557/3
        // Offerer does not need to be set

        // Get the raw payload for a direct fulfillment (the payload that the
        // sidecar yeets out).
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

        // Get the rest of the data (the offer and consideration for the adapter
        // order, plus the sidecar item transfers).
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

        // TODO: figure out how to programmatically target an actual pool.
        (payloads[2],,,) = getDataToBuyManyOfferedERC721WithEther_ListOnChain(
            sudoswapConfig, // BaseMarketConfig config,
            liveCastOfCharactersSudo, // CastOfCharacters memory
            liveCastOfCharactersSudo.adapter,
            desiredItemsSudo, // Item721 memory desiredItems,
            0.06 ether // 0.04969829 ether // uint256 price
        );

        payloads[2].executeOrder.target =
            address(0xa251D9980851cB856E5D13273738CF3CAf0c240E);

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
            0.06 ether // 0.04969829 ether // uint256 price
        );

        // https://nft.coinbase.com/nft/ethereum/0x76be3b62873462d2142405439777e971754e8e77/10789
        liveCastOfCharactersZeroEx.offerer =
            address(0x58afcEC9F52951BaeF490eF6E4A9a09Bfdd53bB7);

        bytes memory actualZeroExSig = abi.encodePacked(
            bytes32(
                uint256(
                    0x713a6392015be875b5c501098756bc5275b2622bb97a4de590d811cfefd3642e
                )
            ), // r
            bytes32(
                uint256(
                    0x356af5b06cab3de80c9aade4aae26427697e97cd96881b28bb6ea495083e2fda
                )
            ), // s
            uint8(28) // v
        );

        // This is not an option.
        // (payloads[3],,,) = getDataToBuyOfferedERC1155WithEther(
        //     zeroExConfig, // BaseMarketConfig config,
        //     liveCastOfCharactersZeroEx, // CastOfCharacters memory
        //     Item1155({
        //         token: address(0x76BE3b62873462d2142405439777e971754E8E77),
        //         identifier: 10789,
        //         amount: 1
        //     }), // Item1155 memory
        //     0.009 ether, // uint256 price
        //     actualZeroExSig // actual signature
        // );

        // Roll the 0x order calldata by hand.
        {
            LibNFTOrder.Fee[] memory zeroExFee = new LibNFTOrder.Fee[](1);
            zeroExFee[0] = LibNFTOrder.Fee({
                recipient: address(0x157e23d3E68aC6f99334B8b0fE71F0eb844911Dd),
                amount: 900000000000000,
                feeData: ""
            });

            LibNFTOrder.ERC1155Order memory order = LibNFTOrder.ERC1155Order({
                direction: LibNFTOrder.TradeDirection.SELL_NFT, // 0
                maker: liveCastOfCharactersZeroEx.offerer, //
                taker: address(0),
                expiry: 1698661401,
                nonce: 338328920673545782875099168451228691357,
                erc20Token: address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE), // 0x
                    // orders are able to be
                    // "bought" with the native token using this sentinel value
                erc20TokenAmount: 8100000000000000,
                fees: zeroExFee,
                erc1155Token: address(0x76BE3b62873462d2142405439777e971754E8E77),
                erc1155TokenId: 10789,
                erc1155TokenAmount: uint128(1),
                erc1155TokenProperties: new LibNFTOrder.Property[](0)
            });

            LibSignature.Signature memory sig;

            {
                uint8 v;
                bytes32 r;
                bytes32 s;

                {
                    assembly {
                        r := mload(add(actualZeroExSig, 32))
                        s := mload(add(actualZeroExSig, 64))
                        v := and(mload(add(actualZeroExSig, 65)), 255)
                    }
                    if (v < 27) v += 27;
                }

                // Prepare the signature
                sig = LibSignature.Signature({
                    signatureType: LibSignature.SignatureType.EIP712,
                    v: v,
                    r: r,
                    s: s
                });
            }

            payloads[3].executeOrder = Call(
                address(0xDef1C0ded9bec7F1a1670819833240f027b25EfF),
                false,
                0.009 ether,
                abi.encodeWithSelector(
                    IZeroEx.buyERC1155.selector, order, sig, uint128(1), ""
                )
            );
        }

        (
            ,
            offerItemsArray[3],
            considerationItemsArray[3],
            itemTransfersArray[3]
        ) = getDataToBuyOfferedERC1155WithEther_FulfillThroughAdapter(
            zeroExConfig, // BaseMarketConfig config,
            liveCastOfCharactersZeroEx, // CastOfCharacters memory
            Item1155({
                token: address(0x76BE3b62873462d2142405439777e971754E8E77),
                identifier: 10789,
                amount: 1
            }), // Item1155 memory
            0.009 ether, // uint256 price
            actualZeroExSig // actual signature
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

        // console.log("Execution call length, should be 4");
        // console.log(executionCalls.length);

        // // Art from Foundation, 3 oranges from Sudo, and 1 Parallel NFT from
        // // Coinbase, plus the PRIME from uniswap.
        // console.log("Offer item length, should be 6");
        // console.log(allItemsToBeOfferedByAdapter.length);

        // // 4 different sized chunks of ETH, could collapse into one for gas
        // // efficiency.
        // console.log("Consideration item length, should be 4");
        // console.log(allItemsToBeProvidedToAdapter.length);

        // // Sudo allows direct transfers, so the sidecar doesn't need to move
        // // those 3 oranges
        // console.log("Item transfer length, should be 2");
        // console.log(allSidecarItemTransfers.length);

        // Call[] memory setupCalls = new Call[](1);
        // setupCalls[0] = Call({});

        // Might need to bake up the flashloan manually.

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

        // for (uint256 i; i < adapterOrders.length; ++i) {
        //     console.log("Adapter order", i);
        // }

        // for (uint256 i; i < adapterFulfillments.length; ++i) {
        //     console.log("Adapter fulfillment", i);
        // }

        // Set up the seaport orders.
        Order[] memory nativeSeaportOrders = new Order[](4);
        Fulfillment[] memory nativeSeaportFullfillments = new Fulfillment[](4);
        uint256 sumAmountsForNativeSeaportOrders;

        {
            Item721[] memory desiredItemsSeaport = new Item721[](3);
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
            }

            // https://opensea.io/assets/ethereum/0x5c2afed4c41b85c36ffb6cc2a235afa66c5a780d/1102
            desiredItemsSeaport[0] = Item721({
                token: address(0x5C2AFeD4c41B85C36FFB6cC2A235AfA66C5A780D),
                identifier: 1102
            });
            castOfCharactersArraySeaport[0].offerer =
                address(0xe4FC2f11f9F7fce3900c82260765f4d10D0EAE0c);
            prices[0] = 3600000000000000;

            // https://opensea.io/assets/ethereum/0x00000000000061ad8ee190710508a818ae5325c3/831
            desiredItemsSeaport[1] = Item721({
                token: address(0x00000000000061aD8EE190710508A818aE5325C3),
                identifier: 831
            });
            castOfCharactersArraySeaport[1].offerer =
                address(0xf05f3C5863B9d36a3D21D0Da51394A7b2432a8d5);
            prices[1] = 0.039 ether;

            // https://opensea.io/assets/ethereum/0xff6000a85baac9c4854faa7155e70ba850bf726b/5890012
            desiredItemsSeaport[2] = Item721({
                token: address(0xFf6000a85baAc9c4854fAA7155e70BA850BF726b),
                identifier: 5890012
            });
            castOfCharactersArraySeaport[2].offerer =
                address(0x83fba2bF935b086A83C8c630dbb61c79d286325a);
            prices[2] = 2998000000000000;

            for (uint256 i; i < orderContexts.length; ++i) {
                orderContexts[i] = OrderContext({
                    listOnChain: false,
                    routeThroughAdapter: false,
                    castOfCharacters: castOfCharactersArraySeaport[i]
                });
            }

            // TODO: Figure out whether this sig recovery is failing bc of an
            // order fidelity issue, a sig setup issue, an order type issue,
            // or some other issue.

            // TODO: figure out how to do this properly.
            bytes[] memory signatures = new bytes[](orderContexts.length + 1);
            // Order hash for the target order:
            // 0xe4d3294c5de52d76bedbe00bc37341eaf220a68cb0a1c941eaa2067269ff7f3d
            // 0x47185d0514402c9467090dcd6ed6e96bfd3850f87c185bdc36f2f97da0ab7d81ce90c5b05f94450b6104cde17ba05c67ef523578e809374caca5a3c22b580a64000015d57881603bc7c338f69c94ebc9a8a6091dc78724d6382ea4a93d0961525fe6216d372342a2bb6ab2cce7a025690c91f13c210bfccf08dad0c3b13a4f480aa06e3d61ad8b361ce9bdf85fd0efcb6aa78b96407d6c356d190389971466d20a708f6c16aad9abad499916f1bc20b6c6e6b193be85eaa395789d4d00da7a4e6858f28b81ae9b18f7f0d0b0b3c58bc5ad114a3e19328f8d0904a8f2e1be4275393167
            signatures[0] = abi.encodePacked(
                bytes32(
                    uint256(
                        0x47185d0514402c9467090dcd6ed6e96bfd3850f87c185bdc36f2f97da0ab7d81
                    )
                ),
                bytes32(
                    uint256(
                        0xce90c5b05f94450b6104cde17ba05c67ef523578e809374caca5a3c22b580a64
                    )
                ),
                bytes32(
                    uint256(
                        0x000015d57881603bc7c338f69c94ebc9a8a6091dc78724d6382ea4a93d096152
                    )
                ),
                bytes32(
                    uint256(
                        0x5fe6216d372342a2bb6ab2cce7a025690c91f13c210bfccf08dad0c3b13a4f48
                    )
                ),
                bytes32(
                    uint256(
                        0x0aa06e3d61ad8b361ce9bdf85fd0efcb6aa78b96407d6c356d190389971466d2
                    )
                ),
                bytes32(
                    uint256(
                        0x0a708f6c16aad9abad499916f1bc20b6c6e6b193be85eaa395789d4d00da7a4e
                    )
                ),
                bytes32(
                    uint256(
                        0x6858f28b81ae9b18f7f0d0b0b3c58bc5ad114a3e19328f8d0904a8f2e1be4275
                    )
                ),
                uint24(uint256(0x393167))
            );

            // 0x06eb235f1fa4f39fe4f6903401a0af3296f62ebb08dcbd22897f9cd1bddb17ba57b33b87d6b0129b5c0dc113a2ae6c0f4bd49a35abaddbb182f7e831b242687e
            signatures[1] = abi.encodePacked(
                bytes32(
                    uint256(
                        0x06eb235f1fa4f39fe4f6903401a0af3296f62ebb08dcbd22897f9cd1bddb17ba
                    )
                ),
                bytes32(
                    uint256(
                        0x57b33b87d6b0129b5c0dc113a2ae6c0f4bd49a35abaddbb182f7e831b242687e
                    )
                )
            );

            //
            signatures[2] = abi.encodePacked(
                bytes32(
                    uint256(
                        0x4425d747d5e5ca5344031dce565eb9fce5ff4a510bab4f4209fa5e1b52278b67
                    )
                ),
                bytes32(
                    uint256(
                        0x808b96a8500ca77853623b9b4fc2f7c84356289bffa82ad419eff2d7bdfd9cb6
                    )
                ),
                bytes32(
                    uint256(
                        0x000001c412a2ee2c2edb4a1b16ab207751b275a403d5c6e05ccea7333fe91c8c
                    )
                ),
                bytes32(
                    uint256(
                        0x23d96c0747f21920d93b7918307e1e6f295cae94273a0ffc8e812c6eb62bc4fb
                    )
                ),
                uint24(uint256(0x7bd68e))
            );

            Fee[] memory fees = new Fee[](4);
            fees[0] = Fee({
                recipient: payable(0x0000a26b00c1F0DF003000390027140000fAa719),
                amount: 0,
                bps: 50
            });
            fees[1] = Fee({
                recipient: payable(0x0000a26b00c1F0DF003000390027140000fAa719),
                amount: 0,
                bps: 250
            });
            fees[2] = Fee({
                recipient: payable(0x0000a26b00c1F0DF003000390027140000fAa719),
                amount: 0,
                bps: 250
            });
            fees[3] = Fee({ recipient: address(0), amount: 0, bps: 0 });

            (
                nativeSeaportOrders,
                nativeSeaportFullfillments,
                sumAmountsForNativeSeaportOrders
            ) = seaportOnePointFiveConfig
                .buildOrderAndFulfillmentManyDistinctOrders(
                orderContexts,
                address(0),
                desiredItemsSeaport,
                prices,
                fees,
                signatures
            );

            // The nativeSeaportFullfillments will be created with the
            // assumption that their orders start at the 0 index. That's not the
            // case here, so adjust the order indices accordingly.
            for (uint256 i; i < nativeSeaportFullfillments.length; ++i) {
                FulfillmentComponent[] memory offerComponents =
                    nativeSeaportFullfillments[i].offerComponents;
                for (uint256 j; j < offerComponents.length; ++j) {
                    offerComponents[j].orderIndex += 3;
                }
                FulfillmentComponent[] memory considerationComponents =
                    nativeSeaportFullfillments[i].considerationComponents;
                for (uint256 j; j < considerationComponents.length; ++j) {
                    considerationComponents[j].orderIndex += 3;
                }
            }
        }

        {
            // Set the real values on the orders.

            // protocolData: {
            //     parameters: {
            //     offerer: '0xe4fc2f11f9f7fce3900c82260765f4d10d0eae0c',
            //     offer: [Array],
            //     consideration: [Array],
            //     startTime: '1690780887',
            //     endTime: '1700389266',
            //     orderType: 0,
            //     zone: '0x004C00500000aD104D7DBd00e3ae0A5C00560C00',
            //     zoneHash:
            // '0x0000000000000000000000000000000000000000000000000000000000000000',
            //     salt:
            // '0x72db8c0b0000000000000000000000000000000000000000ec108dddd2303190',
            //     conduitKey:
            // '0x0000007b02230091a7ed01230072f7006a004d60a8d4e71d599b8104250f0000',
            //     totalOriginalConsiderationItems: 2,
            //     counter: 0
            //     },
            //     signature: null
            // },

            nativeSeaportOrders[0].parameters.offerer =
                address(0xe4FC2f11f9F7fce3900c82260765f4d10D0EAE0c);
            nativeSeaportOrders[0].parameters.startTime = 1690780887;
            nativeSeaportOrders[0].parameters.endTime = 1700389266;
            nativeSeaportOrders[0].parameters.orderType = OrderType.FULL_OPEN;
            nativeSeaportOrders[0].parameters.zone =
                address(0x004C00500000aD104D7DBd00e3ae0A5C00560C00);
            nativeSeaportOrders[0].parameters.zoneHash = bytes32(0);
            nativeSeaportOrders[0].parameters.salt = uint256(
                0x72db8c0b0000000000000000000000000000000000000000ec108dddd2303190
            );
            nativeSeaportOrders[0].parameters.conduitKey = bytes32(
                uint256(
                    0x0000007b02230091a7ed01230072f7006a004d60a8d4e71d599b8104250f0000
                )
            );
            nativeSeaportOrders[0].parameters.totalOriginalConsiderationItems =
                2;

            //   protocolData: {
            //     parameters: {
            //     offerer: '0xf05f3c5863b9d36a3d21d0da51394a7b2432a8d5',
            //     offer: [Array],
            //     consideration: [Array],
            //     startTime: '1691739720',
            //     endTime: '1693932382',
            //     orderType: 0,
            //     zone: '0x004C00500000aD104D7DBd00e3ae0A5C00560C00',
            //     zoneHash:
            // '0x0000000000000000000000000000000000000000000000000000000000000000',
            //     salt:
            // '0x360c6ebe0000000000000000000000000000000000000000fc750841be3032c9',
            //     conduitKey:
            // '0x0000007b02230091a7ed01230072f7006a004d60a8d4e71d599b8104250f0000',
            //     totalOriginalConsiderationItems: 2,
            //     counter: 0
            //     },
            //     signature: null
            // },

            nativeSeaportOrders[1].parameters.startTime = 1691739720;
            nativeSeaportOrders[1].parameters.endTime = 1693932382;
            nativeSeaportOrders[1].parameters.orderType = OrderType.FULL_OPEN;
            nativeSeaportOrders[1].parameters.zone =
                address(0x004C00500000aD104D7DBd00e3ae0A5C00560C00);
            nativeSeaportOrders[1].parameters.zoneHash = bytes32(0);
            nativeSeaportOrders[1].parameters.salt = uint256(
                0x360c6ebe0000000000000000000000000000000000000000fc750841be3032c9
            );
            nativeSeaportOrders[1].parameters.conduitKey = bytes32(
                uint256(
                    0x0000007b02230091a7ed01230072f7006a004d60a8d4e71d599b8104250f0000
                )
            );
            nativeSeaportOrders[1].parameters.totalOriginalConsiderationItems =
                2;

            //   protocolData: {
            //     parameters: {
            //     offerer: '0x83fba2bf935b086a83c8c630dbb61c79d286325a',
            //     offer: [Array],
            //     consideration: [Array],
            //     startTime: '1689289751',
            //     endTime: '1705187351',
            //     orderType: 0,
            //     zone: '0x004C00500000aD104D7DBd00e3ae0A5C00560C00',
            //     zoneHash:
            // '0x0000000000000000000000000000000000000000000000000000000000000000',
            //     salt:
            // '0x360c6ebe0000000000000000000000000000000000000000941d1f5654024a1f',
            //     conduitKey:
            // '0x0000007b02230091a7ed01230072f7006a004d60a8d4e71d599b8104250f0000',
            //     totalOriginalConsiderationItems: 2,
            //     counter: 0
            //     },
            //     signature: null
            // },

            nativeSeaportOrders[2].parameters.startTime = 1689289751;
            nativeSeaportOrders[2].parameters.endTime = 1705187351;
            nativeSeaportOrders[2].parameters.orderType = OrderType.FULL_OPEN;
            nativeSeaportOrders[2].parameters.zone =
                address(0x004C00500000aD104D7DBd00e3ae0A5C00560C00);
            nativeSeaportOrders[2].parameters.zoneHash = bytes32(0);
            nativeSeaportOrders[2].parameters.salt = uint256(
                0x360c6ebe0000000000000000000000000000000000000000941d1f5654024a1f
            );
            nativeSeaportOrders[2].parameters.conduitKey = bytes32(
                uint256(
                    0x0000007b02230091a7ed01230072f7006a004d60a8d4e71d599b8104250f0000
                )
            );
            nativeSeaportOrders[2].parameters.totalOriginalConsiderationItems =
                2;
        }

        AdvancedOrder[] memory nativeSeaportAdvancedOrders =
            new AdvancedOrder[](6);

        {
            for (uint256 i; i < nativeSeaportOrders.length; ++i) {
                nativeSeaportAdvancedOrders[i] = AdvancedOrder({
                    parameters: nativeSeaportOrders[i].parameters,
                    numerator: 1,
                    denominator: 1,
                    signature: nativeSeaportOrders[i].signature,
                    extraData: "" // none required on the native orders
                 });

                // TODO: do this for the 1155 order, too. Or maybe already done.

                if (
                    nativeSeaportAdvancedOrders[i]
                        .parameters
                        .consideration
                        .length > 1
                ) {
                    // Set the fee receiver as the recipient on the second
                    // consideration item for each order.
                    nativeSeaportAdvancedOrders[i].parameters.consideration[1]
                        .recipient =
                        payable(0x0000a26b00c1F0DF003000390027140000fAa719);
                } else {
                    // Just to make sure my taker order doesn't have some
                    // garbage sig on
                    // it.
                    nativeSeaportAdvancedOrders[nativeSeaportOrders.length]
                        .signature = "";
                }
            }
        }

        {
            AdvancedOrder memory orderOffer1155;
            AdvancedOrder memory orderConsider1155;

            // https://opensea.io/collection/parallelalpha?search[paymentAssets][0]=PRIME
            // https://opensea.io/assets/ethereum/0x76be3b62873462d2142405439777e971754e8e77/10330

            {
                address offerer =
                    address(0xA017C0f45bB950F00D12798f64986199E10ecf68);
                Item20 memory price = Item20({
                    token: 0xb23d80f5FefcDDaa212212F028021B41DEd428CF,
                    amount: 1.2 ether // 1.2 PRIME
                 });
                Item1155 memory desiredItem = Item1155(
                    address(0x76BE3b62873462d2142405439777e971754E8E77),
                    10330,
                    4
                );
                // 0xda92db6564ba0b8254eefb8d60594ecf035be3b94f0acc6e893ca2e3e124120fa5b5dc7197944d678c7890da06c47364e63a6de6c79517a605e477623f7bbb1900001c6641c7dbd294c6a2ff93a0a7a7a0a95e237e018d746268f3a831aa490d6a483cea9ec80d951a689459d67963c07611562ec06a92e48b4faf224792ed4fc419eec332335edec056c00a9b2e59df7f19b35fa7e633a68a314e0e1af0b3481b7beb9d18dd9706593de49d1f248b97c88e570c4a4c1b7fcbc73f19c4bda0b43c156143689f3b3e8c25fa80d4b9ca20c5b055679dbd051058125dc61fba97fbf48f31
                bytes memory actualSignature = abi.encodePacked(
                    bytes32(
                        uint256(
                            0xda92db6564ba0b8254eefb8d60594ecf035be3b94f0acc6e893ca2e3e124120f
                        )
                    ),
                    bytes32(
                        uint256(
                            0xa5b5dc7197944d678c7890da06c47364e63a6de6c79517a605e477623f7bbb19
                        )
                    ),
                    bytes32(
                        uint256(
                            0x00001c6641c7dbd294c6a2ff93a0a7a7a0a95e237e018d746268f3a831aa490d
                        )
                    ),
                    bytes32(
                        uint256(
                            0x6a483cea9ec80d951a689459d67963c07611562ec06a92e48b4faf224792ed4f
                        )
                    ),
                    bytes32(
                        uint256(
                            0xc419eec332335edec056c00a9b2e59df7f19b35fa7e633a68a314e0e1af0b348
                        )
                    ),
                    bytes32(
                        uint256(
                            0x1b7beb9d18dd9706593de49d1f248b97c88e570c4a4c1b7fcbc73f19c4bda0b4
                        )
                    ),
                    bytes32(
                        uint256(
                            0x3c156143689f3b3e8c25fa80d4b9ca20c5b055679dbd051058125dc61fba97fb
                        )
                    ),
                    uint24(uint256(0xf48f31))
                );

                BasicOrderParameters memory offerParams =
                seaportOnePointFiveConfig
                    .getComponents_BuyOfferedERC1155WithERC20(
                    offerer, desiredItem, price, actualSignature
                );
                //     .getComponents_BuyOfferedERC20WithERC1155(
                //     offerer, price, desiredItem, actualSignature
                // );

                //   protocolData: {
                //         parameters: {
                //         offerer:
                // '0xa017c0f45bb950f00d12798f64986199e10ecf68',
                //         offer: [Array],
                //         consideration: [Array],
                //         startTime: '1691276632',
                //         endTime: '1693955032',
                //         orderType: 1,
                //         zone: '0x004C00500000aD104D7DBd00e3ae0A5C00560C00',
                //         zoneHash:
                // '0x0000000000000000000000000000000000000000000000000000000000000000',
                //         salt:
                // '0x360c6ebe00000000000000000000000000000000000000000be25eadc3975af6',
                //         conduitKey:
                // '0x0000007b02230091a7ed01230072f7006a004d60a8d4e71d599b8104250f0000',
                //         totalOriginalConsiderationItems: 2,
                //         counter: 0
                //         },
                //         signature: null
                //     },

                // TODO: figure out what's wrong with this order.

                orderOffer1155 =
                    _createSeaportOrderFromBasicParams(offerParams, true);

                // Set the actual values for the order.
                orderOffer1155.parameters.offerer =
                    address(0xA017C0f45bB950F00D12798f64986199E10ecf68);
                orderOffer1155.parameters.startTime = 1691276632;
                orderOffer1155.parameters.endTime = 1693955032;
                orderOffer1155.parameters.orderType = OrderType.PARTIAL_OPEN;
                orderOffer1155.parameters.zone =
                    address(0x004C00500000aD104D7DBd00e3ae0A5C00560C00);
                orderOffer1155.parameters.zoneHash = bytes32(0);
                orderOffer1155.parameters.salt = uint256(
                    0x360c6ebe00000000000000000000000000000000000000000be25eadc3975af6
                );
                orderOffer1155.parameters.conduitKey = bytes32(
                    uint256(
                        0x0000007b02230091a7ed01230072f7006a004d60a8d4e71d599b8104250f0000
                    )
                );
                orderOffer1155.parameters.totalOriginalConsiderationItems = 2;
                orderOffer1155.signature = actualSignature;

                // I only want the remaining 2
                desiredItem = Item1155(
                    address(0x76BE3b62873462d2142405439777e971754E8E77),
                    10330,
                    2
                );

                BasicOrderParameters memory considerParams =
                seaportOnePointFiveConfig
                    .getComponents_BuyOfferedERC20WithERC1155(
                    myAddress, price, desiredItem, actualSignature
                );
                //     .getComponents_BuyOfferedERC1155WithERC20(
                //     myAddress, desiredItem, price, actualSignature
                // );

                orderConsider1155 =
                    _createSeaportOrderFromBasicParams(considerParams, false);

                console.log(
                    "orderConsider1155.parameters.consideration[0].startAmount"
                );
                console.log(
                    orderConsider1155.parameters.consideration[0].startAmount
                );

                // Clear the dummy signature.
                orderConsider1155.signature = "";

                // Try setting the fraction on the consider 1155 order.
                orderOffer1155.denominator = 2;

                orderOffer1155.signature = actualSignature;
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
        // order, plus one for each side of the 1155<>20, plus one for the tip)
        Fulfillment[] memory finalFulfillments = new Fulfillment[](14);

        {
            finalOrders[0] = adapterOrders[0]; // Flashloan
            finalOrders[1] = adapterOrders[1]; // Mirror
            finalOrders[2] = adapterOrders[2]; // Adapter
            finalOrders[3] = nativeSeaportAdvancedOrders[0]; // 721<>ETH
            finalOrders[4] = nativeSeaportAdvancedOrders[1]; // 721<>ETH
            finalOrders[5] = nativeSeaportAdvancedOrders[2]; // 721<>ETH
            finalOrders[6] = nativeSeaportAdvancedOrders[3]; // ETH<>721
            finalOrders[7] = nativeSeaportAdvancedOrders[4]; // 1155<>ERC20
            finalOrders[8] = nativeSeaportAdvancedOrders[5]; // ERC20<>1155
        }

        // console.log("finalOrders[6].parameters.offer.length");
        // console.log(finalOrders[6].parameters.offer.length);

        // console.log("uint256(finalOrders[6].parameters.offer[0].itemType)");
        // console.log(uint256(finalOrders[6].parameters.offer[0].itemType));

        // console.log("finalOrders[6].parameters.offer[0].token");
        // console.log(finalOrders[6].parameters.offer[0].token);

        // console.log("finalOrders[6].parameters.offer[0].identifierOrCriteria");
        // console.log(finalOrders[6].parameters.offer[0].identifierOrCriteria);

        // console.log("finalOrders[6].parameters.offer[0].startAmount");
        // console.log(finalOrders[6].parameters.offer[0].startAmount);

        // console.log("finalOrders[6].parameters.offer[0].endAmount");
        // console.log(finalOrders[6].parameters.offer[0].endAmount);

        // console.log("");

        // console.log("finalOrders[6].parameters.consideration.length");
        // console.log(finalOrders[6].parameters.consideration.length);

        // console.log(
        //     "uint256(finalOrders[6].parameters.consideration[0].itemType)"
        // );
        // console.log(
        //     uint256(finalOrders[6].parameters.consideration[0].itemType)
        // );

        // console.log("finalOrders[6].parameters.consideration[0].token");
        // console.log(finalOrders[6].parameters.consideration[0].token);

        // console.log(
        //     "finalOrders[6].parameters.consideration[0].identifierOrCriteria"
        // );
        // console.log(
        //     finalOrders[6].parameters.consideration[0].identifierOrCriteria
        // );

        // console.log("finalOrders[6].parameters.consideration[0].startAmount");
        // console.log(finalOrders[6].parameters.consideration[0].startAmount);

        // console.log("finalOrders[6].parameters.consideration[0].endAmount");
        // console.log(finalOrders[6].parameters.consideration[0].endAmount);

        // console.log("finalOrders[6].parameters.consideration[0].recipient");
        // console.log(finalOrders[6].parameters.consideration[0].recipient);

        // console.log(
        //     "uint256(finalOrders[6].parameters.consideration[1].itemType)"
        // );
        // console.log(
        //     uint256(finalOrders[6].parameters.consideration[1].itemType)
        // );

        // console.log("finalOrders[6].parameters.consideration[1].token");
        // console.log(finalOrders[6].parameters.consideration[1].token);

        // console.log(
        //     "finalOrders[6].parameters.consideration[1].identifierOrCriteria"
        // );
        // console.log(
        //     finalOrders[6].parameters.consideration[1].identifierOrCriteria
        // );

        // console.log("finalOrders[6].parameters.consideration[1].startAmount");
        // console.log(finalOrders[6].parameters.consideration[1].startAmount);

        // console.log("finalOrders[6].parameters.consideration[1].endAmount");
        // console.log(finalOrders[6].parameters.consideration[1].endAmount);

        // console.log("finalOrders[6].parameters.consideration[1].recipient");
        // console.log(finalOrders[6].parameters.consideration[1].recipient);

        // NOTE: I'm probably gonna need to add a fulfillment for the tips or at
        // least a fulfillment component.
        {
            // Fulfillment memory handrolledTipFulfillmentOne;
            // Fulfillment memory handrolledTipFulfillmentTwo;
            // Fulfillment memory handrolledTipFulfillmentThree;
            // Fulfillment memory handrolledTipFulfillmentFour;
            // Fulfillment memory handrolledTipFulfillmentFive;
            // Fulfillment memory handrolledTipFulfillmentSix;

            (
                Fulfillment memory handrolledTipFulfillmentOne,
                Fulfillment memory handrolledTipFulfillmentTwo,
                Fulfillment memory handrolledTipFulfillmentThree,
                Fulfillment memory handrolledTipFulfillmentFour,
                Fulfillment memory handrolledTipFulfillmentFive,
                Fulfillment memory handrolledTipFulfillmentSix
            ) = _generate721Fulfillments();

            (
                Fulfillment memory order1155FulfillmentOne,
                Fulfillment memory order1155FulfillmentTwo,
                Fulfillment memory order1155FulfillmentThree
            ) = _generate1155Fulfillments();

            finalFulfillments[0] = adapterFulfillments[0]; // good
            finalFulfillments[1] = adapterFulfillments[1]; // good

            finalFulfillments[2] = nativeSeaportFullfillments[0]; // good
            finalFulfillments[3] = nativeSeaportFullfillments[1]; // good
            finalFulfillments[4] = nativeSeaportFullfillments[2]; // good

            finalFulfillments[5] = handrolledTipFulfillmentOne;
            finalFulfillments[6] = handrolledTipFulfillmentTwo;
            finalFulfillments[7] = handrolledTipFulfillmentThree;
            finalFulfillments[8] = handrolledTipFulfillmentFour;
            finalFulfillments[9] = handrolledTipFulfillmentFive;
            finalFulfillments[10] = handrolledTipFulfillmentSix;

            // finalFulfillments[8] =
            //     _extendPaymentFulfillmentWithTips(nativeSeaportFullfillments[3]);

            finalFulfillments[11] = order1155FulfillmentOne;
            finalFulfillments[12] = order1155FulfillmentTwo; // good
            finalFulfillments[13] = order1155FulfillmentThree; // good

            // finalFulfillments[0] = adapterFulfillments[0];
            // finalFulfillments[1] = adapterFulfillments[1];
            // finalFulfillments[2] = nativeSeaportFullfillments[0];
            // finalFulfillments[3] = nativeSeaportFullfillments[1];
            // finalFulfillments[4] = nativeSeaportFullfillments[2];
            // finalFulfillments[5] = nativeSeaportFullfillments[3];
            // finalFulfillments[6] = order1155FulfillmentOne;
            // finalFulfillments[7] = order1155FulfillmentOneTip;
            // finalFulfillments[8] = order1155FulfillmentTwo;
        }

        _checkInitialOwnershipState(allItemsToBeProvidedToAdapter, baseCastOfCharacters.fulfiller);

        // TEMP: Just to check on the traces.
        vm.deal(baseCastOfCharacters.fulfiller, 1 ether);
        vm.deal(baseCastOfCharacters.flashloanOfferer, 1 ether);
        vm.startPrank(baseCastOfCharacters.fulfiller);

        // Approve the conduit to transfer the items.
        (bool success, bytes memory returnData) = address(
            0xb23d80f5FefcDDaa212212F028021B41DEd428CF
        ).call(
            abi.encodeWithSignature(
                "approve(address,uint256)",
                baseCastOfCharacters.seaport,
                // address(0x1E0049783F008A0085193E00003D00cd54003c71),
                type(uint256).max
            )
        );

        if (!success) {
            console.log("returnData");
            console.logBytes(returnData);
            revert("Prime approval failed");
        }

        (success, returnData) = seaportAddress.call{
            value: 0.5 ether // TODO: lower to required level
         }(
            abi.encodeWithSelector(
                ConsiderationInterface.matchAdvancedOrders.selector,
                finalOrders,
                new CriteriaResolver[](0),
                finalFulfillments,
                address(0)
            )
        );

        vm.stopPrank();

        if (!success) {
            console.log("returnData");
            console.logBytes(returnData);
            revert("Seaport matchAdvancedOrders failed");
        } else {
            console.log("Seaport matchAdvancedOrders succeeded");
            console.log("returnData");
            console.logBytes(returnData);
            _checkPostCallOwnershipState(allItemsToBeOfferedByAdapter, baseCastOfCharacters.fulfiller);
        }
    }

    // TODO: refactor.
    // TODO: handle the creator fee case.
    function _createSeaportOrderFromBasicParams(
        BasicOrderParameters memory basicParams,
        bool includeTipInConsideration
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

        if (includeTipInConsideration) {
            params.consideration = new ConsiderationItem[](2);
            params.consideration[0] = considerationItem;
            params.consideration[1] = _createOpenSeaTip(considerationItem);

            params.consideration[0].startAmount = params.consideration[0]
                .startAmount - params.consideration[1].startAmount;
            params.consideration[0].endAmount = params.consideration[0]
                .endAmount - params.consideration[1].endAmount;
        } else {
            params.consideration[0] = considerationItem;
        }

        AdvancedOrder memory advancedOrder = AdvancedOrder({
            parameters: params,
            numerator: 1,
            denominator: 1,
            signature: "",
            extraData: new bytes(0)
        });

        return advancedOrder;
    }

    // TODO: Handle the other side.
    function _createOpenSeaTip(ConsiderationItem memory considerationItem)
        internal
        pure
        returns (ConsiderationItem memory)
    {
        uint256 tipAmount = (considerationItem.startAmount / 100 / 100) * 250;

        return ConsiderationItem({
            itemType: considerationItem.itemType,
            token: considerationItem.token,
            identifierOrCriteria: considerationItem.identifierOrCriteria,
            startAmount: tipAmount,
            endAmount: tipAmount,
            recipient: payable(0x0000a26b00c1F0DF003000390027140000fAa719)
        });
    }

    // TODO: turn this into a proper lifecycle step.

    function _checkInitialOwnershipState(
        ConsiderationItem[] memory allItemsToBeProvidedToAdapter, address fulfiller
    ) internal view {
        for (uint256 i; i < allItemsToBeProvidedToAdapter.length; i++) {
            ConsiderationItem memory considerationItem =
                allItemsToBeProvidedToAdapter[i];
            if (considerationItem.itemType == ItemType.NATIVE) {
                // This tx starts with just ETH. The ERC20 balance is going to
                // come mid flight
                require(
                    address(fulfiller).balance >= considerationItem.startAmount,
                    "ETH not owned"
                );
                uint256 lazySum = 0.23934829 ether;
                require(address(fulfiller).balance >= lazySum, "ETH not owned");
            } else if (considerationItem.itemType == ItemType.ERC20) {
                require(
                    IERC20(considerationItem.token).balanceOf(address(fulfiller))
                        >= considerationItem.startAmount,
                    "ERC20 not owned"
                );
            } else if (considerationItem.itemType == ItemType.ERC721) {
                require(
                    IERC721(considerationItem.token).ownerOf(
                        considerationItem.identifierOrCriteria
                    ) == address(fulfiller),
                    "ERC721 not owned"
                );
            } else if (considerationItem.itemType == ItemType.ERC1155) {
                require(
                    IERC1155(considerationItem.token).balanceOf(
                        address(fulfiller), considerationItem.identifierOrCriteria
                    ) >= considerationItem.startAmount,
                    "ERC1155 not owned"
                );
            }
        }
    }

    // TODO: turn this into a proper lifecycle step.

    function _checkPostCallOwnershipState(
        OfferItem[] memory allItemsToBeOfferedByAdapter, address fulfiller
    ) internal view {
        for (uint256 i; i < allItemsToBeOfferedByAdapter.length; i++) {
            OfferItem memory offerItem = allItemsToBeOfferedByAdapter[i];
            // TODO: native, ERC20, and ERC1155 should be a sum check.
            if (offerItem.itemType == ItemType.NATIVE) {
                // TODO: net check.
                require(
                    address(fulfiller).balance >= offerItem.startAmount,
                    "ETH not owned"
                );
            } else if (offerItem.itemType == ItemType.ERC20) {
                // TODO: net check.
                require(
                    IERC20(offerItem.token).balanceOf(address(fulfiller))
                        >= offerItem.startAmount,
                    "ERC20 not owned"
                );
            } else if (offerItem.itemType == ItemType.ERC721) {
                require(
                    IERC721(offerItem.token).ownerOf(
                        offerItem.identifierOrCriteria
                    ) == address(fulfiller),
                    "ERC721 not owned"
                );
            } else if (offerItem.itemType == ItemType.ERC1155) {
                require(
                    IERC1155(offerItem.token).balanceOf(
                        address(fulfiller), offerItem.identifierOrCriteria
                    ) >= offerItem.startAmount,
                    "ERC1155 not owned"
                );
            }
        }
    }

    function _extendPaymentFulfillmentWithTips(Fulfillment memory fulfillment)
        internal
        pure
        returns (Fulfillment memory)
    {
        Fulfillment memory newFulfillment;
        newFulfillment.offerComponents = fulfillment.offerComponents;

        newFulfillment.considerationComponents = new FulfillmentComponent[](
            fulfillment.considerationComponents.length * 2
        );

        // Iterate over the old consideration components, copy them over, and
        // add a new tip component, which has the same order index but 1 instead
        // of 0 for the item index.
        for (uint256 i; i < fulfillment.considerationComponents.length; i++) {
            FulfillmentComponent memory component =
                fulfillment.considerationComponents[i];
            newFulfillment.considerationComponents[i] = component;
            newFulfillment.considerationComponents[i
                + fulfillment.considerationComponents.length] = FulfillmentComponent({
                orderIndex: component.orderIndex,
                itemIndex: 1
            });
        }

        return newFulfillment;
    }

    function _generate721Fulfillments()
        internal
        pure
        returns (
            Fulfillment memory handrolledTipFulfillmentOne,
            Fulfillment memory handrolledTipFulfillmentTwo,
            Fulfillment memory handrolledTipFulfillmentThree,
            Fulfillment memory handrolledTipFulfillmentFour,
            Fulfillment memory handrolledTipFulfillmentFive,
            Fulfillment memory handrolledTipFulfillmentSix
        )
    {
        // ([(6, 0)], [(3, 0)]),
        // ([(6, 0)], [(3, 1)]),

        // ([(6, 0)], [(4, 0)]),
        // ([(6, 0)], [4, 1)]),

        // ([(6, 0)], [(5, 0)),
        // ([(6, 0)], [5, 1)]),

        {
            FulfillmentComponent[] memory offerComponentsOne =
                new FulfillmentComponent[](1);
            FulfillmentComponent[] memory considerationComponentsOne =
                new FulfillmentComponent[](1);

            offerComponentsOne[0] =
                FulfillmentComponent({ orderIndex: 6, itemIndex: 0 });
            considerationComponentsOne[0] =
                FulfillmentComponent({ orderIndex: 3, itemIndex: 0 });

            handrolledTipFulfillmentOne = Fulfillment({
                offerComponents: offerComponentsOne,
                considerationComponents: considerationComponentsOne
            });
        }

        {
            FulfillmentComponent[] memory offerComponentsTwo =
                new FulfillmentComponent[](1);
            FulfillmentComponent[] memory considerationComponentsTwo =
                new FulfillmentComponent[](1);

            offerComponentsTwo[0] =
                FulfillmentComponent({ orderIndex: 6, itemIndex: 0 });
            considerationComponentsTwo[0] =
                FulfillmentComponent({ orderIndex: 3, itemIndex: 1 });

            handrolledTipFulfillmentTwo = Fulfillment({
                offerComponents: offerComponentsTwo,
                considerationComponents: considerationComponentsTwo
            });
        }

        {
            FulfillmentComponent[] memory offerComponentsThree =
                new FulfillmentComponent[](1);
            FulfillmentComponent[] memory considerationComponentsThree =
                new FulfillmentComponent[](1);
            offerComponentsThree[0] =
                FulfillmentComponent({ orderIndex: 6, itemIndex: 0 });
            considerationComponentsThree[0] =
                FulfillmentComponent({ orderIndex: 4, itemIndex: 0 });

            handrolledTipFulfillmentThree = Fulfillment({
                offerComponents: offerComponentsThree,
                considerationComponents: considerationComponentsThree
            });
        }

        {
            FulfillmentComponent[] memory offerComponentsFour =
                new FulfillmentComponent[](1);
            FulfillmentComponent[] memory considerationComponentsFour =
                new FulfillmentComponent[](1);

            offerComponentsFour[0] =
                FulfillmentComponent({ orderIndex: 6, itemIndex: 0 });
            considerationComponentsFour[0] =
                FulfillmentComponent({ orderIndex: 4, itemIndex: 1 });

            handrolledTipFulfillmentFour = Fulfillment({
                offerComponents: offerComponentsFour,
                considerationComponents: considerationComponentsFour
            });
        }

        {
            FulfillmentComponent[] memory offerComponentsFive =
                new FulfillmentComponent[](1);
            FulfillmentComponent[] memory considerationComponentsFive =
                new FulfillmentComponent[](1);

            offerComponentsFive[0] =
                FulfillmentComponent({ orderIndex: 6, itemIndex: 0 });
            considerationComponentsFive[0] =
                FulfillmentComponent({ orderIndex: 5, itemIndex: 0 });

            handrolledTipFulfillmentFive = Fulfillment({
                offerComponents: offerComponentsFive,
                considerationComponents: considerationComponentsFive
            });
        }

        {
            FulfillmentComponent[] memory offerComponentsSix =
                new FulfillmentComponent[](1);
            FulfillmentComponent[] memory considerationComponentsSix =
                new FulfillmentComponent[](1);

            offerComponentsSix[0] =
                FulfillmentComponent({ orderIndex: 6, itemIndex: 0 });
            considerationComponentsSix[0] =
                FulfillmentComponent({ orderIndex: 5, itemIndex: 1 });

            handrolledTipFulfillmentSix = Fulfillment({
                offerComponents: offerComponentsSix,
                considerationComponents: considerationComponentsSix
            });
        }
    }

    function _generate1155Fulfillments()
        internal
        pure
        returns (
            Fulfillment memory order1155FulfillmentOne,
            Fulfillment memory order1155FulfillmentTwo,
            Fulfillment memory order1155FulfillmentThree
        )
    {
        FulfillmentComponent[] memory offerComponentsOne =
            new FulfillmentComponent[](1);
        FulfillmentComponent[] memory considerationComponentsOne =
            new FulfillmentComponent[](1);

        FulfillmentComponent[] memory offerComponentsTwo =
            new FulfillmentComponent[](1);
        FulfillmentComponent[] memory considerationComponentsTwo =
            new FulfillmentComponent[](1);

        FulfillmentComponent[] memory offerComponentsThree =
            new FulfillmentComponent[](1);
        FulfillmentComponent[] memory considerationComponentsThree =
            new FulfillmentComponent[](1);

        {
            // ([(7, 0)], [(8, 0)]),
            // ([(8, 0)], [(7, 0)])
            // ([(8, 0)], [7, 1)])

            offerComponentsOne[0] =
                FulfillmentComponent({ orderIndex: 7, itemIndex: 0 });
            considerationComponentsOne[0] =
                FulfillmentComponent({ orderIndex: 8, itemIndex: 0 });

            offerComponentsTwo[0] =
                FulfillmentComponent({ orderIndex: 8, itemIndex: 0 });
            considerationComponentsTwo[0] =
                FulfillmentComponent({ orderIndex: 7, itemIndex: 0 });

            offerComponentsThree[0] =
                FulfillmentComponent({ orderIndex: 8, itemIndex: 0 });
            considerationComponentsThree[0] =
                FulfillmentComponent({ orderIndex: 7, itemIndex: 1 });
        }

        order1155FulfillmentOne = Fulfillment({
            offerComponents: offerComponentsOne,
            considerationComponents: considerationComponentsOne
        });
        order1155FulfillmentTwo = Fulfillment({
            offerComponents: offerComponentsTwo,
            considerationComponents: considerationComponentsTwo
        });
        order1155FulfillmentThree = Fulfillment({
            offerComponents: offerComponentsThree,
            considerationComponents: considerationComponentsThree
        });
    }
}
