// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import { ConsiderationItemLib } from "seaport-sol/lib/ConsiderationItemLib.sol";

import { OfferItemLib } from "seaport-sol/lib/OfferItemLib.sol";

import { OrderParametersLib } from "seaport-sol/lib/OrderParametersLib.sol";

import { ItemType } from "seaport-types/lib/ConsiderationEnums.sol";

import {
    ConsiderationItem,
    OfferItem,
    OrderParameters,
    SpentItem
} from "seaport-types/lib/ConsiderationStructs.sol";

import {
    AdapterHelperLib,
    Approval,
    CastOfCharacters,
    Flashloan,
    ItemTransfer
} from "../lib/AdapterHelperLib.sol";

import { FlashloanOffererInterface } from
    "../interfaces/FlashloanOffererInterface.sol";

import { GenericAdapterInterface } from
    "../interfaces/GenericAdapterInterface.sol";

import {
    GenericAdapterSidecarInterface,
    Call
} from "../interfaces/GenericAdapterSidecarInterface.sol";

import { BaseMarketConfig } from "../marketplaces/BaseMarketConfig.sol";

import { BlurConfig } from "../marketplaces/blur/BlurConfig.sol";

import { BlurV2Config } from "../marketplaces/blur-2.0/BlurV2Config.sol";

import { FoundationConfig } from
    "../marketplaces/foundation/FoundationConfig.sol";

import { LooksRareConfig } from "../marketplaces/looksRare/LooksRareConfig.sol";

import { LooksRareV2Config } from
    "../marketplaces/looksRare-v2/LooksRareV2Config.sol";

import { SeaportOnePointFiveConfig } from
    "../marketplaces/seaport-1.5/SeaportOnePointFiveConfig.sol";

import { SudoswapConfig } from "../marketplaces/sudoswap/SudoswapConfig.sol";

import { X2Y2Config } from "../marketplaces/X2Y2/X2Y2Config.sol";

import { ZeroExConfig } from "../marketplaces/zeroEx/ZeroExConfig.sol";

import { OrderPayload } from "../utils/Types.sol";

import {
    Call,
    Item20,
    Item721,
    Item1155,
    OrderContext
} from "../lib/AdapterHelperLib.sol";

import { ConsiderationTypeHashes } from
    "../marketplaces/seaport-1.5/lib/ConsiderationTypeHashes.sol";

import "forge-std/console.sol";

// NOTE: I might need something from ConsiderationTypeHashes.sol

library ExternalOrderPayloadHelperLib {
    using ConsiderationItemLib for ConsiderationItem;
    using ConsiderationItemLib for ConsiderationItem[];
    using OfferItemLib for OfferItem;
    using OfferItemLib for OfferItem[];
    using OrderParametersLib for OrderParameters;
    using OrderParametersLib for OrderParameters[];
    using AdapterHelperLib for Call;
    using AdapterHelperLib for Call[];

    BaseMarketConfig blurConfig;
    BaseMarketConfig blurV2Config;
    BaseMarketConfig foundationConfig;
    BaseMarketConfig looksRareConfig;
    BaseMarketConfig looksRareV2Config;
    BaseMarketConfig seaportOnePointFiveConfig;
    BaseMarketConfig sudoswapConfig;
    BaseMarketConfig x2y2Config;
    BaseMarketConfig zeroExConfig;

    FlashloanOffererInterface testFlashloanOfferer;
    GenericAdapterInterface testAdapter;
    GenericAdapterSidecarInterface testSidecar;

    address public flashloanOfferer;
    address public adapter;
    address public sidecar;
    address public wethAddress;
    address public _test20Address;
    address public _test721Address;
    address public _test1155Address;

    uint256 public costOfLastCall;

    Item20 standardWeth;
    Item20 standardERC20;
    Item721 standardERC721;
    Item721 standardERC721Two;
    Item1155 standardERC1155;

    ItemTransfer standardWethTransfer;
    ItemTransfer standard20Transfer;
    ItemTransfer standard721Transfer;
    ItemTransfer standard1155Transfer;

    ISeaport internal constant seaport =
        ISeaport(0x00000000000000ADc04C56Bf30aC9d3c0aAF14dC);

    CastOfCharacters stdCastOfCharacters;

    constructor() {
        blurConfig = BaseMarketConfig(new BlurConfig());
        blurV2Config = BaseMarketConfig(new BlurV2Config());
        foundationConfig = BaseMarketConfig(new FoundationConfig());
        looksRareConfig = BaseMarketConfig(new LooksRareConfig());
        looksRareV2Config = BaseMarketConfig(new LooksRareV2Config());
        seaportOnePointFiveConfig =
            BaseMarketConfig(new SeaportOnePointFiveConfig());
        sudoswapConfig = BaseMarketConfig(new SudoswapConfig());
        x2y2Config = BaseMarketConfig(new X2Y2Config());
        zeroExConfig = BaseMarketConfig(new ZeroExConfig());
    }

    /*//////////////////////////////////////////////////////////////
                        Payload Getters
    //////////////////////////////////////////////////////////////*/

    // TODO: Think about how to gracefully tease out the stuff that doesn't make
    // sense.
    function buyOfferedERC721WithEther_ListOnChain(
        BaseMarketConfig config,
        Item721 memory desiredItem,
        uint256 price
    ) internal prepareTest(config) returns (OrderPayload memory payload) {
        OrderContext memory context =
            OrderContext(true, false, stdCastOfCharacters);

        try config.getPayload_BuyOfferedERC721WithEther(
            context, desiredItem, price
        ) returns (OrderPayload memory payload) {
            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedERC721WithEther_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (OrderPayload memory payload) {
        OrderContext memory context =
            OrderContext(true, true, stdCastOfCharacters);

        bool transfersToSpecifiedTaker = _isSudo(config);

        // This causes the adapter to be set as the token recipient.
        if (transfersToSpecifiedTaker) {
            context.castOfCharacters.fulfiller = adapter;
        }

        try config.getPayload_BuyOfferedERC721WithEther(
            context, standardERC721, 100
        ) returns (OrderPayload memory payload) {
            context.castOfCharacters.fulfiller = bob;

            ItemTransfer[] memory sidecarItemTransfers = new ItemTransfer[](1);
            sidecarItemTransfers[0] = standard721Transfer;

            if (transfersToSpecifiedTaker) {
                // Sudo lets you send the NFT straight to the adapter and
                // Seaport handles it from there.
                sidecarItemTransfers = new ItemTransfer[](0);
            }

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                stdCastOfCharacters,
                OfferItemLib.fromDefaultMany("standardERC721OfferArray"),
                ConsiderationItemLib.fromDefaultMany(
                    "standardNativeConsiderationArray"
                ),
                sidecarItemTransfers
            );

            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedERC721WithEther(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (OrderPayload memory payload)
    {
        try config.getPayload_BuyOfferedERC721WithEther(
            OrderContext(false, false, stdCastOfCharacters), standardERC721, 100
        ) returns (OrderPayload memory payload) {
            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedERC721WithEther_Adapter(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (OrderPayload memory payload)
    {
        OrderContext memory context =
            OrderContext(false, true, stdCastOfCharacters);

        // Blur, LR, and X2Y2 require that the msg.sender is also the taker.
        bool requiresTakesIsSender = _isBlur(config) || _isBlurV2(config)
            || _isLooksRare(config) || _isLooksRareV2(config) || _isX2y2(config);

        if (requiresTakesIsSender) {
            context.castOfCharacters.fulfiller = sidecar;
        }

        try config.getPayload_BuyOfferedERC721WithEther(
            context, standardERC721, 100
        ) returns (OrderPayload memory payload) {
            context.castOfCharacters.fulfiller = bob;

            ItemTransfer[] memory sidecarItemTransfers = new ItemTransfer[](1);
            sidecarItemTransfers[0] = standard721Transfer;

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                stdCastOfCharacters,
                OfferItemLib.fromDefaultMany("standardERC721OfferArray"),
                ConsiderationItemLib.fromDefaultMany(
                    "standardNativeConsiderationArray"
                ),
                sidecarItemTransfers
            );

            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedERC1155WithEther_ListOnChain(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (OrderPayload memory payload)
    {
        try config.getPayload_BuyOfferedERC1155WithEther(
            OrderContext(true, false, stdCastOfCharacters), standardERC1155, 100
        ) returns (OrderPayload memory payload) {
            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedERC1155WithEther_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (OrderPayload memory payload) {
        "(buyOfferedERC1155WithEther_ListOnChain_Adapter)";

        OrderContext memory context =
            OrderContext(true, true, stdCastOfCharacters);

        try config.getPayload_BuyOfferedERC1155WithEther(
            context, standardERC1155, 100
        ) returns (OrderPayload memory payload) {
            ItemTransfer[] memory sidecarItemTransfers = new ItemTransfer[](1);
            sidecarItemTransfers[0] = standard1155Transfer;

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                stdCastOfCharacters,
                OfferItemLib.fromDefaultMany("standardERC1155OfferArray"),
                ConsiderationItemLib.fromDefaultMany(
                    "standardNativeConsiderationArray"
                ),
                sidecarItemTransfers
            );

            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedERC1155WithEther(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (OrderPayload memory payload)
    {
        try config.getPayload_BuyOfferedERC1155WithEther(
            OrderContext(false, false, stdCastOfCharacters),
            standardERC1155,
            100
        ) returns (OrderPayload memory payload) {
            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedERC1155WithEther_Adapter(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (OrderPayload memory payload)
    {
        OrderContext memory context =
            OrderContext(false, true, stdCastOfCharacters);

        // LR requires that the msg.sender is also the taker.
        bool requiresTakesIsSender =
            _isLooksRare(config) || _isLooksRareV2(config) || _isBlurV2(config);

        if (requiresTakesIsSender) {
            context.castOfCharacters.fulfiller = sidecar;
        }

        try config.getPayload_BuyOfferedERC1155WithEther(
            context, standardERC1155, 100
        ) returns (OrderPayload memory payload) {
            context.castOfCharacters.fulfiller = bob;

            ItemTransfer[] memory sidecarItemTransfers = new ItemTransfer[](1);
            sidecarItemTransfers[0] = standard1155Transfer;

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                stdCastOfCharacters,
                OfferItemLib.fromDefaultMany("standardERC1155OfferArray"),
                ConsiderationItemLib.fromDefaultMany(
                    "standardNativeConsiderationArray"
                ),
                sidecarItemTransfers
            );

            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedERC721WithERC20_ListOnChain(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (OrderPayload memory payload)
    {
        try config.getPayload_BuyOfferedERC721WithERC20(
            OrderContext(true, false, stdCastOfCharacters),
            standardERC721,
            standardERC20
        ) returns (OrderPayload memory payload) {
            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedERC721WithERC20_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (OrderPayload memory payload) {
        "(buyOfferedERC721WithERC20_ListOnChain_Adapter)";

        OrderContext memory context =
            OrderContext(true, true, stdCastOfCharacters);

        bool requiresTakerIsSender =
            _isLooksRare(config) || _isLooksRareV2(config);

        // LooksRare requires that the msg.sender is also the taker. So this
        // changes the fulfiller on the context, which changes the taker on the
        // orders created, which allows the sidecar to fulfill the order, and
        // then below the sidecar transfers the NFTs to the adapter, so that
        // Seaport can yoink them out and enforce that the caller gets what the
        // caller expects.
        if (requiresTakerIsSender) {
            context.castOfCharacters.fulfiller = sidecar;
        }

        bool transfersToSpecifiedTaker = _isSudo(config);

        // This causes the adapter to be set as the token recipient, so no
        // transfers from the sidecar are necessary.
        if (transfersToSpecifiedTaker) {
            context.castOfCharacters.fulfiller = adapter;
        }

        try config.getPayload_BuyOfferedERC721WithERC20(
            context, standardERC721, standardERC20
        ) returns (OrderPayload memory payload) {
            context.castOfCharacters.fulfiller = bob;

            ItemTransfer[] memory sidecarItemTransfers = new ItemTransfer[](1);
            sidecarItemTransfers[0] = standard721Transfer;

            if (transfersToSpecifiedTaker) {
                // Sudo lets you send the NFT straight to the adapter and
                // Seaport handles it from there.
                sidecarItemTransfers = new ItemTransfer[](0);
            }

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                stdCastOfCharacters,
                OfferItemLib.fromDefaultMany("standardERC721OfferArray"),
                ConsiderationItemLib.fromDefaultMany(
                    "standardERC20ConsiderationArray"
                ),
                sidecarItemTransfers
            );

            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedERC721WithERC20(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (OrderPayload memory payload)
    {
        try config.getPayload_BuyOfferedERC721WithERC20(
            OrderContext(false, false, stdCastOfCharacters),
            standardERC721,
            standardERC20
        ) returns (OrderPayload memory payload) {
            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedERC721WithERC20_Adapter(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (OrderPayload memory payload)
    {
        OrderContext memory context =
            OrderContext(false, true, stdCastOfCharacters);

        bool requiresTakerIsSender =
            _isLooksRare(config) || _isLooksRareV2(config) || _isX2y2(config);

        if (requiresTakerIsSender) {
            context.castOfCharacters.fulfiller = sidecar;
        }

        try config.getPayload_BuyOfferedERC721WithERC20(
            context, standardERC721, standardERC20
        ) returns (OrderPayload memory payload) {
            // Put the context back.
            context.castOfCharacters.fulfiller = bob;

            ItemTransfer[] memory sidecarItemTransfers = new ItemTransfer[](1);
            sidecarItemTransfers[0] = standard721Transfer;

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                stdCastOfCharacters,
                OfferItemLib.fromDefaultMany("standardERC721OfferArray"),
                ConsiderationItemLib.fromDefaultMany(
                    "standardERC20ConsiderationArray"
                ),
                sidecarItemTransfers
            );

            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedERC721WithWETH_ListOnChain(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (OrderPayload memory payload)
    {
        try config.getPayload_BuyOfferedERC721WithERC20(
            OrderContext(true, false, stdCastOfCharacters),
            standardERC721,
            standardWeth
        ) returns (OrderPayload memory payload) {
            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedERC721WithWETH_Adapter(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (OrderPayload memory payload)
    {
        OrderContext memory context =
            OrderContext(false, true, stdCastOfCharacters);

        bool requiresTakerIsSender = _isBlur(config) || _isLooksRare(config)
            || _isLooksRareV2(config) || _isX2y2(config);

        if (requiresTakerIsSender) {
            context.castOfCharacters.fulfiller = sidecar;
        }

        try config.getPayload_BuyOfferedERC721WithWETH(
            context, standardERC721, standardWeth
        ) returns (OrderPayload memory payload) {
            // Put the context back.
            context.castOfCharacters.fulfiller = bob;

            ConsiderationItem[] memory adapterOrderConsideration =
            ConsiderationItemLib.fromDefaultMany(
                "standardWethConsiderationArray"
            );

            ItemTransfer[] memory sidecarItemTransfers = new ItemTransfer[](1);
            sidecarItemTransfers[0] = standard721Transfer;

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                stdCastOfCharacters,
                OfferItemLib.fromDefaultMany("standardERC721OfferArray"),
                adapterOrderConsideration,
                sidecarItemTransfers
            );

            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedERC721WithBETH(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (OrderPayload memory payload)
    {
        beth.deposit{ value: 100 }();

        OrderContext memory context =
            OrderContext(false, false, stdCastOfCharacters);

        try config.getPayload_BuyOfferedERC721WithBETH(
            context, Item721(address(test721_1), 1), Item20(address(beth), 100)
        ) returns (OrderPayload memory payload) {
            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedERC721WithBETH_Adapter(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (OrderPayload memory payload)
    {
        // Bob doesn't deposit BETH for this, he sends native tokens, gets a
        // flashloan, which goes from adapter to sidecar to BETH's deposit
        // function, and then the sidecar uses the BETH to fulfill the listing.
        // beth.deposit{ value: 100 }();

        OrderContext memory context =
            OrderContext(false, true, stdCastOfCharacters);

        bool requiresTakerIsSender = _isBlur(config) || _isBlurV2(config);

        if (requiresTakerIsSender) {
            context.castOfCharacters.fulfiller = sidecar;
        }

        try config.getPayload_BuyOfferedERC721WithBETH(
            context, Item721(address(test721_1), 1), Item20(address(beth), 100)
        ) returns (OrderPayload memory payload) {
            context.castOfCharacters.fulfiller = bob;

            ConsiderationItem[] memory adapterOrderConsideration =
                new ConsiderationItem[](1);
            adapterOrderConsideration[0] = ConsiderationItemLib.fromDefault(
                "standardNativeConsiderationItem"
            );

            Flashloan[] memory flashloans = new Flashloan[](1);

            Flashloan memory flashloan = Flashloan({
                amount: uint88(100),
                itemType: ItemType.NATIVE,
                token: address(0),
                shouldCallback: true,
                recipient: context.castOfCharacters.adapter
            });

            flashloans[0] = flashloan;

            Call[] memory sidecarSetUpCalls = new Call[](1);
            Call memory call = Call({
                target: address(beth),
                allowFailure: false,
                value: 100,
                callData: abi.encodeWithSelector(beth.deposit.selector)
            });
            sidecarSetUpCalls[0] = call;

            ItemTransfer[] memory sidecarItemTransfers = new ItemTransfer[](1);
            sidecarItemTransfers[0] = standard721Transfer;

            Call[] memory sidecarMarketplaceCalls;
            sidecarMarketplaceCalls = new Call[](1);
            sidecarMarketplaceCalls[0] = payload.executeOrder;

            payload.executeOrder = AdapterHelperLib
                .createSeaportWrappedCallParameters(
                sidecarMarketplaceCalls,
                sidecarSetUpCalls,
                new Call[](0),
                stdCastOfCharacters,
                flashloans,
                OfferItemLib.fromDefaultMany("standardERC721OfferArray"),
                adapterOrderConsideration,
                sidecarItemTransfers
            );

            payload.executeOrder.value = 100;

            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedERC721WithWETH_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (OrderPayload memory payload) {
        "(buyOfferedERC721WithWETH_ListOnChain_Adapter)";

        OrderContext memory context =
            OrderContext(true, true, stdCastOfCharacters);

        bool requiresTakerIsSender =
            _isBlur(config) || _isLooksRare(config) || _isX2y2(config);

        // These aren't actually working. They're not implemented yet.
        if (requiresTakerIsSender) {
            context.castOfCharacters.fulfiller = sidecar;
        }

        try config.getPayload_BuyOfferedERC721WithERC20(
            context, standardERC721, standardWeth
        ) returns (OrderPayload memory payload) {
            context.castOfCharacters.fulfiller = bob;

            ConsiderationItem[] memory adapterOrderConsideration =
            ConsiderationItemLib.fromDefaultMany(
                "standardWethConsiderationArray"
            );

            ItemTransfer[] memory sidecarItemTransfers = new ItemTransfer[](1);
            sidecarItemTransfers[0] = standard721Transfer;

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                stdCastOfCharacters,
                OfferItemLib.fromDefaultMany("standardERC721OfferArray"),
                adapterOrderConsideration,
                sidecarItemTransfers
            );

            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedERC721WithWETH(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (OrderPayload memory payload)
    {
        try config.getPayload_BuyOfferedERC721WithWETH(
            OrderContext(false, false, stdCastOfCharacters),
            standardERC721,
            standardWeth
        ) returns (OrderPayload memory payload) {
            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedERC1155WithERC20_ListOnChain(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (OrderPayload memory payload)
    {
        try config.getPayload_BuyOfferedERC1155WithERC20(
            OrderContext(true, false, stdCastOfCharacters),
            standardERC1155,
            standardERC20
        ) returns (OrderPayload memory payload) {
            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedERC1155WithERC20_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (OrderPayload memory payload) {
        "(buyOfferedERC1155WithERC20_ListOnChain_Adapter)";

        OrderContext memory context =
            OrderContext(true, true, stdCastOfCharacters);

        try config.getPayload_BuyOfferedERC1155WithERC20(
            context, standardERC1155, standardERC20
        ) returns (OrderPayload memory payload) {
            ItemTransfer[] memory sidecarItemTransfers = new ItemTransfer[](1);
            sidecarItemTransfers[0] = standard1155Transfer;

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                stdCastOfCharacters,
                OfferItemLib.fromDefaultMany("standardERC1155OfferArray"),
                ConsiderationItemLib.fromDefaultMany(
                    "standardERC20ConsiderationArray"
                ),
                sidecarItemTransfers
            );

            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedERC1155WithERC20(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (OrderPayload memory payload)
    {
        try config.getPayload_BuyOfferedERC1155WithERC20(
            OrderContext(false, false, stdCastOfCharacters),
            standardERC1155,
            standardERC20
        ) returns (OrderPayload memory payload) {
            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedERC1155WithERC20_Adapter(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (OrderPayload memory payload)
    {
        OrderContext memory context =
            OrderContext(false, true, stdCastOfCharacters);

        bool requiresTakerIsSender =
            _isLooksRare(config) || _isLooksRareV2(config);

        if (requiresTakerIsSender) {
            context.castOfCharacters.fulfiller = sidecar;
        }

        try config.getPayload_BuyOfferedERC1155WithERC20(
            context, standardERC1155, standardERC20
        ) returns (OrderPayload memory payload) {
            // Put the context back.
            context.castOfCharacters.fulfiller = bob;

            ItemTransfer[] memory sidecarItemTransfers = new ItemTransfer[](1);
            sidecarItemTransfers[0] = standard1155Transfer;

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                stdCastOfCharacters,
                OfferItemLib.fromDefaultMany("standardERC1155OfferArray"),
                ConsiderationItemLib.fromDefaultMany(
                    "standardERC20ConsiderationArray"
                ),
                sidecarItemTransfers
            );

            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedERC20WithERC721_ListOnChain(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (OrderPayload memory payload)
    {
        try config.getPayload_BuyOfferedERC20WithERC721(
            OrderContext(true, false, stdCastOfCharacters),
            standardERC20,
            standardERC721
        ) returns (OrderPayload memory payload) {
            // Allow the market to escrow after listing
            assert(
                test20.balanceOf(alice) == 100
                    || test20.balanceOf(config.market()) == 100
            );

            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedERC20WithERC721_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (OrderPayload memory payload) {
        "(buyOfferedERC20WithERC721_ListOnChain_Adapter)";

        OrderContext memory context =
            OrderContext(true, true, stdCastOfCharacters);

        // Turns out X2Y2 doesn't support this, but if it did, it would need
        // this.
        bool requiresTakerIsSender = _isX2y2(config);

        // X2Y2 requires that the taker is the msg.sender.
        if (requiresTakerIsSender) {
            context.castOfCharacters.fulfiller = sidecar;
        }

        bool transfersToSpecifiedTaker = _isSudo(config);

        if (transfersToSpecifiedTaker) {
            context.castOfCharacters.fulfiller = adapter;
        }

        try config.getPayload_BuyOfferedERC20WithERC721(
            context, standardERC20, standardERC721
        ) returns (OrderPayload memory payload) {
            context.castOfCharacters.fulfiller = bob;

            // Allow the market to escrow after listing
            assert(
                test20.balanceOf(alice) == 100
                    || test20.balanceOf(config.market()) == 100
            );

            ItemTransfer[] memory sidecarItemTransfers = new ItemTransfer[](1);
            sidecarItemTransfers[0] = standard20Transfer;

            if (transfersToSpecifiedTaker) {
                sidecarItemTransfers = new ItemTransfer[](0);
            }

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                stdCastOfCharacters,
                OfferItemLib.fromDefaultMany("standardERC20OfferArray"),
                ConsiderationItemLib.fromDefaultMany(
                    "standardERC721ConsiderationArray"
                ),
                sidecarItemTransfers
            );

            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedERC20WithERC721(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (OrderPayload memory payload)
    {
        try config.getPayload_BuyOfferedERC20WithERC721(
            OrderContext(false, false, stdCastOfCharacters),
            standardERC20,
            standardERC721
        ) returns (OrderPayload memory payload) {
            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedERC20WithERC721_Adapter(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (OrderPayload memory payload)
    {
        OrderContext memory context =
            OrderContext(false, true, stdCastOfCharacters);

        bool requiresTakerIsSender =
            _isLooksRare(config) || _isLooksRareV2(config) || _isX2y2(config);

        if (requiresTakerIsSender) {
            context.castOfCharacters.fulfiller = sidecar;
        }

        try config.getPayload_BuyOfferedERC20WithERC721(
            context, standardERC20, standardERC721
        ) returns (OrderPayload memory payload) {
            // Put the context back.
            context.castOfCharacters.fulfiller = bob;

            ItemTransfer[] memory sidecarItemTransfers = new ItemTransfer[](1);
            sidecarItemTransfers[0] = standard20Transfer;

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                stdCastOfCharacters,
                OfferItemLib.fromDefaultMany("standardERC20OfferArray"),
                ConsiderationItemLib.fromDefaultMany(
                    "standardERC721ConsiderationArray"
                ),
                sidecarItemTransfers
            );

            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedWETHWithERC721_ListOnChain(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (OrderPayload memory payload)
    {
        try config.getPayload_BuyOfferedWETHWithERC721(
            OrderContext(true, false, stdCastOfCharacters),
            standardWeth,
            standardERC721
        ) returns (OrderPayload memory payload) {
            // Allow the market to escrow after listing
            assert();

            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedWETHWithERC721_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (OrderPayload memory payload) {
        "(buyOfferedWETHWithERC721_ListOnChain_Adapter)";

        OrderContext memory context =
            OrderContext(true, true, stdCastOfCharacters);

        try config.getPayload_BuyOfferedWETHWithERC721(
            context, standardWeth, standardERC721
        ) returns (OrderPayload memory payload) {
            // Allow the market to escrow after listing
            assert();

            // Look into why test20 requires an explicit approval lol.

            ItemTransfer[] memory sidecarItemTransfers = new ItemTransfer[](1);
            sidecarItemTransfers[0] = standardWethTransfer;

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                stdCastOfCharacters,
                OfferItemLib.fromDefaultMany("standardWethOfferArray"),
                ConsiderationItemLib.fromDefaultMany(
                    "standardERC721ConsiderationArray"
                ),
                sidecarItemTransfers
            );

            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedWETHWithERC721(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (OrderPayload memory payload)
    {
        try config.getPayload_BuyOfferedWETHWithERC721(
            OrderContext(false, false, stdCastOfCharacters),
            standardWeth,
            standardERC721
        ) returns (OrderPayload memory payload) {
            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedWETHWithERC721_Adapter(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (OrderPayload memory payload)
    {
        OrderContext memory context =
            OrderContext(false, true, stdCastOfCharacters);

        bool requiresTakerIsSender = _isBlur(config) || _isLooksRare(config)
            || _isLooksRareV2(config) || _isX2y2(config);

        if (requiresTakerIsSender) {
            context.castOfCharacters.fulfiller = sidecar;
        }

        try config.getPayload_BuyOfferedWETHWithERC721(
            context, standardWeth, standardERC721
        ) returns (OrderPayload memory payload) {
            context.castOfCharacters.fulfiller = bob;

            ItemTransfer[] memory sidecarItemTransfers = new ItemTransfer[](1);
            sidecarItemTransfers[0] = standardWethTransfer;

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                stdCastOfCharacters,
                OfferItemLib.fromDefaultMany("standardWethOfferArray"),
                ConsiderationItemLib.fromDefaultMany(
                    "standardERC721ConsiderationArray"
                ),
                sidecarItemTransfers
            );

            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedBETHWithERC721(BaseMarketConfig config)
        internal
        prepareTest(config)
    {
        beth.deposit{ value: 100 }();
        try config.getPayload_BuyOfferedBETHWithERC721(
            OrderContext(false, false, stdCastOfCharacters),
            Item20(address(beth), 100),
            Item721(address(test721_1), 1)
        ) returns (OrderPayload memory payload) {
            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedBETHWithERC721_Adapter(BaseMarketConfig config)
        internal
        prepareTest(config)
    {
        beth.deposit{ value: 100 }();

        OrderContext memory context =
            OrderContext(false, true, stdCastOfCharacters);

        bool requiresTakerIsSender = _isBlurV2(config);

        if (requiresTakerIsSender) {
            context.castOfCharacters.fulfiller = sidecar;
        }

        try config.getPayload_BuyOfferedBETHWithERC721(
            context, Item20(address(beth), 100), Item721(address(test721_1), 1)
        ) returns (OrderPayload memory payload) {
            // Sidecar's not going to transfer anything.
            ItemTransfer[] memory sidecarItemTransfers = new ItemTransfer[](0);

            // Bob expects to get 100 native tokens.
            OfferItem[] memory adapterOrderOffer = new OfferItem[](1);
            adapterOrderOffer[0] =
                OfferItemLib.fromDefault("standardNativeOfferItem");

            // This converts the BETH received by the sidecar into native tokens
            // which should make their way to bob.
            Call[] memory sidecarWrapUpCalls = new Call[](2);
            Call memory bethCall = Call({
                target: address(beth),
                allowFailure: false,
                value: 0,
                callData: abi.encodeWithSelector(beth.withdraw.selector, 100)
            });
            Call memory sendNativeTokensToSeaportCall = Call({
                target: seaportAddress,
                allowFailure: false,
                value: 100,
                callData: ""
            });
            sidecarWrapUpCalls[0] = bethCall;
            sidecarWrapUpCalls[1] = sendNativeTokensToSeaportCall;

            Call[] memory sidecarMarketplaceCalls;
            sidecarMarketplaceCalls = new Call[](1);
            sidecarMarketplaceCalls[0] = payload.executeOrder;

            payload.executeOrder = AdapterHelperLib
                .createSeaportWrappedCallParameters(
                sidecarMarketplaceCalls,
                new Call[](0),
                sidecarWrapUpCalls,
                stdCastOfCharacters,
                new Flashloan[](0),
                adapterOrderOffer,
                ConsiderationItemLib.fromDefaultMany(
                    "standardERC721ConsiderationArray"
                ),
                sidecarItemTransfers
            );

            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedERC20WithERC1155_ListOnChain(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (OrderPayload memory payload)
    {
        OrderContext memory context =
            OrderContext(true, false, stdCastOfCharacters);
        try config.getPayload_BuyOfferedERC20WithERC1155(
            context, standardERC20, standardERC1155
        ) returns (OrderPayload memory payload) {
            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedERC20WithERC1155_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (OrderPayload memory payload) {
        "(buyOfferedERC20WithERC1155_ListOnChain_Adapter)";

        OrderContext memory context =
            OrderContext(true, true, stdCastOfCharacters);
        try config.getPayload_BuyOfferedERC20WithERC1155(
            context, standardERC20, standardERC1155
        ) returns (OrderPayload memory payload) {
            ItemTransfer[] memory sidecarItemTransfers = new ItemTransfer[](1);
            sidecarItemTransfers[0] = standard20Transfer;

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                stdCastOfCharacters,
                OfferItemLib.fromDefaultMany("standardERC20OfferArray"),
                ConsiderationItemLib.fromDefaultMany(
                    "standardERC1155ConsiderationArray"
                ),
                sidecarItemTransfers
            );

            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedERC20WithERC1155(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (OrderPayload memory payload)
    {
        OrderContext memory context =
            OrderContext(false, false, stdCastOfCharacters);
        try config.getPayload_BuyOfferedERC20WithERC1155(
            context, standardERC20, standardERC1155
        ) returns (OrderPayload memory payload) {
            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedERC20WithERC1155_Adapter(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (OrderPayload memory payload)
    {
        OrderContext memory context =
            OrderContext(false, true, stdCastOfCharacters);

        bool requiresTakerIsSender =
            _isLooksRare(config) || _isLooksRareV2(config);

        // Cheat the context for LR.
        if (requiresTakerIsSender) {
            context.castOfCharacters.fulfiller = sidecar;
        }

        try config.getPayload_BuyOfferedERC20WithERC1155(
            context, standardERC20, standardERC1155
        ) returns (OrderPayload memory payload) {
            // Put the context back.
            context.castOfCharacters.fulfiller = bob;

            ItemTransfer[] memory sidecarItemTransfers = new ItemTransfer[](1);
            sidecarItemTransfers[0] = standard20Transfer;

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                stdCastOfCharacters,
                OfferItemLib.fromDefaultMany("standardERC20OfferArray"),
                ConsiderationItemLib.fromDefaultMany(
                    "standardERC1155ConsiderationArray"
                ),
                sidecarItemTransfers
            );

            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedERC721WithERC1155_ListOnChain(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (OrderPayload memory payload)
    {
        OrderContext memory context =
            OrderContext(true, false, stdCastOfCharacters);
        try config.getPayload_BuyOfferedERC721WithERC1155(
            context, standardERC721, standardERC1155
        ) returns (OrderPayload memory payload) {
            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedERC721WithERC1155_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (OrderPayload memory payload) {
        "(buyOfferedERC721WithERC1155_ListOnChain_Adapter)";

        // Only seaport, skip for now.
        _logNotSupported();
        return 0;

        // OrderContext memory context = OrderContext(
        //     true, true, stdCastOfCharacters
        // );
        // try config.getPayload_BuyOfferedERC721WithERC1155(
        //     context,
        //     standardERC721,
        //     standardERC1155
        // ) returns (OrderPayload memory payload) {
        //     gasUsed = _benchmarkCallWithParams(
        //         config.name(),
        //         string(abi.encodePacked(testLabel, " List")),
        //         alice,
        //         payload.submitOrder
        //     );

        //     assertEq(test721_1.ownerOf(1), alice);
        //     assertEq(test1155_1.balanceOf(bob, 1), 1);

        //     gasUsed = _benchmarkCallWithParams(
        //         config.name(),
        //         string(abi.encodePacked(testLabel, " Fulfill*")),true,
        //         bob,
        //         payload.executeOrder
        //     );

        //     assertEq(test721_1.ownerOf(1), bob);
        //     assertEq(test1155_1.balanceOf(alice, 1), 1);
        // } catch {
        //     _logNotSupported();
        // }
    }

    function buyOfferedERC721WithERC1155(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (OrderPayload memory payload)
    {
        OrderContext memory context =
            OrderContext(false, false, stdCastOfCharacters);
        try config.getPayload_BuyOfferedERC721WithERC1155(
            context, standardERC721, standardERC1155
        ) returns (OrderPayload memory payload) {
            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedERC721WithERC1155_Adapter(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (OrderPayload memory payload)
    {
        // Only seaport, skip for now.
        _logNotSupported();
        return 0;

        // OrderContext memory context = OrderContext(
        //     false, true, stdCastOfCharacters
        // );
        // try config.getPayload_BuyOfferedERC721WithERC1155(
        //     context,
        //     standardERC721,
        //     standardERC1155
        // ) returns (OrderPayload memory payload) {
        //     assertEq(test721_1.ownerOf(1), alice);
        //     assertEq(test1155_1.balanceOf(bob, 1), 1);

        //     gasUsed = _benchmarkCallWithParams(
        //         config.name(),
        //         string(abi.encodePacked(testLabel, " Fulfill w/ Sig*")),true,
        //         bob,
        //         payload.executeOrder
        //     );

        //     assertEq(test721_1.ownerOf(1), bob);
        //     assertEq(test1155_1.balanceOf(alice, 1), 1);
        // } catch {
        //     _logNotSupported();
        // }
    }

    function buyOfferedERC1155WithERC721_ListOnChain(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (OrderPayload memory payload)
    {
        OrderContext memory context =
            OrderContext(true, false, stdCastOfCharacters);
        try config.getPayload_BuyOfferedERC1155WithERC721(
            context, standardERC1155, standardERC721
        ) returns (OrderPayload memory payload) {
            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedERC1155WithERC721_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (OrderPayload memory payload) {
        "(buyOfferedERC1155WithERC721_ListOnChain_Adapter)";

        // Only seaport so skipping here.
        _logNotSupported();
        return 0;
    }

    function buyOfferedERC1155WithERC721(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (OrderPayload memory payload)
    {
        OrderContext memory context =
            OrderContext(false, false, stdCastOfCharacters);
        try config.getPayload_BuyOfferedERC1155WithERC721(
            context, standardERC1155, standardERC721
        ) returns (OrderPayload memory payload) {
            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedERC1155WithERC721_Adapter(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (OrderPayload memory payload)
    {
        // Only seaport so skipping here for now.
        _logNotSupported();
        return payload;
    }

    function buyOfferedERC721WithEtherFee_ListOnChain(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (OrderPayload memory payload)
    {
        try config.getPayload_BuyOfferedERC721WithEtherOneFeeRecipient(
            OrderContext(true, false, stdCastOfCharacters),
            standardERC721,
            500, // increased so that the fee recipient recieves 1%
            feeReciever1,
            5
        ) returns (OrderPayload memory payload) {
            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedERC721WithEtherFee_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (OrderPayload memory payload) {
        "(buyOfferedERC721WithEtherFee_ListOnChain_Adapter)";

        OrderContext memory context =
            OrderContext(true, true, stdCastOfCharacters);

        try config.getPayload_BuyOfferedERC721WithEtherOneFeeRecipient(
            context,
            standardERC721,
            500, // increased so that the fee recipient recieves 1%
            feeReciever1,
            5
        ) returns (OrderPayload memory payload) {
            ConsiderationItem[] memory considerationArray =
            new ConsiderationItem[](
                1
            );
            considerationArray[0] = ConsiderationItemLib.fromDefault(
                "standardNativeConsiderationItem"
            ).withStartAmount(505).withEndAmount(505);

            ItemTransfer[] memory sidecarItemTransfers = new ItemTransfer[](1);
            sidecarItemTransfers[0] = standard721Transfer;

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                stdCastOfCharacters,
                OfferItemLib.fromDefaultMany("standardERC721OfferArray"),
                considerationArray,
                sidecarItemTransfers
            );

            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedERC721WithEtherFee(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (OrderPayload memory payload)
    {
        try config.getPayload_BuyOfferedERC721WithEtherOneFeeRecipient(
            OrderContext(false, false, stdCastOfCharacters),
            standardERC721,
            100,
            feeReciever1,
            5
        ) returns (OrderPayload memory payload) {
            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedERC721WithEtherFee_Adapter(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (OrderPayload memory payload)
    {
        OrderContext memory context =
            OrderContext(false, true, stdCastOfCharacters);

        bool requiresTakerIsSender = _isX2y2(config);

        if (requiresTakerIsSender) {
            context.castOfCharacters.fulfiller = sidecar;
        }

        try config.getPayload_BuyOfferedERC721WithEtherOneFeeRecipient(
            context, standardERC721, 100, feeReciever1, 5
        ) returns (OrderPayload memory payload) {
            context.castOfCharacters.fulfiller = bob;

            ConsiderationItem[] memory considerationArray =
            new ConsiderationItem[](
                1
            );
            considerationArray[0] = ConsiderationItemLib.fromDefault(
                "standardNativeConsiderationItem"
            ).withStartAmount(105).withEndAmount(105);

            ItemTransfer[] memory sidecarItemTransfers = new ItemTransfer[](1);
            sidecarItemTransfers[0] = standard721Transfer;

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                stdCastOfCharacters,
                OfferItemLib.fromDefaultMany("standardERC721OfferArray"),
                considerationArray,
                sidecarItemTransfers
            );

            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedERC721WithEtherFeeTwoRecipients_ListOnChain(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (OrderPayload memory payload) {
        "(buyOfferedERC721WithEtherFeeTwoRecipients_ListOnChain)";
        try config.getPayload_BuyOfferedERC721WithEtherTwoFeeRecipient(
            OrderContext(true, false, stdCastOfCharacters),
            standardERC721,
            100,
            feeReciever1,
            5,
            feeReciever2,
            5
        ) returns (OrderPayload memory payload) {
            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedERC721WithEtherFeeTwoRecipients_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (OrderPayload memory payload) {
        "(buyOfferedERC721WithEtherFeeTwoRecipients_ListOnChain_Adapter)";

        OrderContext memory context =
            OrderContext(true, true, stdCastOfCharacters);

        try config.getPayload_BuyOfferedERC721WithEtherTwoFeeRecipient(
            context, standardERC721, 100, feeReciever1, 5, feeReciever2, 5
        ) returns (OrderPayload memory payload) {
            assert(
                test721_1.ownerOf(1) == alice
                    || test721_1.ownerOf(1) == config.market()
            );

            ConsiderationItem[] memory considerationArray =
            new ConsiderationItem[](
                1
            );
            considerationArray[0] = ConsiderationItemLib.fromDefault(
                "standardNativeConsiderationItem"
            ).withStartAmount(110).withEndAmount(110);

            ItemTransfer[] memory sidecarItemTransfers = new ItemTransfer[](1);
            sidecarItemTransfers[0] = standard721Transfer;

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                stdCastOfCharacters,
                OfferItemLib.fromDefaultMany("standardERC721OfferArray"),
                considerationArray,
                sidecarItemTransfers
            );

            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedERC721WithEtherFeeTwoRecipients(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (OrderPayload memory payload)
    {
        try config.getPayload_BuyOfferedERC721WithEtherTwoFeeRecipient(
            OrderContext(false, false, stdCastOfCharacters),
            standardERC721,
            100,
            feeReciever1,
            5,
            feeReciever2,
            5
        ) returns (OrderPayload memory payload) {
            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyOfferedERC721WithEtherFeeTwoRecipients_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (OrderPayload memory payload) {
        "(buyOfferedERC721WithEtherFeeTwoRecipients_Adapter)";

        OrderContext memory context =
            OrderContext(false, true, stdCastOfCharacters);

        bool requiresTakerIsSender = _isX2y2(config);

        if (requiresTakerIsSender) {
            context.castOfCharacters.fulfiller = sidecar;
        }

        try config.getPayload_BuyOfferedERC721WithEtherTwoFeeRecipient(
            context, standardERC721, 100, feeReciever1, 5, feeReciever2, 5
        ) returns (OrderPayload memory payload) {
            context.castOfCharacters.fulfiller = bob;

            ConsiderationItem[] memory considerationArray =
            new ConsiderationItem[](
                1
            );
            considerationArray[0] = ConsiderationItemLib.fromDefault(
                "standardNativeConsiderationItem"
            ).withStartAmount(110).withEndAmount(110);

            ItemTransfer[] memory sidecarItemTransfers = new ItemTransfer[](1);
            sidecarItemTransfers[0] = standard721Transfer;

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                stdCastOfCharacters,
                OfferItemLib.fromDefaultMany("standardERC721OfferArray"),
                considerationArray,
                sidecarItemTransfers
            );

            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyTenOfferedERC721WithEther_ListOnChain(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (OrderPayload memory payload)
    {
        Item721[] memory nfts = new Item721[](10);
        for (uint256 i = 0; i < 10; i++) {
            nfts[i] = Item721(_test721Address, i + 1);
        }

        try config.getPayload_BuyOfferedManyERC721WithEther(
            OrderContext(true, false, stdCastOfCharacters), nfts, 100
        ) returns (OrderPayload memory payload) {
            for (uint256 i = 0; i < 10; i++) {
                assertTrue(
                    test721_1.ownerOf(i + 1) == alice
                        || test721_1.ownerOf(i + 1) == config.market(),
                    "Not owner"
                );
            }

            return payload;

            for (uint256 i = 0; i < 10; i++) { }
        } catch {
            _logNotSupported();
        }
    }

    function buyTenOfferedERC721WithEther_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (OrderPayload memory payload) {
        "(buyTenOfferedERC721WithEther_ListOnChain_Adapter)";

        OrderContext memory context =
            OrderContext(true, true, stdCastOfCharacters);

        bool transfersToSpecifiedTaker = _isSudo(config);

        if (transfersToSpecifiedTaker) {
            context.castOfCharacters.fulfiller = adapter;
        }

        Item721[] memory nfts = new Item721[](10);
        for (uint256 i = 0; i < 10; i++) {
            nfts[i] = Item721(_test721Address, i + 1);
        }

        try config.getPayload_BuyOfferedManyERC721WithEther(context, nfts, 100)
        returns (OrderPayload memory payload) {
            for (uint256 i = 0; i < 10; i++) {
                assertTrue(
                    test721_1.ownerOf(i + 1) == alice
                        || test721_1.ownerOf(i + 1) == config.market(),
                    "Not owner"
                );
            }

            OfferItem[] memory adapterOrderOffer = new OfferItem[](nfts.length);

            ItemTransfer[] memory sidecarItemTransfers =
                new ItemTransfer[](nfts.length);
            for (uint256 i; i < nfts.length; i++) {
                sidecarItemTransfers[i] = ItemTransfer({
                    from: sidecar,
                    to: adapter,
                    token: nfts[i].token,
                    identifier: nfts[i].identifier,
                    amount: 1,
                    itemType: ItemType.ERC721
                });

                adapterOrderOffer[i] = OfferItemLib.fromDefault(
                    "standardERC721OfferItem"
                ).withToken(nfts[i].token).withIdentifierOrCriteria(
                    nfts[i].identifier
                );
            }

            if (transfersToSpecifiedTaker) {
                sidecarItemTransfers = new ItemTransfer[](0);
            }

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                stdCastOfCharacters,
                adapterOrderOffer,
                ConsiderationItemLib.fromDefaultMany(
                    "standardNativeConsiderationArray"
                ),
                sidecarItemTransfers
            );

            return payload;

            for (uint256 i = 0; i < 10; i++) { }
        } catch {
            _logNotSupported();
        }
    }

    function buyTenOfferedERC721WithEther(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (OrderPayload memory payload)
    {
        Item721[] memory nfts = new Item721[](10);
        for (uint256 i = 0; i < 10; i++) {
            nfts[i] = Item721(_test721Address, i + 1);
        }

        try config.getPayload_BuyOfferedManyERC721WithEther(
            OrderContext(false, false, stdCastOfCharacters), nfts, 100
        ) returns (OrderPayload memory payload) {
            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function buyTenOfferedERC721WithEther_Adapter(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (OrderPayload memory payload)
    {
        OrderContext memory context =
            OrderContext(false, true, stdCastOfCharacters);

        bool requiresTakerIsSender =
            _isBlurV2(config) || _isX2y2(config) || _isLooksRareV2(config);

        if (requiresTakerIsSender) {
            context.castOfCharacters.fulfiller = sidecar;
        }

        Item721[] memory nfts = new Item721[](10);
        for (uint256 i = 0; i < 10; i++) {
            nfts[i] = Item721(_test721Address, i + 1);
        }

        try config.getPayload_BuyOfferedManyERC721WithEther(context, nfts, 100)
        returns (OrderPayload memory payload) {
            context.castOfCharacters.fulfiller = bob;

            for (uint256 i = 0; i < 10; i++) { }

            OfferItem[] memory adapterOrderOffer = new OfferItem[](nfts.length);

            ItemTransfer[] memory sidecarItemTransfers =
                new ItemTransfer[](nfts.length);
            for (uint256 i; i < nfts.length; i++) {
                sidecarItemTransfers[i] = ItemTransfer({
                    from: sidecar,
                    to: adapter,
                    token: nfts[i].token,
                    identifier: nfts[i].identifier,
                    amount: 1,
                    itemType: ItemType.ERC721
                });

                adapterOrderOffer[i] = OfferItemLib.fromDefault(
                    "standardERC721OfferItem"
                ).withToken(nfts[i].token).withIdentifierOrCriteria(
                    nfts[i].identifier
                );
            }

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                stdCastOfCharacters,
                adapterOrderOffer,
                ConsiderationItemLib.fromDefaultMany(
                    "standardNativeConsiderationArray"
                ),
                sidecarItemTransfers
            );

            return payload;

            for (uint256 i = 0; i < 10; i++) { }
        } catch {
            _logNotSupported();
        }
    }

    function buyTenOfferedERC721WithEtherDistinctOrders(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (OrderPayload memory payload)
    {
        OrderContext[] memory contexts = new OrderContext[](10);
        Item721[] memory nfts = new Item721[](10);
        uint256[] memory ethAmounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            nfts[i] = Item721(_test721Address, i + 1);
            contexts[i] = OrderContext(false, false, stdCastOfCharacters);
            ethAmounts[i] = 100 + i;
        }

        try config.getPayload_BuyOfferedManyERC721WithEtherDistinctOrders(
            contexts, nfts, ethAmounts
        ) returns (OrderPayload memory payload) {
            

            return payload;

            
        } catch {
            _logNotSupported();
        }
    }

    function buyTenOfferedERC721WithEtherDistinctOrders_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (OrderPayload memory payload) {
        "(buyTenOfferedERC721WithEtherDistinctOrders_Adapter)";

        bool requiresTakerIsSender = _isBlur(config) || _isBlurV2(config)
            || _isLooksRareV2(config) || _isX2y2(config);

        OrderContext[] memory contexts = new OrderContext[](10);
        Item721[] memory nfts = new Item721[](10);
        uint256[] memory ethAmounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            nfts[i] = Item721(_test721Address, i + 1);
            contexts[i] = OrderContext(false, true, stdCastOfCharacters);

            contexts[i].castOfCharacters.fulfiller =
                requiresTakerIsSender ? sidecar : bob;
            ethAmounts[i] = 100 + i;
        }

        try config.getPayload_BuyOfferedManyERC721WithEtherDistinctOrders(
            contexts, nfts, ethAmounts
        ) returns (OrderPayload memory payload) {
            for (uint256 i = 0; i < 10; i++) {
                contexts[i].castOfCharacters.fulfiller = bob;
            }

            

            uint256 flashloanAmount;

            for (uint256 i = 0; i < ethAmounts.length; i++) {
                flashloanAmount += ethAmounts[i];
            }

            ConsiderationItem[] memory considerationArray =
            new ConsiderationItem[](
                1
            );
            considerationArray[0] = ConsiderationItemLib.fromDefault(
                "standardNativeConsiderationItem"
            ).withStartAmount(flashloanAmount).withEndAmount(flashloanAmount);

            OfferItem[] memory adapterOrderOffer = new OfferItem[](nfts.length);

            ItemTransfer[] memory sidecarItemTransfers =
                new ItemTransfer[](nfts.length);
            for (uint256 i; i < nfts.length; i++) {
                sidecarItemTransfers[i] = ItemTransfer({
                    from: sidecar,
                    to: adapter,
                    token: nfts[i].token,
                    identifier: nfts[i].identifier,
                    amount: 1,
                    itemType: ItemType.ERC721
                });

                adapterOrderOffer[i] = OfferItemLib.fromDefault(
                    "standardERC721OfferItem"
                ).withToken(nfts[i].token).withIdentifierOrCriteria(
                    nfts[i].identifier
                );
            }

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                stdCastOfCharacters,
                adapterOrderOffer,
                considerationArray,
                sidecarItemTransfers
            );

            return payload;

            
        } catch {
            _logNotSupported();
        }
    }

    function buyTenOfferedERC721WithEtherDistinctOrders_ListOnChain(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (OrderPayload memory payload) {
        "(buyTenOfferedERC721WithEtherDistinctOrders_ListOnChain)";

        OrderContext[] memory contexts = new OrderContext[](10);
        Item721[] memory nfts = new Item721[](10);
        uint256[] memory ethAmounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            nfts[i] = Item721(_test721Address, i + 1);
            contexts[i] = OrderContext(true, false, stdCastOfCharacters);
            ethAmounts[i] = 100 + i;
        }

        try config.getPayload_BuyOfferedManyERC721WithEtherDistinctOrders(
            contexts, nfts, ethAmounts
        ) returns (OrderPayload memory payload) {
            // @dev checking ownership here (when nfts are escrowed in different
            // contracts) is messy so we skip it for now

            return payload;

            
        } catch {
            _logNotSupported();
        }
    }

    function buyTenOfferedERC721WithEtherDistinctOrders_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (OrderPayload memory payload) {
        "(buyTenOfferedERC721WithEtherDistinctOrders_ListOnChain_Adapter)";

        bool transfersToSpecifiedTaker = _isSudo(config);

        OrderContext[] memory contexts = new OrderContext[](10);
        Item721[] memory nfts = new Item721[](10);
        uint256[] memory ethAmounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            nfts[i] = Item721(_test721Address, i + 1);
            contexts[i] = OrderContext(true, true, stdCastOfCharacters);

            contexts[i].castOfCharacters.fulfiller =
                transfersToSpecifiedTaker ? adapter : bob;

            // There's something screwy with the ETH amounts here. For some
            // reason, this needs to be 101 instead of 100 like it is in its
            // sibling test. Only Sudo and Seaport are set up for this, and
            // Seaport doesn't get tested. So, leaving it alone for now.
            ethAmounts[i] = 101 + i;
        }

        try config.getPayload_BuyOfferedManyERC721WithEtherDistinctOrders(
            contexts, nfts, ethAmounts
        ) returns (OrderPayload memory payload) {
            for (uint256 i = 0; i < 10; i++) {
                contexts[i].castOfCharacters.fulfiller = bob;
            }

            uint256 flashloanAmount;

            for (uint256 i; i < ethAmounts.length; i++) {
                flashloanAmount += ethAmounts[i];
            }

            OfferItem[] memory adapterOrderOffer = new OfferItem[](nfts.length);

            for (uint256 i; i < nfts.length; i++) {
                adapterOrderOffer[i] = OfferItemLib.fromDefault(
                    "standardERC721OfferItem"
                ).withToken(nfts[i].token).withIdentifierOrCriteria(
                    nfts[i].identifier
                );
            }

            ConsiderationItem[] memory considerationArray =
            new ConsiderationItem[](
                1
            );
            considerationArray[0] = ConsiderationItemLib.fromDefault(
                "standardNativeConsiderationItem"
            ).withStartAmount(flashloanAmount).withEndAmount(flashloanAmount);

            ItemTransfer[] memory sidecarItemTransfers =
                new ItemTransfer[](nfts.length);
            for (uint256 i; i < nfts.length; i++) {
                sidecarItemTransfers[i] = ItemTransfer({
                    from: sidecar,
                    to: adapter,
                    token: nfts[i].token,
                    identifier: nfts[i].identifier,
                    amount: 1,
                    itemType: ItemType.ERC721
                });
            }

            // Sudo does the transfers.
            if (transfersToSpecifiedTaker) {
                sidecarItemTransfers = new ItemTransfer[](0);
            }

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                stdCastOfCharacters,
                adapterOrderOffer,
                considerationArray,
                sidecarItemTransfers
            );

            payload.executeOrder.value = flashloanAmount;

            return payload;

            
        } catch {
            _logNotSupported();
        }
    }

    function buyTenOfferedERC721WithErc20DistinctOrders(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (OrderPayload memory payload)
    {
        OrderContext[] memory contexts = new OrderContext[](10);
        Item721[] memory nfts = new Item721[](10);
        uint256[] memory erc20Amounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            nfts[i] = Item721(_test721Address, i + 1);
            contexts[i] = OrderContext(false, false, stdCastOfCharacters);
            erc20Amounts[i] = 100 + i;
        }

        try config.getPayload_BuyOfferedManyERC721WithErc20DistinctOrders(
            contexts, _test20Address, nfts, erc20Amounts
        ) returns (OrderPayload memory payload) {
            

            return payload;

            
        } catch {
            _logNotSupported();
        }
    }

    function buyTenOfferedERC721WithErc20DistinctOrders_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (OrderPayload memory payload) {
        "(buyTenOfferedERC721WithErc20DistinctOrders_Adapter)";

        OrderContext[] memory contexts = new OrderContext[](10);
        Item721[] memory nfts = new Item721[](10);
        uint256[] memory erc20Amounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            nfts[i] = Item721(_test721Address, i + 1);
            contexts[i] = OrderContext(false, true, stdCastOfCharacters);
            erc20Amounts[i] = 100 + i;
        }

        bool requiresTakerIsSender =
            _isLooksRare(config) || _isLooksRareV2(config) || _isX2y2(config);

        if (requiresTakerIsSender) {
            for (uint256 i = 0; i < contexts.length; i++) {
                contexts[i].castOfCharacters.fulfiller =
                    address(contexts[i].castOfCharacters.sidecar);
            }
        }

        try config.getPayload_BuyOfferedManyERC721WithErc20DistinctOrders(
            contexts, _test20Address, nfts, erc20Amounts
        ) returns (OrderPayload memory payload) {
            for (uint256 i = 0; i < contexts.length; i++) {
                contexts[i].castOfCharacters.fulfiller = bob;
            }

            

            ConsiderationItem[] memory adapterOrderConsideration =
                new ConsiderationItem[](1);

            uint256 totalERC20Amount;

            for (uint256 i = 0; i < contexts.length; i++) {
                totalERC20Amount += erc20Amounts[i];
            }

            adapterOrderConsideration[0] = ConsiderationItemLib.fromDefault(
                "standardERC20ConsiderationItem"
            ).withStartAmount(totalERC20Amount).withEndAmount(totalERC20Amount);

            OfferItem[] memory adapterOrderOffer = new OfferItem[](nfts.length);
            ItemTransfer[] memory sidecarItemTransfers =
                new ItemTransfer[](nfts.length);

            for (uint256 i; i < nfts.length; i++) {
                sidecarItemTransfers[i] = ItemTransfer({
                    from: sidecar,
                    to: adapter,
                    token: nfts[i].token,
                    identifier: nfts[i].identifier,
                    amount: 1,
                    itemType: ItemType.ERC721
                });

                adapterOrderOffer[i] = OfferItemLib.fromDefault(
                    "standardERC721OfferItem"
                ).withToken(nfts[i].token).withIdentifierOrCriteria(
                    nfts[i].identifier
                );
            }

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                stdCastOfCharacters,
                adapterOrderOffer,
                adapterOrderConsideration,
                sidecarItemTransfers
            );

            return payload;

            
        } catch {
            _logNotSupported();
        }
    }

    function buyTenOfferedERC721WithErc20DistinctOrders_ListOnChain(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (OrderPayload memory payload) {
        "(buyTenOfferedERC721WithErc20DistinctOrders_ListOnChain)";

        OrderContext[] memory contexts = new OrderContext[](10);
        Item721[] memory nfts = new Item721[](10);
        uint256[] memory erc20Amounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            nfts[i] = Item721(_test721Address, i + 1);
            contexts[i] = OrderContext(true, false, stdCastOfCharacters);
            erc20Amounts[i] = 100 + i;
        }

        try config.getPayload_BuyOfferedManyERC721WithErc20DistinctOrders(
            contexts, _test20Address, nfts, erc20Amounts
        ) returns (OrderPayload memory payload) {
            return payload;

            
        } catch {
            _logNotSupported();
        }
    }

    function buyTenOfferedERC721WithErc20DistinctOrders_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (OrderPayload memory payload) {
        "(buyTenOfferedERC721WithErc20DistinctOrders_ListOnChain_Adapter)";

        OrderContext[] memory contexts = new OrderContext[](10);
        Item721[] memory nfts = new Item721[](10);
        uint256[] memory erc20Amounts = new uint256[](10);

        bool requiresTakerIsSender =
            _isLooksRare(config) || _isLooksRareV2(config) || _isX2y2(config);

        // Ah crap this turns out to be only implemented for Seaport, so this is
        // a no-op for now.
        if (requiresTakerIsSender) {
            for (uint256 i = 0; i < contexts.length; i++) {
                contexts[i].castOfCharacters.fulfiller =
                    address(contexts[i].castOfCharacters.sidecar);
            }
        }

        for (uint256 i = 0; i < 10; i++) {
            nfts[i] = Item721(_test721Address, i + 1);
            contexts[i] = OrderContext(true, true, stdCastOfCharacters);
            erc20Amounts[i] = 100 + i;
        }

        try config.getPayload_BuyOfferedManyERC721WithErc20DistinctOrders(
            contexts, _test20Address, nfts, erc20Amounts
        ) returns (OrderPayload memory payload) {
            for (uint256 i = 0; i < contexts.length; i++) {
                contexts[i].castOfCharacters.fulfiller = bob;
            }

            ConsiderationItem[] memory adapterOrderConsideration =
                new ConsiderationItem[](1);

            uint256 totalERC20Amount;

            for (uint256 i = 0; i < contexts.length; i++) {
                totalERC20Amount += erc20Amounts[i];
            }

            adapterOrderConsideration[0] = ConsiderationItemLib.fromDefault(
                "standardERC20ConsiderationItem"
            ).withStartAmount(totalERC20Amount).withEndAmount(totalERC20Amount);

            OfferItem[] memory adapterOrderOffer = new OfferItem[](nfts.length);

            ItemTransfer[] memory sidecarItemTransfers =
                new ItemTransfer[](nfts.length);

            for (uint256 i; i < nfts.length; i++) {
                sidecarItemTransfers[i] = ItemTransfer({
                    from: sidecar,
                    to: adapter,
                    token: nfts[i].token,
                    identifier: nfts[i].identifier,
                    amount: 1,
                    itemType: ItemType.ERC721
                });

                adapterOrderOffer[i] = OfferItemLib.fromDefault(
                    "standardERC721OfferItem"
                ).withToken(nfts[i].token).withIdentifierOrCriteria(
                    nfts[i].identifier
                );
            }

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                stdCastOfCharacters,
                adapterOrderOffer,
                adapterOrderConsideration,
                sidecarItemTransfers
            );

            return payload;

            
        } catch {
            _logNotSupported();
        }
    }

    function buyTenOfferedERC721WithWETHDistinctOrders(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (OrderPayload memory payload)
    {
        OrderContext[] memory contexts = new OrderContext[](10);
        Item721[] memory nfts = new Item721[](10);
        uint256[] memory wethAmounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            nfts[i] = Item721(_test721Address, i + 1);
            contexts[i] = OrderContext(false, false, stdCastOfCharacters);
            wethAmounts[i] = 100 + i;
        }

        try config.getPayload_BuyOfferedManyERC721WithWETHDistinctOrders(
            contexts, wethAddress, nfts, wethAmounts
        ) returns (OrderPayload memory payload) {
            

            return payload;

            
        } catch {
            _logNotSupported();
        }
    }

    function buyTenOfferedERC721WithWETHDistinctOrders_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (OrderPayload memory payload) {
        OrderContext[] memory contexts = new OrderContext[](10);
        Item721[] memory nfts = new Item721[](10);
        uint256[] memory wethAmounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            nfts[i] = Item721(_test721Address, i + 1);
            contexts[i] = OrderContext(false, true, stdCastOfCharacters);
            wethAmounts[i] = 100 + i;
        }

        bool requiresTakerIsSender =
            _isBlur(config) || _isLooksRareV2(config) || _isX2y2(config);

        if (requiresTakerIsSender) {
            for (uint256 i = 0; i < contexts.length; i++) {
                contexts[i].castOfCharacters.fulfiller = sidecar;
            }
        }

        try config.getPayload_BuyOfferedManyERC721WithWETHDistinctOrders(
            contexts, wethAddress, nfts, wethAmounts
        ) returns (OrderPayload memory payload) {
            for (uint256 i = 0; i < contexts.length; i++) {
                contexts[i].castOfCharacters.fulfiller = bob;
            }

            

            uint256 totalWethAmount;

            for (uint256 i = 0; i < wethAmounts.length; i++) {
                totalWethAmount += wethAmounts[i];
            }

            ConsiderationItem[] memory considerationArray =
                new ConsiderationItem[](1);
            considerationArray[0] = ConsiderationItemLib.fromDefault(
                "standardWethConsiderationItem"
            ).withStartAmount(totalWethAmount).withEndAmount(totalWethAmount);

            OfferItem[] memory adapterOrderOffer = new OfferItem[](nfts.length);
            ItemTransfer[] memory sidecarItemTransfers =
                new ItemTransfer[](nfts.length);

            for (uint256 i; i < nfts.length; i++) {
                sidecarItemTransfers[i] = ItemTransfer({
                    from: sidecar,
                    to: adapter,
                    token: nfts[i].token,
                    identifier: nfts[i].identifier,
                    amount: 1,
                    itemType: ItemType.ERC721
                });

                adapterOrderOffer[i] = OfferItemLib.fromDefault(
                    "standardERC721OfferItem"
                ).withToken(nfts[i].token).withIdentifierOrCriteria(
                    nfts[i].identifier
                );
            }

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                stdCastOfCharacters,
                adapterOrderOffer,
                considerationArray,
                sidecarItemTransfers
            );

            return payload;

            
        } catch {
            _logNotSupported();
        }
    }

    function buyTenOfferedERC721WithWETHDistinctOrders_ListOnChain(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (OrderPayload memory payload) {
        "(buyTenOfferedERC721WithWETHDistinctOrders_ListOnChain)";

        OrderContext[] memory contexts = new OrderContext[](10);
        Item721[] memory nfts = new Item721[](10);
        uint256[] memory wethAmounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            nfts[i] = Item721(_test721Address, i + 1);
            contexts[i] = OrderContext(true, false, stdCastOfCharacters);
            wethAmounts[i] = 100 + i;
        }

        try config.getPayload_BuyOfferedManyERC721WithWETHDistinctOrders(
            contexts, wethAddress, nfts, wethAmounts
        ) returns (OrderPayload memory payload) {
            return payload;

            
        } catch {
            _logNotSupported();
        }
    }

    // This is a no-op for now.
    function buyTenOfferedERC721WithWETHDistinctOrders_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (OrderPayload memory payload) {
        "(buyTenOfferedERC721WithWETHDistinctOrders_ListOnChain_Adapter)";

        OrderContext[] memory contexts = new OrderContext[](10);
        Item721[] memory nfts = new Item721[](10);
        uint256[] memory wethAmounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            nfts[i] = Item721(_test721Address, i + 1);
            contexts[i] = OrderContext(true, true, stdCastOfCharacters);
            wethAmounts[i] = 100 + i;
        }

        try config.getPayload_BuyOfferedManyERC721WithWETHDistinctOrders(
            contexts, wethAddress, nfts, wethAmounts
        ) returns (OrderPayload memory payload) {
            ConsiderationItem[] memory considerationArray =
            new ConsiderationItem[](
                1
            );
            considerationArray[0] = ConsiderationItemLib.fromDefault(
                "standardNativeConsiderationItem"
            ).withStartAmount(0).withEndAmount(0);

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                stdCastOfCharacters,
                new OfferItem[](0), // TODO: add boilerplate for conditionality
                considerationArray,
                new ItemTransfer[](0)
            );

            return payload;

            
        } catch {
            _logNotSupported();
        }
    }

    function benchmark_MatchOrders_ABCA(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (OrderPayload memory payload)
    {
        OrderContext[] memory contexts = new OrderContext[](3);
        Item721[] memory nfts = new Item721[](3);

        contexts[0] = OrderContext(
            false,
            false,
            CastOfCharacters({
                offerer: alice,
                fulfiller: address(0),
                seaport: address(0),
                flashloanOfferer: flashloanOfferer,
                adapter: adapter,
                sidecar: sidecar
            })
        );
        contexts[1] = OrderContext(
            false,
            false,
            CastOfCharacters({
                offerer: cal,
                fulfiller: address(0),
                seaport: address(0),
                flashloanOfferer: flashloanOfferer,
                adapter: adapter,
                sidecar: sidecar
            })
        );
        contexts[2] = OrderContext(
            false,
            false,
            CastOfCharacters({
                offerer: bob,
                fulfiller: address(0),
                seaport: address(0),
                flashloanOfferer: flashloanOfferer,
                adapter: adapter,
                sidecar: sidecar
            })
        );

        nfts[0] = standardERC721;
        nfts[1] = standardERC721Two;
        nfts[2] = Item721(_test721Address, 3);

        try config.getPayload_MatchOrders_ABCA(contexts, nfts) returns (
            OrderPayload memory payload
        ) {
            return payload;
        } catch {
            _logNotSupported();
        }
    }

    function benchmark_MatchOrders_ABCA_Adapter(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (OrderPayload memory payload)
    {
        // Seaport only.
        _logNotSupported();
        return 0;
    }

    /*//////////////////////////////////////////////////////////////
                          Helpers
    //////////////////////////////////////////////////////////////*/

    // Note: this is where `_setApprovals` in `prepareTest` was.
    // TODO: Think about making a nice tool to set up necessary approvals.

    // TODO: make this a script that initializes the contracts.
    function _setAdapterSpecificApprovals() internal {
        // This is where the users of the adapter approve the adapter to
        // transfer their tokens.
        address[] memory adapterUsers = new address[](3);
        adapterUsers[0] = address(alice);
        adapterUsers[1] = address(bob);
        adapterUsers[2] = address(cal);

        Approval[] memory approvalsOfTheAdapter = new Approval[](5);
        approvalsOfTheAdapter[0] = Approval(_test20Address, ItemType.ERC20);
        approvalsOfTheAdapter[1] = Approval(_test721Address, ItemType.ERC721);
        approvalsOfTheAdapter[2] = Approval(_test1155Address, ItemType.ERC1155);
        approvalsOfTheAdapter[3] = Approval(wethAddress, ItemType.ERC20);

        for (uint256 i; i < adapterUsers.length; i++) {
            for (uint256 j; j < approvalsOfTheAdapter.length; j++) {
                Approval memory approval = approvalsOfTheAdapter[j];

                bool success;

                uint256 selector;
                uint256 approvalValue;

                assembly {
                    let approvalType := gt(mload(add(0x20, approval)), 1)
                    approvalValue := sub(approvalType, iszero(approvalType))
                    selector :=
                        add(
                            mul(0x095ea7b3, iszero(approvalType)),
                            mul(0xa22cb465, approvalType)
                        )
                }

                (success,) = address(approval.token).call(
                    abi.encodeWithSelector(
                        bytes4(bytes32(selector << 224)), adapter, approvalValue
                    )
                );

                if (!success) {
                    revert("Generic adapter approval failed.");
                }
            }
        }

        // This is where the adapter approves Seaport.
        Approval[] memory approvalsByTheAdapter = new Approval[](4);
        approvalsByTheAdapter[0] = Approval(_test20Address, ItemType.ERC20);
        approvalsByTheAdapter[1] = Approval(_test721Address, ItemType.ERC721);
        approvalsByTheAdapter[2] = Approval(_test1155Address, ItemType.ERC1155);
        approvalsByTheAdapter[3] = Approval(wethAddress, ItemType.ERC20);

        bytes memory contextArg = AdapterHelperLib.createGenericAdapterContext(
            approvalsByTheAdapter, new Call[](0)
        );

        // Prank seaport to allow hitting the adapter directly.
        testAdapter.generateOrder(
            address(this), new SpentItem[](0), new SpentItem[](0), contextArg
        );

        test20.approve(sidecar, type(uint256).max);
    }

    function _doSetup() internal {
        testFlashloanOfferer = FlashloanOffererInterface(
            deployCode(
                "out/FlashloanOfferer.sol/FlashloanOfferer.json",
                abi.encode(seaportAddress)
            )
        );

        testAdapter = GenericAdapterInterface(
            deployCode(
                "out/GenericAdapter.sol/GenericAdapter.json",
                abi.encode(seaportAddress, address(testFlashloanOfferer))
            )
        );

        testSidecar = GenericAdapterSidecarInterface(
            abi.decode(entries[0].data, (address))
        );

        flashloanOfferer = address(testFlashloanOfferer);
        adapter = address(testAdapter);
        sidecar = address(testSidecar);
        wethAddress = address(weth);

        // TODO: set up the live contracts.
    }

    function _isSudo(BaseMarketConfig config) internal view returns (bool) {
        return _sameName(config.name(), sudoswapConfig.name());
    }

    function _isBlur(BaseMarketConfig config) internal view returns (bool) {
        return _sameName(config.name(), blurConfig.name());
    }

    function _isBlurV2(BaseMarketConfig config) internal view returns (bool) {
        return _sameName(config.name(), blurV2Config.name());
    }

    function _isX2y2(BaseMarketConfig config) internal view returns (bool) {
        return _sameName(config.name(), x2y2Config.name());
    }

    function _isLooksRare(BaseMarketConfig config)
        internal
        view
        returns (bool)
    {
        return _sameName(config.name(), looksRareConfig.name());
    }

    function _isLooksRareV2(BaseMarketConfig config)
        internal
        view
        returns (bool)
    {
        return _sameName(config.name(), looksRareV2Config.name());
    }

    function _sameName(string memory name1, string memory name2)
        internal
        pure
        returns (bool)
    {
        return keccak256(bytes(name1)) == keccak256(bytes(name2));
    }

    function _logNotSupported(string memory name, string memory label)
        internal
    {
        console.log(
            "Not currently supported. See <some_README> for details on how to add support."
        );
    }
}
