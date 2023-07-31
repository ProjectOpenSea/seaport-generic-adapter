// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

// TODO: Come back and clean up imports.

import { WETH } from "solady/src/tokens/WETH.sol";

import { ConsiderationItemLib } from "seaport-sol/lib/ConsiderationItemLib.sol";

import { OfferItemLib } from "seaport-sol/lib/OfferItemLib.sol";

import { OrderParametersLib } from "seaport-sol/lib/OrderParametersLib.sol";

import { ConsiderationInterface } from
    "seaport-types/interfaces/ConsiderationInterface.sol";

import { ItemType } from "seaport-types/lib/ConsiderationEnums.sol";

import {
    ConsiderationItem,
    OfferItem,
    OrderParameters,
    SpentItem
} from "seaport-types/lib/ConsiderationStructs.sol";

import { OrderPayload } from "../utils/Types.sol";

import {
    Call,
    AdapterHelperLib,
    Approval,
    CastOfCharacters,
    Flashloan,
    Item1155,
    Item20,
    Item721,
    ItemTransfer,
    OrderContext
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

import { ConsiderationTypeHashes } from
    "../marketplaces/seaport-1.5/lib/ConsiderationTypeHashes.sol";

import "forge-std/console.sol";

// NOTE: I might need something from ConsiderationTypeHashes.sol

struct Fee {
    address recipient;
    uint256 amount;
}
// TODO: switch to a percentage.

// TODO: think about whether this can be a library.
contract ExternalOrderPayloadHelper {
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

    FlashloanOffererInterface flashloanOffererInterface;
    GenericAdapterInterface adapterInterface;
    GenericAdapterSidecarInterface sidecarInterface;

    address public flashloanOfferer;
    address public adapter;
    address public sidecar;
    address public wethAddress;

    ConsiderationInterface internal constant seaport =
        ConsiderationInterface(0x00000000000000ADc04C56Bf30aC9d3c0aAF14dC);

    WETH internal constant beth =
        WETH(payable(0x0000000000A39bb272e79075ade125fd351887Ac));

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

        wethAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    }

    /*//////////////////////////////////////////////////////////////
                        Payload Getters
    //////////////////////////////////////////////////////////////*/

    // TODO: Think about how to gracefully tease out the stuff that doesn't make
    // sense (eg the listing payloads).
    function getPayloadToBuyOfferedERC721WithEther_ListOnChain(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item721 memory desiredItem,
        uint256 price
    )
        public
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: true,
            routeThroughAdapter: false,
            castOfCharacters: castOfCharacters
        });

        try config.getPayload_BuyOfferedERC721WithEther(
            context, desiredItem, price
        ) returns (OrderPayload memory payload) {
            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyOfferedERC721WithEther_ListOnChain_FulfillThroughAdapter(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item721 memory desiredItem,
        uint256 price
    )
        public
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: true,
            routeThroughAdapter: true,
            castOfCharacters: castOfCharacters
        });

        bool transfersToSpecifiedTaker = _isSudo(config);

        address originalFulfiller = context.castOfCharacters.fulfiller;

        // This causes the adapter to be set as the token recipient in the
        // `getPayload_BuyOfferedERC721WithEther` function call.
        if (transfersToSpecifiedTaker) {
            context.castOfCharacters.fulfiller =
                context.castOfCharacters.adapter;
        }

        try config.getPayload_BuyOfferedERC721WithEther(
            context, desiredItem, price
        ) returns (OrderPayload memory payload) {
            context.castOfCharacters.fulfiller = originalFulfiller;

            sidecarItemTransfers = new ItemTransfer[](1);
            sidecarItemTransfers[0] = _desiredItemToSidecarItemTransfer(
                desiredItem, context.castOfCharacters
            );

            if (transfersToSpecifiedTaker) {
                // Sudo lets you send the NFT straight to the adapter and
                // Seaport handles it from there.
                sidecarItemTransfers = new ItemTransfer[](0);
            }

            itemsToBeOfferedByAdapter = new OfferItem[](1);
            {
                itemsToBeOfferedByAdapter[0] =
                    _desiredItemToOfferItem(desiredItem);
            }

            itemsToBeProvidedToAdapter = new ConsiderationItem[](1);
            itemsToBeProvidedToAdapter[0] = ConsiderationItem({
                itemType: ItemType.NATIVE,
                token: address(0),
                identifierOrCriteria: 0,
                startAmount: price,
                endAmount: price,
                recipient: payable(address(0))
            });

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                context.castOfCharacters,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );

            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyOfferedERC721WithEther(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item721 memory desiredItem,
        uint256 price
    )
        public
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        try config.getPayload_BuyOfferedERC721WithEther(
            OrderContext(false, false, castOfCharacters), desiredItem, price
        ) returns (OrderPayload memory payload) {
            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyOfferedERC721WithEther_FulfillThroughAdapter(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item721 memory desiredItem,
        uint256 price
    )
        public
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: false,
            routeThroughAdapter: true,
            castOfCharacters: castOfCharacters
        });

        // TODO: Add a field to the cast of characters for the address that
        // should get set on the external order as the taker so that the cast of
        // characters doesn't get mangled.

        // Blur, LR, and X2Y2 require that the msg.sender is also the taker.
        bool requiresTakerIsSender = _isBlur(config) || _isBlurV2(config)
            || _isLooksRare(config) || _isLooksRareV2(config) || _isX2y2(config);

        address originalFulfiller = context.castOfCharacters.fulfiller;

        if (requiresTakerIsSender) {
            context.castOfCharacters.fulfiller =
                context.castOfCharacters.sidecar;
        }

        try config.getPayload_BuyOfferedERC721WithEther(
            context, desiredItem, price
        ) returns (OrderPayload memory payload) {
            context.castOfCharacters.fulfiller = originalFulfiller;

            itemsToBeOfferedByAdapter = new OfferItem[](1);
            {
                itemsToBeOfferedByAdapter[0] =
                    _desiredItemToOfferItem(desiredItem);
            }

            itemsToBeProvidedToAdapter = new ConsiderationItem[](1);
            itemsToBeProvidedToAdapter[0] = ConsiderationItem({
                itemType: ItemType.NATIVE,
                token: address(0),
                identifierOrCriteria: 0,
                startAmount: price,
                endAmount: price,
                recipient: payable(address(0))
            });

            sidecarItemTransfers = new ItemTransfer[](1);
            sidecarItemTransfers[0] = _desiredItemToSidecarItemTransfer(
                desiredItem, context.castOfCharacters
            );

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                context.castOfCharacters,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );

            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyOfferedERC1155WithEther_ListOnChain(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item1155 memory desiredItem,
        uint256 price
    )
        public
        view
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: true,
            routeThroughAdapter: false,
            castOfCharacters: castOfCharacters
        });

        try config.getPayload_BuyOfferedERC1155WithEther(
            context, desiredItem, price
        ) returns (OrderPayload memory payload) {
            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyOfferedERC1155WithEther_ListOnChain_FulfillThroughAdapter(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item1155 memory desiredItem,
        uint256 price
    )
        public
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: true,
            routeThroughAdapter: true,
            castOfCharacters: castOfCharacters
        });

        try config.getPayload_BuyOfferedERC1155WithEther(
            context, desiredItem, price
        ) returns (OrderPayload memory payload) {
            itemsToBeOfferedByAdapter = new OfferItem[](1);
            itemsToBeOfferedByAdapter[0] = _desiredItemToOfferItem(desiredItem);

            itemsToBeProvidedToAdapter = new ConsiderationItem[](1);
            itemsToBeProvidedToAdapter[0] = ConsiderationItem({
                itemType: ItemType.NATIVE,
                token: address(0),
                identifierOrCriteria: 0,
                startAmount: price,
                endAmount: price,
                recipient: payable(address(0))
            });

            sidecarItemTransfers = new ItemTransfer[](1);
            sidecarItemTransfers[0] = ItemTransfer({
                from: context.castOfCharacters.sidecar,
                to: context.castOfCharacters.adapter,
                token: desiredItem.token,
                identifier: desiredItem.identifier,
                amount: desiredItem.amount,
                itemType: ItemType.ERC1155
            });

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                context.castOfCharacters,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );

            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyOfferedERC1155WithEther(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item1155 memory desiredItem,
        uint256 price
    )
        public
        view
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        try config.getPayload_BuyOfferedERC1155WithEther(
            OrderContext(false, false, castOfCharacters), desiredItem, price
        ) returns (OrderPayload memory payload) {
            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyOfferedERC1155WithEther_FulfillThroughAdapter(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item1155 memory desiredItem,
        uint256 price
    )
        public
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: false,
            routeThroughAdapter: true,
            castOfCharacters: castOfCharacters
        });

        // LR requires that the msg.sender is also the taker.
        bool requiresTakerIsSender =
            _isLooksRare(config) || _isLooksRareV2(config) || _isBlurV2(config);

        address originalFulfiller = context.castOfCharacters.fulfiller;

        if (requiresTakerIsSender) {
            context.castOfCharacters.fulfiller =
                context.castOfCharacters.sidecar;
        }

        try config.getPayload_BuyOfferedERC1155WithEther(
            context, desiredItem, price
        ) returns (OrderPayload memory payload) {
            context.castOfCharacters.fulfiller = originalFulfiller;

            itemsToBeOfferedByAdapter = new OfferItem[](1);
            itemsToBeOfferedByAdapter[0] = _desiredItemToOfferItem(desiredItem);

            itemsToBeProvidedToAdapter = new ConsiderationItem[](1);
            itemsToBeProvidedToAdapter[0] = ConsiderationItem({
                itemType: ItemType.NATIVE,
                token: address(0),
                identifierOrCriteria: 0,
                startAmount: price,
                endAmount: price,
                recipient: payable(address(0))
            });

            sidecarItemTransfers = new ItemTransfer[](1);
            sidecarItemTransfers[0] = ItemTransfer({
                from: context.castOfCharacters.sidecar,
                to: context.castOfCharacters.adapter,
                token: desiredItem.token,
                identifier: desiredItem.identifier,
                amount: desiredItem.amount,
                itemType: ItemType.ERC1155
            });

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                context.castOfCharacters,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );

            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyOfferedERC721WithERC20_ListOnChain(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item721 memory desiredItem,
        Item20 memory payment
    )
        public
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        try config.getPayload_BuyOfferedERC721WithERC20(
            OrderContext(true, false, castOfCharacters), desiredItem, payment
        ) returns (OrderPayload memory payload) {
            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyOfferedERC721WithERC20_ListOnChain_FulfillThroughAdapter(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item721 memory desiredItem,
        Item20 memory payment
    )
        public
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: true,
            routeThroughAdapter: true,
            castOfCharacters: castOfCharacters
        });

        address originalFulfiller = context.castOfCharacters.fulfiller;

        bool requiresTakerIsSender =
            _isLooksRare(config) || _isLooksRareV2(config);

        // LooksRare requires that the msg.sender is also the taker. So this
        // changes the fulfiller on the context, which changes the taker on the
        // orders created, which allows the sidecar to fulfill the order, and
        // then below the sidecar transfers the NFTs to the adapter, so that
        // Seaport can yoink them out and enforce that the caller gets what the
        // caller expects.

        if (requiresTakerIsSender) {
            context.castOfCharacters.fulfiller =
                context.castOfCharacters.sidecar;
        }

        bool transfersToSpecifiedTaker = _isSudo(config);

        // This causes the adapter to be set as the token recipient, so no
        // transfers from the sidecar are necessary.
        if (transfersToSpecifiedTaker) {
            context.castOfCharacters.fulfiller =
                context.castOfCharacters.adapter;
        }

        try config.getPayload_BuyOfferedERC721WithERC20(
            context, desiredItem, payment
        ) returns (OrderPayload memory payload) {
            context.castOfCharacters.fulfiller = originalFulfiller;

            itemsToBeOfferedByAdapter = new OfferItem[](1);
            {
                itemsToBeOfferedByAdapter[0] =
                    _desiredItemToOfferItem(desiredItem);
            }

            itemsToBeProvidedToAdapter = new ConsiderationItem[](1);
            itemsToBeProvidedToAdapter[0] = _paymentToConsiderationItem(payment);

            sidecarItemTransfers = new ItemTransfer[](1);
            sidecarItemTransfers[0] = _desiredItemToSidecarItemTransfer(
                desiredItem, context.castOfCharacters
            );

            if (transfersToSpecifiedTaker) {
                // Sudo lets you send the NFT straight to the adapter and
                // Seaport handles it from there.
                sidecarItemTransfers = new ItemTransfer[](0);
            }

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                context.castOfCharacters,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );

            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyOfferedERC721WithERC20(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item721 memory desiredItem,
        Item20 memory payment
    )
        public
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: false,
            routeThroughAdapter: false,
            castOfCharacters: castOfCharacters
        });

        try config.getPayload_BuyOfferedERC721WithERC20(
            context, desiredItem, payment
        ) returns (OrderPayload memory payload) {
            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyOfferedERC721WithERC20_FulfillThroughAdapter(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item721 memory desiredItem,
        Item20 memory payment
    )
        public
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: false,
            routeThroughAdapter: true,
            castOfCharacters: castOfCharacters
        });

        bool requiresTakerIsSender =
            _isLooksRare(config) || _isLooksRareV2(config) || _isX2y2(config);

        address originalFulfiller = context.castOfCharacters.fulfiller;

        if (requiresTakerIsSender) {
            context.castOfCharacters.fulfiller =
                context.castOfCharacters.sidecar;
        }

        try config.getPayload_BuyOfferedERC721WithERC20(
            context, desiredItem, payment
        ) returns (OrderPayload memory payload) {
            // Put the context back.
            context.castOfCharacters.fulfiller = originalFulfiller;

            itemsToBeOfferedByAdapter = new OfferItem[](1);
            {
                itemsToBeOfferedByAdapter[0] =
                    _desiredItemToOfferItem(desiredItem);
            }

            itemsToBeProvidedToAdapter = new ConsiderationItem[](1);
            itemsToBeProvidedToAdapter[0] = _paymentToConsiderationItem(payment);

            sidecarItemTransfers = new ItemTransfer[](1);
            sidecarItemTransfers[0] = _desiredItemToSidecarItemTransfer(
                desiredItem, context.castOfCharacters
            );

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                context.castOfCharacters,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );

            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyOfferedERC721WithWETH_ListOnChain(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item721 memory desiredItem,
        Item20 memory payment
    )
        public
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: true,
            routeThroughAdapter: false,
            castOfCharacters: castOfCharacters
        });

        try config.getPayload_BuyOfferedERC721WithERC20(
            context, desiredItem, payment
        ) returns (OrderPayload memory payload) {
            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyOfferedERC721WithWETH_FulfillThroughAdapter(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item721 memory desiredItem,
        Item20 memory payment
    )
        public
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: false,
            routeThroughAdapter: true,
            castOfCharacters: castOfCharacters
        });

        bool requiresTakerIsSender = _isBlur(config) || _isLooksRare(config)
            || _isLooksRareV2(config) || _isX2y2(config);

        address originalFulfiller = context.castOfCharacters.fulfiller;

        if (requiresTakerIsSender) {
            context.castOfCharacters.fulfiller =
                context.castOfCharacters.sidecar;
        }

        try config.getPayload_BuyOfferedERC721WithWETH(
            context, desiredItem, payment
        ) returns (OrderPayload memory payload) {
            // Put the context back.
            context.castOfCharacters.fulfiller = originalFulfiller;

            itemsToBeOfferedByAdapter = new OfferItem[](1);
            {
                itemsToBeOfferedByAdapter[0] =
                    _desiredItemToOfferItem(desiredItem);
            }

            itemsToBeProvidedToAdapter = new ConsiderationItem[](1);
            itemsToBeProvidedToAdapter[0] = _paymentToConsiderationItem(payment);

            sidecarItemTransfers = new ItemTransfer[](1);
            sidecarItemTransfers[0] = _desiredItemToSidecarItemTransfer(
                desiredItem, context.castOfCharacters
            );

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                context.castOfCharacters,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );

            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyOfferedERC721WithBETH(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item721 memory desiredItem,
        Item20 memory payment
    )
        public
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: false,
            routeThroughAdapter: false,
            castOfCharacters: castOfCharacters
        });

        try config.getPayload_BuyOfferedERC721WithBETH(
            context, desiredItem, payment
        ) returns (OrderPayload memory payload) {
            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    // // TODO: Come back and handle the stack pressure issue here.
    // // Breadcrumb. Might have to come back and sort this out.
    // function getPayloadToBuyOfferedERC721WithBETH_FulfillThroughAdapter(
    //     BaseMarketConfig config,
    //     CastOfCharacters memory castOfCharacters,
    //     Item721 memory desiredItem,
    //     uint256 price
    // )
    //     public
    //     returns (
    //         OrderPayload memory _payload,
    //         OfferItem[] memory itemsToBeOfferedByAdapter,
    //         ConsiderationItem[] memory itemsToBeProvidedToAdapter,
    //         ItemTransfer[] memory sidecarItemTransfers
    //     )
    // {
    //     // Bob doesn't deposit BETH for this, he sends native tokens, gets a
    //     // flashloan, which goes from adapter to sidecar to BETH's deposit
    //     // function, and then the sidecar uses the BETH to fulfill the
    // listing.

    //     OrderContext memory context = OrderContext({
    //         listOnChain: false,
    //         routeThroughAdapter: true,
    //         castOfCharacters: castOfCharacters
    //     });

    //     bool requiresTakerIsSender = _isBlur(config) || _isBlurV2(config);

    //     address originalFulfiller = context.castOfCharacters.fulfiller;

    //     if (requiresTakerIsSender) {
    //         context.castOfCharacters.fulfiller =
    //             context.castOfCharacters.sidecar;
    //     }

    //     // TODO: Come back and check to make sure this is OK.
    //     try config.getPayload_BuyOfferedERC721WithBETH(
    //         context, desiredItem, Item20(address(beth), price)
    //     ) returns (OrderPayload memory payload) {
    //         {
    //             context.castOfCharacters.fulfiller = originalFulfiller;
    //         }

    //         Flashloan[] memory flashloans = new Flashloan[](1);
    //         {
    //             Flashloan memory flashloan = Flashloan({
    //                 amount: uint88(price),
    //                 itemType: ItemType.NATIVE,
    //                 token: address(0),
    //                 shouldCallback: true,
    //                 recipient: context.castOfCharacters.adapter
    //             });
    //             flashloans[0] = flashloan;
    //         }

    //         Call[] memory sidecarSetUpCalls = new Call[](1);
    //         {
    //             Call memory call = Call({
    //                 target: address(beth),
    //                 allowFailure: false,
    //                 value: price,
    //                 callData: abi.encodeWithSelector(beth.deposit.selector)
    //             });
    //             sidecarSetUpCalls[0] = call;
    //         }

    //         Call[] memory sidecarMarketplaceCalls;
    //         {
    //             sidecarMarketplaceCalls = new Call[](1);
    //             sidecarMarketplaceCalls[0] = payload.executeOrder;
    //         }

    //         itemsToBeOfferedByAdapter = new
    // OfferItem[](1);
    //         {
    //             itemsToBeOfferedByAdapter[0] =
    //                 _desiredItemToOfferItem(desiredItem);
    //         }

    //         itemsToBeProvidedToAdapter =
    //             new ConsiderationItem[](1);
    //         {
    //             itemsToBeProvidedToAdapter[0] = ConsiderationItem({
    //                 itemType: ItemType.NATIVE,
    //                 token: address(0),
    //                 identifierOrCriteria: 0,
    //                 startAmount: price,
    //                 endAmount: price,
    //                 recipient: payable(address(0))
    //             });
    //         }

    //         sidecarItemTransfers = new
    // ItemTransfer[](1);
    //         {
    //             sidecarItemTransfers[0] =
    //                 _desiredItemToSidecarItemTransfer(desiredItem, context);
    //         }

    //         payload.executeOrder = AdapterHelperLib
    //             .createSeaportWrappedCallParameters(
    //             sidecarMarketplaceCalls,
    //             sidecarSetUpCalls,
    //             new Call[](0), // No wrap up calls necessary.
    //             context.castOfCharacters,
    //             flashloans,
    //             itemsToBeOfferedByAdapter,
    //             itemsToBeProvidedToAdapter,
    //             sidecarItemTransfers
    //         );

    //         payload.executeOrder.value = price;

    //         return (
    //             payload,
    //             itemsToBeOfferedByAdapter,
    //             itemsToBeProvidedToAdapter,
    //             sidecarItemTransfers
    //         );
    //     } catch {
    //         _revertNotSupported();
    //     }
    // }

    function getPayloadToBuyOfferedERC721WithWETH_ListOnChain_FulfillThroughAdapter(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item721 memory desiredItem,
        Item20 memory payment
    )
        public
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: true,
            routeThroughAdapter: true,
            castOfCharacters: castOfCharacters
        });

        bool requiresTakerIsSender =
            _isBlur(config) || _isLooksRare(config) || _isX2y2(config);

        address originalFulfiller = context.castOfCharacters.fulfiller;

        if (requiresTakerIsSender) {
            context.castOfCharacters.fulfiller =
                context.castOfCharacters.sidecar;
        }

        try config.getPayload_BuyOfferedERC721WithERC20(
            context, desiredItem, payment
        ) returns (OrderPayload memory payload) {
            context.castOfCharacters.fulfiller = originalFulfiller;

            itemsToBeOfferedByAdapter = new OfferItem[](1);
            {
                itemsToBeOfferedByAdapter[0] =
                    _desiredItemToOfferItem(desiredItem);
            }

            itemsToBeProvidedToAdapter = new ConsiderationItem[](1);
            itemsToBeProvidedToAdapter[0] = _paymentToConsiderationItem(payment);

            sidecarItemTransfers = new ItemTransfer[](1);
            sidecarItemTransfers[0] = _desiredItemToSidecarItemTransfer(
                desiredItem, context.castOfCharacters
            );

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                context.castOfCharacters,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );

            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyOfferedERC721WithWETH(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item721 memory desiredItem,
        Item20 memory payment
    )
        public
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: false,
            routeThroughAdapter: false,
            castOfCharacters: castOfCharacters
        });

        try config.getPayload_BuyOfferedERC721WithWETH(
            context, desiredItem, payment
        ) returns (OrderPayload memory payload) {
            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyOfferedERC1155WithERC20_ListOnChain(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item1155 memory desiredItem,
        Item20 memory payment
    )
        public
        view
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: true,
            routeThroughAdapter: false,
            castOfCharacters: castOfCharacters
        });

        try config.getPayload_BuyOfferedERC1155WithERC20(
            context, desiredItem, payment
        ) returns (OrderPayload memory payload) {
            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyOfferedERC1155WithERC20_ListOnChain_FulfillThroughAdapter(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item1155 memory desiredItem,
        Item20 memory payment
    )
        public
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: true,
            routeThroughAdapter: true,
            castOfCharacters: castOfCharacters
        });

        try config.getPayload_BuyOfferedERC1155WithERC20(
            context, desiredItem, payment
        ) returns (OrderPayload memory payload) {
            itemsToBeOfferedByAdapter = new OfferItem[](1);
            itemsToBeOfferedByAdapter[0] = _desiredItemToOfferItem(desiredItem);

            itemsToBeProvidedToAdapter = new ConsiderationItem[](1);
            itemsToBeProvidedToAdapter[0] = _paymentToConsiderationItem(payment);

            sidecarItemTransfers = new ItemTransfer[](1);
            sidecarItemTransfers[0] = ItemTransfer({
                from: context.castOfCharacters.sidecar,
                to: context.castOfCharacters.adapter,
                token: desiredItem.token,
                identifier: desiredItem.identifier,
                amount: desiredItem.amount,
                itemType: ItemType.ERC1155
            });

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                context.castOfCharacters,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );

            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyOfferedERC1155WithERC20(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item1155 memory desiredItem,
        Item20 memory payment
    )
        public
        view
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: false,
            routeThroughAdapter: false,
            castOfCharacters: castOfCharacters
        });

        try config.getPayload_BuyOfferedERC1155WithERC20(
            context, desiredItem, payment
        ) returns (OrderPayload memory payload) {
            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyOfferedERC1155WithERC20_FulfillThroughAdapter(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item1155 memory desiredItem,
        Item20 memory payment
    )
        public
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: false,
            routeThroughAdapter: true,
            castOfCharacters: castOfCharacters
        });

        bool requiresTakerIsSender =
            _isLooksRare(config) || _isLooksRareV2(config);

        address originalFulfiller = context.castOfCharacters.fulfiller;

        if (requiresTakerIsSender) {
            context.castOfCharacters.fulfiller =
                context.castOfCharacters.sidecar;
        }

        try config.getPayload_BuyOfferedERC1155WithERC20(
            context, desiredItem, payment
        ) returns (OrderPayload memory payload) {
            // Put the context back.
            context.castOfCharacters.fulfiller = originalFulfiller;

            itemsToBeOfferedByAdapter = new OfferItem[](1);
            itemsToBeOfferedByAdapter[0] = _desiredItemToOfferItem(desiredItem);

            itemsToBeProvidedToAdapter = new ConsiderationItem[](1);
            itemsToBeProvidedToAdapter[0] = _paymentToConsiderationItem(payment);

            sidecarItemTransfers = new ItemTransfer[](1);
            sidecarItemTransfers[0] = ItemTransfer({
                from: context.castOfCharacters.sidecar,
                to: context.castOfCharacters.adapter,
                token: desiredItem.token,
                identifier: desiredItem.identifier,
                amount: desiredItem.amount,
                itemType: ItemType.ERC1155
            });

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                context.castOfCharacters,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );

            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyOfferedERC20WithERC721_ListOnChain(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item20 memory desiredPayment,
        Item721 memory offeredItem
    )
        public
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: true,
            routeThroughAdapter: false,
            castOfCharacters: castOfCharacters
        });

        try config.getPayload_BuyOfferedERC20WithERC721(
            context, desiredPayment, offeredItem
        ) returns (OrderPayload memory payload) {
            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyOfferedERC20WithERC721_ListOnChain_FulfillThroughAdapter(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item20 memory desiredPayment,
        Item721 memory offeredItem
    )
        public
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: true,
            routeThroughAdapter: true,
            castOfCharacters: castOfCharacters
        });

        // Turns out X2Y2 doesn't support this, but if it did, it would need
        // this.
        bool requiresTakerIsSender = _isX2y2(config);

        // X2Y2 requires that the taker is the msg.sender.
        address originalFulfiller = context.castOfCharacters.fulfiller;

        if (requiresTakerIsSender) {
            context.castOfCharacters.fulfiller =
                context.castOfCharacters.sidecar;
        }

        bool transfersToSpecifiedTaker = _isSudo(config);

        if (transfersToSpecifiedTaker) {
            context.castOfCharacters.fulfiller =
                context.castOfCharacters.adapter;
        }

        try config.getPayload_BuyOfferedERC20WithERC721(
            context, desiredPayment, offeredItem
        ) returns (OrderPayload memory payload) {
            context.castOfCharacters.fulfiller = originalFulfiller;

            itemsToBeOfferedByAdapter = new OfferItem[](1);
            itemsToBeOfferedByAdapter[0] =
                _desiredPaymentToOfferItem(desiredPayment);

            itemsToBeProvidedToAdapter = new ConsiderationItem[](1);

            itemsToBeProvidedToAdapter[0] = ConsiderationItem({
                itemType: ItemType.ERC721,
                token: offeredItem.token,
                identifierOrCriteria: offeredItem.identifier,
                startAmount: 1,
                endAmount: 1,
                recipient: payable(address(0))
            });

            sidecarItemTransfers = new ItemTransfer[](1);
            sidecarItemTransfers[0] = ItemTransfer({
                from: context.castOfCharacters.sidecar,
                to: context.castOfCharacters.adapter,
                token: desiredPayment.token,
                identifier: 0,
                amount: desiredPayment.amount,
                itemType: ItemType.ERC20
            });

            if (transfersToSpecifiedTaker) {
                sidecarItemTransfers = new ItemTransfer[](0);
            }

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                context.castOfCharacters,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );

            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyOfferedERC20WithERC721(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item20 memory desiredPayment,
        Item721 memory offeredItem
    )
        public
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: false,
            routeThroughAdapter: false,
            castOfCharacters: castOfCharacters
        });
        try config.getPayload_BuyOfferedERC20WithERC721(
            context, desiredPayment, offeredItem
        ) returns (OrderPayload memory payload) {
            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyOfferedERC20WithERC721_FulfillThroughAdapter(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item20 memory desiredPayment,
        Item721 memory offeredItem
    )
        public
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: false,
            routeThroughAdapter: true,
            castOfCharacters: castOfCharacters
        });

        bool requiresTakerIsSender =
            _isLooksRare(config) || _isLooksRareV2(config) || _isX2y2(config);

        address originalFulfiller = context.castOfCharacters.fulfiller;

        if (requiresTakerIsSender) {
            context.castOfCharacters.fulfiller =
                context.castOfCharacters.sidecar;
        }

        try config.getPayload_BuyOfferedERC20WithERC721(
            context, desiredPayment, offeredItem
        ) returns (OrderPayload memory payload) {
            // Put the context back.
            context.castOfCharacters.fulfiller = originalFulfiller;

            itemsToBeOfferedByAdapter = new OfferItem[](1);
            itemsToBeOfferedByAdapter[0] =
                _desiredPaymentToOfferItem(desiredPayment);

            itemsToBeProvidedToAdapter = new ConsiderationItem[](1);

            itemsToBeProvidedToAdapter[0] = ConsiderationItem({
                itemType: ItemType.ERC721,
                token: offeredItem.token,
                identifierOrCriteria: offeredItem.identifier,
                startAmount: 1,
                endAmount: 1,
                recipient: payable(address(0))
            });

            sidecarItemTransfers = new ItemTransfer[](1);
            sidecarItemTransfers[0] = ItemTransfer({
                from: context.castOfCharacters.sidecar,
                to: context.castOfCharacters.adapter,
                token: desiredPayment.token,
                identifier: 0,
                amount: desiredPayment.amount,
                itemType: ItemType.ERC20
            });

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                context.castOfCharacters,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );

            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyOfferedWETHWithERC721_ListOnChain(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item20 memory desiredPayment,
        Item721 memory offeredItem
    )
        public
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: true,
            routeThroughAdapter: false,
            castOfCharacters: castOfCharacters
        });

        try config.getPayload_BuyOfferedWETHWithERC721(
            context, desiredPayment, offeredItem
        ) returns (OrderPayload memory payload) {
            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyOfferedWETHWithERC721_ListOnChain_FulfillThroughAdapter(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item20 memory desiredPayment,
        Item721 memory offeredItem
    )
        public
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: true,
            routeThroughAdapter: true,
            castOfCharacters: castOfCharacters
        });

        try config.getPayload_BuyOfferedWETHWithERC721(
            context, desiredPayment, offeredItem
        ) returns (OrderPayload memory payload) {
            itemsToBeOfferedByAdapter = new OfferItem[](1);
            itemsToBeOfferedByAdapter[0] =
                _desiredPaymentToOfferItem(desiredPayment);

            itemsToBeProvidedToAdapter = new ConsiderationItem[](1);

            itemsToBeProvidedToAdapter[0] = ConsiderationItem({
                itemType: ItemType.ERC721,
                token: offeredItem.token,
                identifierOrCriteria: offeredItem.identifier,
                startAmount: 1,
                endAmount: 1,
                recipient: payable(address(0))
            });

            sidecarItemTransfers = new ItemTransfer[](1);
            sidecarItemTransfers[0] = ItemTransfer({
                from: context.castOfCharacters.sidecar,
                to: context.castOfCharacters.adapter,
                token: desiredPayment.token,
                identifier: 0,
                amount: desiredPayment.amount,
                itemType: ItemType.ERC20
            });

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                context.castOfCharacters,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );

            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyOfferedWETHWithERC721(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item20 memory desiredPayment,
        Item721 memory offeredItem
    )
        public
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: false,
            routeThroughAdapter: false,
            castOfCharacters: castOfCharacters
        });
        try config.getPayload_BuyOfferedWETHWithERC721(
            context, desiredPayment, offeredItem
        ) returns (OrderPayload memory payload) {
            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyOfferedWETHWithERC721_FulfillThroughAdapter(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item20 memory desiredPayment,
        Item721 memory offeredItem
    )
        public
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: false,
            routeThroughAdapter: true,
            castOfCharacters: castOfCharacters
        });

        bool requiresTakerIsSender = _isBlur(config) || _isLooksRare(config)
            || _isLooksRareV2(config) || _isX2y2(config);

        address originalFulfiller = context.castOfCharacters.fulfiller;

        if (requiresTakerIsSender) {
            context.castOfCharacters.fulfiller =
                context.castOfCharacters.sidecar;
        }

        try config.getPayload_BuyOfferedWETHWithERC721(
            context, desiredPayment, offeredItem
        ) returns (OrderPayload memory payload) {
            context.castOfCharacters.fulfiller = originalFulfiller;

            itemsToBeOfferedByAdapter = new OfferItem[](1);
            itemsToBeOfferedByAdapter[0] =
                _desiredPaymentToOfferItem(desiredPayment);

            itemsToBeProvidedToAdapter = new ConsiderationItem[](1);

            itemsToBeProvidedToAdapter[0] = ConsiderationItem({
                itemType: ItemType.ERC721,
                token: offeredItem.token,
                identifierOrCriteria: offeredItem.identifier,
                startAmount: 1,
                endAmount: 1,
                recipient: payable(address(0))
            });

            sidecarItemTransfers = new ItemTransfer[](1);
            sidecarItemTransfers[0] = ItemTransfer({
                from: context.castOfCharacters.sidecar,
                to: context.castOfCharacters.adapter,
                token: desiredPayment.token,
                identifier: 0,
                amount: desiredPayment.amount,
                itemType: ItemType.ERC20
            });

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                context.castOfCharacters,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );

            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyOfferedBETHWithERC721(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item20 memory desiredPayment,
        Item721 memory offeredItem
    )
        public
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: false,
            routeThroughAdapter: false,
            castOfCharacters: castOfCharacters
        });

        try config.getPayload_BuyOfferedBETHWithERC721(
            context, desiredPayment, offeredItem
        ) returns (OrderPayload memory payload) {
            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    // // TODO: Come back and handle the stack pressure issues here.
    // // Breadcrumb. Might have to come back and sort this out.
    // function getPayloadToBuyOfferedBETHWithERC721_FulfillThroughAdapter(
    //     BaseMarketConfig config,
    //     CastOfCharacters memory castOfCharacters,
    //     Item20 memory desiredPayment,
    //     Item721 memory offeredItem
    // )
    //     public
    //     returns (
    //         OrderPayload memory _payload,
    //         OfferItem[] memory itemsToBeOfferedByAdapter,
    //         ConsiderationItem[] memory itemsToBeProvidedToAdapter,
    //         ItemTransfer[] memory sidecarItemTransfers
    //     )
    // {
    //     OrderContext memory context = OrderContext({
    //         listOnChain: false,
    //         routeThroughAdapter: true,
    //         castOfCharacters: castOfCharacters
    //     });

    //     bool requiresTakerIsSender = _isBlurV2(config);

    //     address originalFulfiller = context.castOfCharacters.fulfiller;

    //     if (requiresTakerIsSender) {
    //         context.castOfCharacters.fulfiller =
    //             context.castOfCharacters.sidecar;
    //     }

    //     try config.getPayload_BuyOfferedBETHWithERC721(
    //         context, desiredPayment, offeredItem
    //     ) returns (OrderPayload memory payload) {
    //         context.castOfCharacters.fulfiller = originalFulfiller;

    //         // Sidecar's not going to transfer anything.
    //         sidecarItemTransfers = new
    // ItemTransfer[](0);

    //         itemsToBeOfferedByAdapter = new
    // OfferItem[](1);
    //         itemsToBeOfferedByAdapter[0] = OfferItem({
    //             itemType: ItemType.NATIVE,
    //             token: address(0),
    //             identifierOrCriteria: 0,
    //             startAmount: desiredPayment.amount,
    //             endAmount: desiredPayment.amount
    //         });

    //         itemsToBeProvidedToAdapter =
    //             new ConsiderationItem[](1);
    //         itemsToBeProvidedToAdapter[0] = ConsiderationItem({
    //             itemType: ItemType.ERC721,
    //             token: offeredItem.token,
    //             identifierOrCriteria: offeredItem.identifier,
    //             startAmount: 1,
    //             endAmount: 1,
    //             recipient: payable(address(0))
    //         });

    //         // This converts the BETH received by the sidecar into native
    // tokens
    //         // which should make their way to the fulfiller.
    //         Call[] memory sidecarWrapUpCalls = new Call[](2);
    //         Call memory bethCall = Call({
    //             target: address(beth),
    //             allowFailure: false,
    //             value: 0,
    //             callData: abi.encodeWithSelector(
    //                 beth.withdraw.selector, desiredPayment.amount
    //                 )
    //         });
    //         Call memory sendNativeTokensToSeaportCall = Call({
    //             target: address(seaport),
    //             allowFailure: false,
    //             value: desiredPayment.amount,
    //             callData: ""
    //         });
    //         sidecarWrapUpCalls[0] = bethCall;
    //         sidecarWrapUpCalls[1] = sendNativeTokensToSeaportCall;

    //         Call[] memory sidecarMarketplaceCalls;
    //         sidecarMarketplaceCalls = new Call[](1);
    //         sidecarMarketplaceCalls[0] = payload.executeOrder;

    //         payload.executeOrder = AdapterHelperLib
    //             .createSeaportWrappedCallParameters(
    //             sidecarMarketplaceCalls,
    //             new Call[](0),
    //             sidecarWrapUpCalls,
    //             context.castOfCharacters,
    //             new Flashloan[](0),
    //             itemsToBeOfferedByAdapter,
    //             itemsToBeProvidedToAdapter,
    //             sidecarItemTransfers
    //         );

    //         return (
    //             payload,
    //             itemsToBeOfferedByAdapter,
    //             itemsToBeProvidedToAdapter,
    //             sidecarItemTransfers
    //         );
    //     } catch {
    //         _revertNotSupported();
    //     }
    // }

    function getPayloadToBuyOfferedERC20WithERC1155_ListOnChain(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item20 memory desiredPayment,
        Item1155 memory offeredItem
    )
        public
        view
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: true,
            routeThroughAdapter: false,
            castOfCharacters: castOfCharacters
        });
        try config.getPayload_BuyOfferedERC20WithERC1155(
            context, desiredPayment, offeredItem
        ) returns (OrderPayload memory payload) {
            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyOfferedERC20WithERC1155_ListOnChain_FulfillThroughAdapter(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item20 memory desiredPayment,
        Item1155 memory offeredItem
    )
        public
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: true,
            routeThroughAdapter: true,
            castOfCharacters: castOfCharacters
        });
        try config.getPayload_BuyOfferedERC20WithERC1155(
            context, desiredPayment, offeredItem
        ) returns (OrderPayload memory payload) {
            itemsToBeOfferedByAdapter = new OfferItem[](1);
            itemsToBeOfferedByAdapter[0] =
                _desiredPaymentToOfferItem(desiredPayment);

            itemsToBeProvidedToAdapter = new ConsiderationItem[](1);
            itemsToBeProvidedToAdapter[0] = ConsiderationItem({
                itemType: ItemType.ERC1155,
                token: offeredItem.token,
                identifierOrCriteria: offeredItem.identifier,
                startAmount: offeredItem.amount,
                endAmount: offeredItem.amount,
                recipient: payable(address(0))
            });

            sidecarItemTransfers = new ItemTransfer[](1);
            sidecarItemTransfers[0] = ItemTransfer({
                from: context.castOfCharacters.sidecar,
                to: context.castOfCharacters.adapter,
                token: desiredPayment.token,
                identifier: 0,
                amount: desiredPayment.amount,
                itemType: ItemType.ERC20
            });

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                context.castOfCharacters,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );

            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyOfferedERC20WithERC1155(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item20 memory desiredPayment,
        Item1155 memory offeredItem
    )
        public
        view
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: false,
            routeThroughAdapter: false,
            castOfCharacters: castOfCharacters
        });
        try config.getPayload_BuyOfferedERC20WithERC1155(
            context, desiredPayment, offeredItem
        ) returns (OrderPayload memory payload) {
            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyOfferedERC20WithERC1155_FulfillThroughAdapter(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item20 memory desiredPayment,
        Item1155 memory offeredItem
    )
        public
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: false,
            routeThroughAdapter: true,
            castOfCharacters: castOfCharacters
        });

        bool requiresTakerIsSender =
            _isLooksRare(config) || _isLooksRareV2(config);

        // Cheat the context for LR.
        address originalFulfiller = context.castOfCharacters.fulfiller;

        if (requiresTakerIsSender) {
            context.castOfCharacters.fulfiller =
                context.castOfCharacters.sidecar;
        }

        try config.getPayload_BuyOfferedERC20WithERC1155(
            context, desiredPayment, offeredItem
        ) returns (OrderPayload memory payload) {
            // Put the context back.
            context.castOfCharacters.fulfiller = originalFulfiller;

            itemsToBeOfferedByAdapter = new OfferItem[](1);
            itemsToBeOfferedByAdapter[0] =
                _desiredPaymentToOfferItem(desiredPayment);

            itemsToBeProvidedToAdapter = new ConsiderationItem[](1);

            itemsToBeProvidedToAdapter[0] = ConsiderationItem({
                itemType: ItemType.ERC1155,
                token: offeredItem.token,
                identifierOrCriteria: offeredItem.identifier,
                startAmount: offeredItem.amount,
                endAmount: offeredItem.amount,
                recipient: payable(address(0))
            });

            sidecarItemTransfers = new ItemTransfer[](1);
            sidecarItemTransfers[0] = ItemTransfer({
                from: context.castOfCharacters.sidecar,
                to: context.castOfCharacters.adapter,
                token: desiredPayment.token,
                identifier: 0,
                amount: desiredPayment.amount,
                itemType: ItemType.ERC20
            });

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                context.castOfCharacters,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );

            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyOfferedERC721WithERC1155_ListOnChain(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item721 memory desiredItem,
        Item1155 memory offeredItem
    )
        public
        view
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: true,
            routeThroughAdapter: false,
            castOfCharacters: castOfCharacters
        });
        try config.getPayload_BuyOfferedERC721WithERC1155(
            context, desiredItem, offeredItem
        ) returns (OrderPayload memory payload) {
            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyOfferedERC721WithERC1155_ListOnChain_FulfillThroughAdapter(
        BaseMarketConfig, /* config */
        CastOfCharacters memory, /* castOfCharacters */
        Item721 memory, /* desiredItem */
        Item1155 memory /* offeredItem */
    ) public pure returns (OrderPayload memory /* _payload */ ) {
        // Only seaport, skip for now.
        _revertNotSupported();
    }

    function getPayloadToBuyOfferedERC721WithERC1155(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item721 memory desiredItem,
        Item1155 memory offeredItem
    )
        public
        view
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: false,
            routeThroughAdapter: false,
            castOfCharacters: castOfCharacters
        });
        try config.getPayload_BuyOfferedERC721WithERC1155(
            context, desiredItem, offeredItem
        ) returns (OrderPayload memory payload) {
            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyOfferedERC721WithERC1155_FulfillThroughAdapter(
        BaseMarketConfig, /* config */
        CastOfCharacters memory, /* castOfCharacters */
        Item721 memory, /* desiredItem */
        Item1155 memory /* offeredItem */
    ) public pure returns (OrderPayload memory /* _payload */ ) {
        // Only seaport, skip for now.
        _revertNotSupported();
    }

    function getPayloadToBuyOfferedERC1155WithERC721_ListOnChain(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item1155 memory desiredItem,
        Item721 memory offeredItem
    )
        public
        view
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: true,
            routeThroughAdapter: false,
            castOfCharacters: castOfCharacters
        });
        try config.getPayload_BuyOfferedERC1155WithERC721(
            context, desiredItem, offeredItem
        ) returns (OrderPayload memory payload) {
            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyOfferedERC1155WithERC721_ListOnChain_FulfillThroughAdapter(
        BaseMarketConfig, /* config */
        CastOfCharacters memory, /* castOfCharacters */
        Item1155 memory, /* desiredItem */
        Item721 memory /* offeredItem */
    ) public pure returns (OrderPayload memory /* _payload */ ) {
        // Only seaport so skipping here.
        _revertNotSupported();
    }

    function getPayloadToBuyOfferedERC1155WithERC721(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item1155 memory desiredItem,
        Item721 memory offeredItem
    )
        public
        view
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: false,
            routeThroughAdapter: false,
            castOfCharacters: castOfCharacters
        });
        try config.getPayload_BuyOfferedERC1155WithERC721(
            context, desiredItem, offeredItem
        ) returns (OrderPayload memory payload) {
            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyOfferedERC1155WithERC721_FulfillThroughAdapter(
        BaseMarketConfig, /* config */
        CastOfCharacters memory, /* castOfCharacters */
        Item1155 memory, /* desiredItem */
        Item721 memory /* offeredItem */
    ) public pure returns (OrderPayload memory /* _payload */ ) {
        // Only seaport so skipping here for now.
        _revertNotSupported();
    }

    // TODO: Make this a percentage, calculate it for the user, merge these into
    // a single FeeInfo struct.
    function getPayloadToBuyOfferedERC721WithEtherOneFeeRecipient_ListOnChain(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item721 memory desiredItem,
        uint256 price,
        Fee memory fee
    )
        public
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: true,
            routeThroughAdapter: false,
            castOfCharacters: castOfCharacters
        });

        try config.getPayload_BuyOfferedERC721WithEtherOneFeeRecipient(
            context,
            desiredItem,
            price, // increased so that the fee recipient recieves 1%
            fee.recipient,
            fee.amount
        ) returns (OrderPayload memory payload) {
            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyOfferedERC721WithEtherOneFeeRecipient_ListOnChain_FulfillThroughAdapter(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item721 memory desiredItem,
        uint256 price,
        Fee memory fee
    )
        public
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: true,
            routeThroughAdapter: true,
            castOfCharacters: castOfCharacters
        });

        try config.getPayload_BuyOfferedERC721WithEtherOneFeeRecipient(
            context, desiredItem, price, fee.recipient, fee.amount
        ) returns (OrderPayload memory payload) {
            itemsToBeOfferedByAdapter = new OfferItem[](1);
            {
                itemsToBeOfferedByAdapter[0] =
                    _desiredItemToOfferItem(desiredItem);
            }

            itemsToBeProvidedToAdapter = new ConsiderationItem[](
                1
            );
            itemsToBeProvidedToAdapter[0] = ConsiderationItem({
                itemType: ItemType.NATIVE,
                token: address(0),
                identifierOrCriteria: 0,
                startAmount: price + fee.amount,
                endAmount: price + fee.amount,
                recipient: payable(address(0))
            });

            // TODO: Maybe an ItemTransfer to ConsiderationItem conversion
            // function and an ItemTransfer to OfferItem conversion function.
            sidecarItemTransfers = new ItemTransfer[](1);
            sidecarItemTransfers[0] = _desiredItemToSidecarItemTransfer(
                desiredItem, context.castOfCharacters
            );

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                context.castOfCharacters,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );

            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyOfferedERC721WithEtherOneFeeRecipient(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item721 memory desiredItem,
        uint256 price,
        Fee memory fee
    )
        public
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: false,
            routeThroughAdapter: false,
            castOfCharacters: castOfCharacters
        });
        try config.getPayload_BuyOfferedERC721WithEtherOneFeeRecipient(
            context, desiredItem, price, fee.recipient, fee.amount
        ) returns (OrderPayload memory payload) {
            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyOfferedERC721WithEtherOneFeeRecipient_FulfillThroughAdapter(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item721 memory desiredItem,
        uint256 price,
        Fee memory fee
    )
        public
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: false,
            routeThroughAdapter: true,
            castOfCharacters: castOfCharacters
        });

        bool requiresTakerIsSender = _isX2y2(config);

        address originalFulfiller = context.castOfCharacters.fulfiller;

        if (requiresTakerIsSender) {
            context.castOfCharacters.fulfiller =
                context.castOfCharacters.sidecar;
        }

        try config.getPayload_BuyOfferedERC721WithEtherOneFeeRecipient(
            context, desiredItem, price, fee.recipient, 5
        ) returns (OrderPayload memory payload) {
            context.castOfCharacters.fulfiller = originalFulfiller;

            itemsToBeOfferedByAdapter = new OfferItem[](1);
            {
                itemsToBeOfferedByAdapter[0] =
                    _desiredItemToOfferItem(desiredItem);
            }

            itemsToBeProvidedToAdapter = new ConsiderationItem[](
                1
            );
            itemsToBeProvidedToAdapter[0] = ConsiderationItem({
                itemType: ItemType.NATIVE,
                token: address(0),
                identifierOrCriteria: 0,
                startAmount: price + fee.amount,
                endAmount: price + fee.amount,
                recipient: payable(address(0))
            });

            sidecarItemTransfers = new ItemTransfer[](1);
            sidecarItemTransfers[0] = _desiredItemToSidecarItemTransfer(
                desiredItem, context.castOfCharacters
            );

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                context.castOfCharacters,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );

            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyOfferedERC721WithEtherTwoFeeRecipients_ListOnChain(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item721 memory desiredItem,
        uint256 price,
        Fee memory feeOne,
        Fee memory feeTwo
    )
        public
        view
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: true,
            routeThroughAdapter: false,
            castOfCharacters: castOfCharacters
        });

        try config.getPayload_BuyOfferedERC721WithEtherTwoFeeRecipient(
            context,
            desiredItem,
            price,
            feeOne.recipient,
            feeOne.amount,
            feeTwo.recipient,
            feeTwo.amount
        ) returns (OrderPayload memory payload) {
            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyOfferedERC721WithEtherTwoFeeRecipients_ListOnChain_FulfillThroughAdapter(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item721 memory desiredItem,
        uint256 price,
        Fee memory feeOne,
        Fee memory feeTwo
    )
        public
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context;

        {
            context = OrderContext({
                listOnChain: true,
                routeThroughAdapter: true,
                castOfCharacters: castOfCharacters
            });
        }

        try config.getPayload_BuyOfferedERC721WithEtherTwoFeeRecipient(
            context,
            desiredItem,
            price,
            feeOne.recipient,
            feeOne.amount,
            feeTwo.recipient,
            feeTwo.amount
        ) returns (OrderPayload memory payload) {
            itemsToBeOfferedByAdapter = new OfferItem[](1);

            {
                itemsToBeOfferedByAdapter[0] =
                    _desiredItemToOfferItem(desiredItem);
            }

            itemsToBeProvidedToAdapter = new ConsiderationItem[](
                1
            );
            {
                uint256 totalAmount;
                {
                    totalAmount = price + feeOne.amount + feeTwo.amount;
                }
                itemsToBeProvidedToAdapter[0] = ConsiderationItem({
                    itemType: ItemType.NATIVE,
                    token: address(0),
                    identifierOrCriteria: 0,
                    startAmount: totalAmount,
                    endAmount: totalAmount,
                    recipient: payable(address(0))
                });
            }

            sidecarItemTransfers = new ItemTransfer[](1);
            {
                sidecarItemTransfers[0] = _desiredItemToSidecarItemTransfer(
                    desiredItem, context.castOfCharacters
                );
            }

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                context.castOfCharacters,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );

            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyOfferedERC721WithEtherTwoFeeRecipients(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item721 memory desiredItem,
        uint256 price,
        Fee memory feeOne,
        Fee memory feeTwo
    )
        public
        view
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: false,
            routeThroughAdapter: false,
            castOfCharacters: castOfCharacters
        });

        try config.getPayload_BuyOfferedERC721WithEtherTwoFeeRecipient(
            context,
            desiredItem,
            price,
            feeOne.recipient,
            feeOne.amount,
            feeTwo.recipient,
            feeTwo.amount
        ) returns (OrderPayload memory payload) {
            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyOfferedERC721WithEtherTwoFeeRecipients_FulfillThroughAdapter(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item721 memory desiredItem,
        uint256 price,
        Fee memory feeOne,
        Fee memory feeTwo
    )
        public
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: false,
            routeThroughAdapter: true,
            castOfCharacters: castOfCharacters
        });

        address requiresTakerIsSender =
            _isX2y2(config) ? context.castOfCharacters.fulfiller : address(0);

        if (requiresTakerIsSender != address(0)) {
            context.castOfCharacters.fulfiller =
                context.castOfCharacters.sidecar;
        }

        try config.getPayload_BuyOfferedERC721WithEtherTwoFeeRecipient(
            context,
            desiredItem,
            price,
            feeOne.recipient,
            feeOne.amount,
            feeTwo.recipient,
            feeTwo.amount
        ) returns (OrderPayload memory payload) {
            {
                context.castOfCharacters.fulfiller = requiresTakerIsSender
                    != address(0)
                    ? requiresTakerIsSender
                    : context.castOfCharacters.fulfiller;
            }

            itemsToBeOfferedByAdapter = new OfferItem[](1);

            {
                itemsToBeOfferedByAdapter[0] =
                    _desiredItemToOfferItem(desiredItem);
            }

            itemsToBeProvidedToAdapter = new ConsiderationItem[](
                1
            );
            {
                itemsToBeProvidedToAdapter[0] = ConsiderationItem({
                    itemType: ItemType.NATIVE,
                    token: address(0),
                    identifierOrCriteria: 0,
                    startAmount: price + feeOne.amount + feeTwo.amount,
                    endAmount: price + feeOne.amount + feeTwo.amount,
                    recipient: payable(address(0))
                });
            }

            sidecarItemTransfers = new ItemTransfer[](1);
            {
                sidecarItemTransfers[0] = _desiredItemToSidecarItemTransfer(
                    desiredItem, context.castOfCharacters
                );
            }

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                context.castOfCharacters,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );

            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyManyOfferedERC721WithEther_ListOnChain(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item721[] memory desiredItems,
        uint256 price
    )
        public
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: true,
            routeThroughAdapter: false,
            castOfCharacters: castOfCharacters
        });

        try config.getPayload_BuyManyOfferedERC721WithEther(
            context, desiredItems, price
        ) returns (OrderPayload memory payload) {
            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyManyOfferedERC721WithEther_ListOnChain_FulfillThroughAdapter(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item721[] memory desiredItems,
        uint256 price
    )
        public
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: true,
            routeThroughAdapter: true,
            castOfCharacters: castOfCharacters
        });

        address originalFulfiller = context.castOfCharacters.fulfiller;

        bool transfersToSpecifiedTaker = _isSudo(config);

        if (transfersToSpecifiedTaker) {
            context.castOfCharacters.fulfiller =
                context.castOfCharacters.adapter;
        }

        try config.getPayload_BuyManyOfferedERC721WithEther(
            context, desiredItems, price
        ) returns (OrderPayload memory payload) {
            context.castOfCharacters.fulfiller = originalFulfiller;

            itemsToBeOfferedByAdapter = new OfferItem[](desiredItems.length);

            sidecarItemTransfers = new ItemTransfer[](desiredItems.length);
            for (uint256 i; i < desiredItems.length; i++) {
                sidecarItemTransfers[i] = ItemTransfer({
                    from: context.castOfCharacters.sidecar,
                    to: context.castOfCharacters.adapter,
                    token: desiredItems[i].token,
                    identifier: desiredItems[i].identifier,
                    amount: 1,
                    itemType: ItemType.ERC721
                });

                itemsToBeOfferedByAdapter[i] =
                    _desiredItemToOfferItem(desiredItems[i]);
            }

            itemsToBeProvidedToAdapter = new ConsiderationItem[](
                1
            );

            itemsToBeProvidedToAdapter[0] = ConsiderationItem({
                itemType: ItemType.NATIVE,
                token: address(0),
                identifierOrCriteria: 0,
                startAmount: price,
                endAmount: price,
                recipient: payable(address(0))
            });

            if (transfersToSpecifiedTaker) {
                sidecarItemTransfers = new ItemTransfer[](0);
            }

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                context.castOfCharacters,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );

            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyManyOfferedERC721WithEther(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item721[] memory desiredItems,
        uint256 price
    )
        public
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: false,
            routeThroughAdapter: false,
            castOfCharacters: castOfCharacters
        });

        try config.getPayload_BuyManyOfferedERC721WithEther(
            context, desiredItems, price
        ) returns (OrderPayload memory payload) {
            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyManyOfferedERC721WithEther_FulfillThroughAdapter(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item721[] memory desiredItems,
        uint256 price
    )
        public
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext memory context = OrderContext({
            listOnChain: false,
            routeThroughAdapter: true,
            castOfCharacters: castOfCharacters
        });

        bool requiresTakerIsSender =
            _isBlurV2(config) || _isX2y2(config) || _isLooksRareV2(config);

        address originalFulfiller = context.castOfCharacters.fulfiller;

        if (requiresTakerIsSender) {
            context.castOfCharacters.fulfiller =
                context.castOfCharacters.sidecar;
        }

        try config.getPayload_BuyManyOfferedERC721WithEther(
            context, desiredItems, price
        ) returns (OrderPayload memory payload) {
            context.castOfCharacters.fulfiller = originalFulfiller;

            itemsToBeOfferedByAdapter = new OfferItem[](desiredItems.length);

            sidecarItemTransfers = new ItemTransfer[](desiredItems.length);
            for (uint256 i; i < desiredItems.length; i++) {
                sidecarItemTransfers[i] = ItemTransfer({
                    from: context.castOfCharacters.sidecar,
                    to: context.castOfCharacters.adapter,
                    token: desiredItems[i].token,
                    identifier: desiredItems[i].identifier,
                    amount: 1,
                    itemType: ItemType.ERC721
                });

                itemsToBeOfferedByAdapter[i] =
                    _desiredItemToOfferItem(desiredItems[i]);
            }

            itemsToBeProvidedToAdapter = new ConsiderationItem[](
                1
            );

            itemsToBeProvidedToAdapter[0] = ConsiderationItem({
                itemType: ItemType.NATIVE,
                token: address(0),
                identifierOrCriteria: 0,
                startAmount: price,
                endAmount: price,
                recipient: payable(address(0))
            });

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                context.castOfCharacters,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );

            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyManyOfferedERC721WithEtherDistinctOrders(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item721[] memory desiredItems,
        uint256[] memory prices
    )
        public
        view
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext[] memory contexts = new OrderContext[](desiredItems.length);

        for (uint256 i = 0; i < desiredItems.length; i++) {
            contexts[i] = OrderContext({
                listOnChain: false,
                routeThroughAdapter: false,
                castOfCharacters: castOfCharacters
            });
        }

        try config.getPayload_BuyManyOfferedERC721WithEtherDistinctOrders(
            contexts, desiredItems, prices
        ) returns (OrderPayload memory payload) {
            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyManyOfferedERC721WithEtherDistinctOrders_FulfillThroughAdapter(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item721[] memory desiredItems,
        uint256[] memory prices
    )
        public
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        bool requiresTakerIsSender = _isBlur(config) || _isBlurV2(config)
            || _isLooksRareV2(config) || _isX2y2(config);

        OrderContext[] memory contexts = new OrderContext[](desiredItems.length);

        address originalFulfiller = castOfCharacters.fulfiller;

        {
            for (uint256 i = 0; i < desiredItems.length; i++) {
                contexts[i] = OrderContext({
                    listOnChain: false,
                    routeThroughAdapter: true,
                    castOfCharacters: castOfCharacters
                });

                contexts[i].castOfCharacters.fulfiller = requiresTakerIsSender
                    ? contexts[i].castOfCharacters.sidecar
                    : castOfCharacters.fulfiller;
            }
        }

        try config.getPayload_BuyManyOfferedERC721WithEtherDistinctOrders(
            contexts, desiredItems, prices
        ) returns (OrderPayload memory payload) {
            for (uint256 i = 0; i < contexts.length; i++) {
                contexts[i].castOfCharacters.fulfiller = originalFulfiller;
            }

            uint256 flashloanAmount;

            {
                for (uint256 i = 0; i < prices.length; i++) {
                    flashloanAmount += prices[i];
                }
            }

            itemsToBeProvidedToAdapter = new ConsiderationItem[](
                1
            );
            {
                itemsToBeProvidedToAdapter[0] = ConsiderationItem({
                    itemType: ItemType.NATIVE,
                    token: address(0),
                    identifierOrCriteria: 0,
                    startAmount: flashloanAmount,
                    endAmount: flashloanAmount,
                    recipient: payable(address(0))
                });
            }

            itemsToBeOfferedByAdapter = new OfferItem[](desiredItems.length);

            sidecarItemTransfers = new ItemTransfer[](desiredItems.length);

            {
                // TODO: see if making a helper eases the stack pressure.
                Item721[] memory _desiredItems = desiredItems;
                for (uint256 i; i < _desiredItems.length; i++) {
                    sidecarItemTransfers[i] = ItemTransfer({
                        from: contexts[i].castOfCharacters.sidecar,
                        to: contexts[i].castOfCharacters.adapter,
                        token: _desiredItems[i].token,
                        identifier: _desiredItems[i].identifier,
                        amount: 1,
                        itemType: ItemType.ERC721
                    });

                    itemsToBeOfferedByAdapter[i] =
                        _desiredItemToOfferItem(_desiredItems[i]);
                }
            }

            // BREADCRUMB
            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                contexts[0].castOfCharacters,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );

            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyManyOfferedERC721WithEtherDistinctOrders_ListOnChain(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item721[] memory desiredItems,
        uint256[] memory prices
    )
        public
        view
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext[] memory contexts = new OrderContext[](desiredItems.length);

        for (uint256 i = 0; i < contexts.length; i++) {
            contexts[i] = OrderContext({
                listOnChain: true,
                routeThroughAdapter: false,
                castOfCharacters: castOfCharacters
            });
        }

        try config.getPayload_BuyManyOfferedERC721WithEtherDistinctOrders(
            contexts, desiredItems, prices
        ) returns (OrderPayload memory payload) {
            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyManyOfferedERC721WithEtherDistinctOrders_ListOnChain_FulfillThroughAdapter(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item721[] memory desiredItems,
        uint256[] memory prices
    )
        public
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        bool transfersToSpecifiedTaker = _isSudo(config);

        address originalFulfiller = castOfCharacters.fulfiller;

        OrderContext[] memory contexts = new OrderContext[](desiredItems.length);

        for (uint256 i = 0; i < contexts.length; i++) {
            contexts[i] = OrderContext({
                listOnChain: true,
                routeThroughAdapter: true,
                castOfCharacters: castOfCharacters
            });

            contexts[i].castOfCharacters.fulfiller = transfersToSpecifiedTaker
                ? contexts[i].castOfCharacters.adapter
                : contexts[i].castOfCharacters.fulfiller;
        }

        try config.getPayload_BuyManyOfferedERC721WithEtherDistinctOrders(
            contexts, desiredItems, prices
        ) returns (OrderPayload memory payload) {
            for (uint256 i = 0; i < contexts.length; i++) {
                contexts[i].castOfCharacters.fulfiller = originalFulfiller;
            }

            uint256 flashloanAmount;

            {
                for (uint256 i; i < prices.length; i++) {
                    flashloanAmount += prices[i];
                }
            }

            itemsToBeOfferedByAdapter = new OfferItem[](desiredItems.length);

            {
                for (uint256 i; i < desiredItems.length; i++) {
                    itemsToBeOfferedByAdapter[i] =
                        _desiredItemToOfferItem(desiredItems[i]);
                }
            }

            itemsToBeProvidedToAdapter = new ConsiderationItem[](
                1
            );
            {
                itemsToBeProvidedToAdapter[0] = ConsiderationItem({
                    itemType: ItemType.NATIVE,
                    token: address(0),
                    identifierOrCriteria: 0,
                    startAmount: flashloanAmount,
                    endAmount: flashloanAmount,
                    recipient: payable(address(0))
                });
            }

            sidecarItemTransfers = new ItemTransfer[](desiredItems.length);
            {
                Item721[] memory _desiredItems = desiredItems;

                for (uint256 i; i < _desiredItems.length; i++) {
                    sidecarItemTransfers[i] = ItemTransfer({
                        from: contexts[i].castOfCharacters.sidecar,
                        to: contexts[i].castOfCharacters.adapter,
                        token: _desiredItems[i].token,
                        identifier: _desiredItems[i].identifier,
                        amount: 1,
                        itemType: ItemType.ERC721
                    });
                }
            }

            // Sudo does the transfers.
            if (transfersToSpecifiedTaker) {
                sidecarItemTransfers = new ItemTransfer[](0);
            }

            // BREADCRUMB
            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                contexts[0].castOfCharacters,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );

            payload.executeOrder.value = flashloanAmount;

            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyManyOfferedERC721WithErc20DistinctOrders(
        BaseMarketConfig config,
        CastOfCharacters[] memory castOfCharactersArray,
        Item721[] memory desiredItems,
        Item20[] memory payments
    )
        public
        view
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext[] memory contexts = new OrderContext[](desiredItems.length);
        uint256[] memory paymentAmounts = new uint256[](10);

        for (uint256 i = 0; i < contexts.length; i++) {
            contexts[i] = OrderContext(false, false, castOfCharactersArray[i]);
            paymentAmounts[i] = payments[i].amount;
        }

        // TODO: Come back and rework this getPayload function across the board.
        try config.getPayload_BuyManyOfferedERC721WithErc20DistinctOrders(
            contexts, desiredItems, payments
        ) returns (OrderPayload memory payload) {
            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyManyOfferedERC721WithErc20DistinctOrders_FulfillThroughAdapter(
        BaseMarketConfig config,
        CastOfCharacters[] memory castOfCharactersArray,
        Item721[] memory desiredItems,
        Item20[] memory payments
    )
        public
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext[] memory contexts = new OrderContext[](desiredItems.length);

        for (uint256 i = 0; i < contexts.length; i++) {
            contexts[i] = OrderContext(false, true, castOfCharactersArray[i]);
        }

        address originalFulfiller = contexts[0].castOfCharacters.fulfiller;

        {
            bool requiresTakerIsSender = _isLooksRare(config)
                || _isLooksRareV2(config) || _isX2y2(config);
            if (requiresTakerIsSender) {
                for (uint256 i = 0; i < contexts.length; i++) {
                    contexts[i].castOfCharacters.fulfiller =
                        address(contexts[i].castOfCharacters.sidecar);
                }
            }
        }

        try config.getPayload_BuyManyOfferedERC721WithErc20DistinctOrders(
            contexts, desiredItems, payments
        ) returns (OrderPayload memory payload) {
            {
                for (uint256 i = 0; i < contexts.length; i++) {
                    contexts[i].castOfCharacters.fulfiller = originalFulfiller;
                }
            }

            itemsToBeProvidedToAdapter = new ConsiderationItem[](1);

            {
                uint256 totalERC20Amount;

                {
                    for (uint256 i = 0; i < contexts.length; i++) {
                        totalERC20Amount += payments[i].amount;
                    }
                }

                // TODO: Come back and make this more flexible.
                itemsToBeProvidedToAdapter[0] = ConsiderationItem({
                    itemType: ItemType.ERC20,
                    token: payments[0].token,
                    identifierOrCriteria: 0,
                    startAmount: totalERC20Amount,
                    endAmount: totalERC20Amount,
                    recipient: payable(address(0))
                });
            }

            itemsToBeOfferedByAdapter = new OfferItem[](desiredItems.length);
            sidecarItemTransfers = new ItemTransfer[](desiredItems.length);

            {
                Item721[] memory _desiredItems = desiredItems;
                for (uint256 i; i < _desiredItems.length; i++) {
                    sidecarItemTransfers[i] = _desiredItemToSidecarItemTransfer(
                        _desiredItems[i], contexts[i].castOfCharacters
                    );

                    itemsToBeOfferedByAdapter[i] =
                        _desiredItemToOfferItem(_desiredItems[i]);
                }
            }

            // TODO: Come back and make this more flexible.
            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                castOfCharactersArray[0],
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );

            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    // TODO: Come back and make the cast of characters array consistent across
    // these.
    function getPayloadToBuyManyOfferedERC721WithErc20DistinctOrders_ListOnChain(
        BaseMarketConfig config,
        CastOfCharacters[] memory castOfCharactersArray,
        Item721[] memory desiredItems,
        Item20[] memory payments
    )
        public
        view
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext[] memory contexts = new OrderContext[](desiredItems.length);

        uint256[] memory paymentAmounts = new uint256[](10);

        for (uint256 i = 0; i < contexts.length; i++) {
            contexts[i] = OrderContext({
                listOnChain: true,
                routeThroughAdapter: false,
                castOfCharacters: castOfCharactersArray[i]
            });
            paymentAmounts[i] = payments[i].amount;
        }

        // TODO: Come back and refactor this.
        try config.getPayload_BuyManyOfferedERC721WithErc20DistinctOrders(
            contexts, desiredItems, payments
        ) returns (OrderPayload memory payload) {
            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyManyOfferedERC721WithErc20DistinctOrders_ListOnChain_FulfillThroughAdapter(
        BaseMarketConfig config,
        CastOfCharacters[] memory castOfCharactersArray,
        Item721[] memory desiredItems,
        Item20[] memory payments
    )
        public
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext[] memory contexts = new OrderContext[](desiredItems.length);

        uint256[] memory paymentAmounts = new uint256[](10);

        bool requiresTakerIsSender =
            _isLooksRare(config) || _isLooksRareV2(config) || _isX2y2(config);

        address originalFulfiller = contexts[0].castOfCharacters.fulfiller;

        if (requiresTakerIsSender) {
            for (uint256 i = 0; i < contexts.length; i++) {
                contexts[i].castOfCharacters.fulfiller =
                    address(contexts[i].castOfCharacters.sidecar);
            }
        }

        for (uint256 i = 0; i < desiredItems.length; i++) {
            contexts[i] = OrderContext({
                listOnChain: true,
                routeThroughAdapter: true,
                castOfCharacters: castOfCharactersArray[i]
            });
            paymentAmounts[i] = payments[i].amount;
        }

        // TODO: Come back and rework.
        try config.getPayload_BuyManyOfferedERC721WithErc20DistinctOrders(
            contexts, desiredItems, payments
        ) returns (OrderPayload memory payload) {
            for (uint256 i = 0; i < contexts.length; i++) {
                contexts[i].castOfCharacters.fulfiller = originalFulfiller;
            }

            itemsToBeProvidedToAdapter = new ConsiderationItem[](1);

            uint256 totalERC20Amount;

            for (uint256 i = 0; i < contexts.length; i++) {
                totalERC20Amount += paymentAmounts[i];
            }

            // Again, come back and rework this to allow for sets of arbitrary
            // ERC20s.
            itemsToBeProvidedToAdapter[0] = ConsiderationItem({
                itemType: ItemType.ERC20,
                token: payments[0].token,
                identifierOrCriteria: 0,
                startAmount: totalERC20Amount,
                endAmount: totalERC20Amount,
                recipient: payable(address(0))
            });

            itemsToBeOfferedByAdapter = new OfferItem[](desiredItems.length);

            sidecarItemTransfers = new ItemTransfer[](desiredItems.length);

            {
                Item721[] memory _desiredItems = desiredItems;
                for (uint256 i; i < _desiredItems.length; i++) {
                    sidecarItemTransfers[i] = ItemTransfer({
                        from: contexts[i].castOfCharacters.sidecar,
                        to: contexts[i].castOfCharacters.adapter,
                        token: _desiredItems[i].token,
                        identifier: _desiredItems[i].identifier,
                        amount: 1,
                        itemType: ItemType.ERC721
                    });

                    itemsToBeOfferedByAdapter[i] =
                        _desiredItemToOfferItem(_desiredItems[i]);
                }
            }

            // BREADCRUMB
            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                contexts[0].castOfCharacters,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );

            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyManyOfferedERC721WithWETHDistinctOrders(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item721[] memory desiredItems,
        Item20[] memory weths
    )
        public
        view
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext[] memory contexts = new OrderContext[](desiredItems.length);
        uint256[] memory wethAmounts = new uint256[](10);

        for (uint256 i = 0; i < desiredItems.length; i++) {
            contexts[i] = OrderContext({
                listOnChain: false,
                routeThroughAdapter: false,
                castOfCharacters: castOfCharacters
            });
            wethAmounts[i] = weths[i].amount;
        }

        try config.getPayload_BuyManyOfferedERC721WithWETHDistinctOrders(
            contexts, wethAddress, desiredItems, wethAmounts
        ) returns (OrderPayload memory payload) {
            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyManyOfferedERC721WithWETHDistinctOrders_FulfillThroughAdapter(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item721[] memory desiredItems,
        Item20[] memory payments
    )
        public
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext[] memory contexts = new OrderContext[](desiredItems.length);

        uint256[] memory wethAmounts = new uint256[](10);

        for (uint256 i = 0; i < desiredItems.length; i++) {
            contexts[i] = OrderContext({
                listOnChain: false,
                routeThroughAdapter: true,
                castOfCharacters: castOfCharacters
            });
            wethAmounts[i] = payments[i].amount;
        }

        bool requiresTakerIsSender =
            _isBlur(config) || _isLooksRareV2(config) || _isX2y2(config);

        // Note: should be fine, fulfiller should be the same across.ERC20
        address originalFulfiller = contexts[0].castOfCharacters.fulfiller;

        if (requiresTakerIsSender) {
            for (uint256 i = 0; i < contexts.length; i++) {
                contexts[i].castOfCharacters.fulfiller =
                    contexts[i].castOfCharacters.sidecar;
            }
        }

        try config.getPayload_BuyManyOfferedERC721WithWETHDistinctOrders(
            contexts, wethAddress, desiredItems, wethAmounts
        ) returns (OrderPayload memory payload) {
            for (uint256 i = 0; i < contexts.length; i++) {
                contexts[i].castOfCharacters.fulfiller = originalFulfiller;
            }

            uint256 totalWethAmount;

            for (uint256 i = 0; i < wethAmounts.length; i++) {
                totalWethAmount += wethAmounts[i];
            }

            // TODO: Come back and clean this up.
            itemsToBeProvidedToAdapter = new ConsiderationItem[](1);
            itemsToBeProvidedToAdapter[0] = ConsiderationItem({
                itemType: ItemType.ERC20,
                token: payments[0].token,
                identifierOrCriteria: 0,
                startAmount: totalWethAmount,
                endAmount: totalWethAmount,
                recipient: payable(address(0))
            });

            itemsToBeOfferedByAdapter = new OfferItem[](desiredItems.length);
            sidecarItemTransfers = new ItemTransfer[](desiredItems.length);

            {
                // TODO: Come back and think about array stuff.
                sidecarItemTransfers = _desiredItemsToSidecarItemTransfers(
                    desiredItems, contexts[0].castOfCharacters
                );
            }

            {
                itemsToBeOfferedByAdapter =
                    _desiredItemsToOfferItems(desiredItems);
            }

            // BREADCRUMB
            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                contexts[0].castOfCharacters,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );

            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    function getPayloadToBuyManyOfferedERC721WithWETHDistinctOrders_ListOnChain(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item721[] memory desiredItems,
        Item20[] memory payments
    )
        public
        view
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext[] memory contexts = new OrderContext[](desiredItems.length);

        uint256[] memory wethAmounts = new uint256[](10);

        for (uint256 i = 0; i < desiredItems.length; i++) {
            contexts[i] = OrderContext({
                listOnChain: true,
                routeThroughAdapter: false,
                castOfCharacters: castOfCharacters
            });
            wethAmounts[i] = payments[i].amount;
        }

        try config.getPayload_BuyManyOfferedERC721WithWETHDistinctOrders(
            contexts, wethAddress, desiredItems, wethAmounts
        ) returns (OrderPayload memory payload) {
            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    // TODO: either get rid of the "WithWETH" functions or convert them to
    // automatically populate the WETH info so you can just pass in a price.
    function getPayloadToBuyManyOfferedERC721WithWETHDistinctOrders_ListOnChain_FulfillThroughAdapter(
        BaseMarketConfig config,
        CastOfCharacters memory castOfCharacters,
        Item721[] memory desiredItems,
        Item20[] memory weths
    )
        public
        returns (
            OrderPayload memory _payload,
            OfferItem[] memory itemsToBeOfferedByAdapter,
            ConsiderationItem[] memory itemsToBeProvidedToAdapter,
            ItemTransfer[] memory sidecarItemTransfers
        )
    {
        OrderContext[] memory contexts = new OrderContext[](desiredItems.length);

        uint256[] memory wethAmounts = new uint256[](10);

        for (uint256 i = 0; i < desiredItems.length; i++) {
            contexts[i] = OrderContext({
                listOnChain: true,
                routeThroughAdapter: true,
                castOfCharacters: castOfCharacters
            });
            wethAmounts[i] = weths[i].amount;
        }

        try config.getPayload_BuyManyOfferedERC721WithWETHDistinctOrders(
            contexts, wethAddress, desiredItems, wethAmounts
        ) returns (OrderPayload memory payload) {
            itemsToBeProvidedToAdapter = new ConsiderationItem[](
                1
            );

            uint256 totalWethAmount;

            for (uint256 i; i < wethAmounts.length; ++i) {
                totalWethAmount += wethAmounts[i];
            }

            itemsToBeOfferedByAdapter = new OfferItem[](desiredItems.length);

            for (uint256 i; i < desiredItems.length; i++) {
                itemsToBeOfferedByAdapter[i] =
                    _desiredItemToOfferItem(desiredItems[i]);
            }

            itemsToBeProvidedToAdapter[0] = ConsiderationItem({
                itemType: ItemType.ERC20,
                token: wethAddress,
                identifierOrCriteria: 0,
                startAmount: totalWethAmount,
                endAmount: totalWethAmount,
                recipient: payable(address(0))
            });

            // BREADCRUMB
            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedCallParameters(
                contexts[0].castOfCharacters,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                new ItemTransfer[](0)
            );

            return (
                payload,
                itemsToBeOfferedByAdapter,
                itemsToBeProvidedToAdapter,
                sidecarItemTransfers
            );
        } catch {
            _revertNotSupported();
        }
    }

    /*//////////////////////////////////////////////////////////////
                          Helpers
    //////////////////////////////////////////////////////////////*/

    // Note: this is where `_setApprovals` in `prepareTest` was.
    // TODO: Think about making a nice tool to set up necessary approvals.

    // TODO: make this a script that initializes the contracts kind of like what
    // _setAdapterSpecificApprovals does.

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

    function _revertNotSupported() internal pure {
        revert(
            "Not currently supported. See <some_README> for details on how to add support."
        );
    }

    function _desiredItemToOfferItem(Item721 memory desiredItem)
        public
        pure
        returns (OfferItem memory)
    {
        return OfferItem({
            itemType: ItemType.ERC721,
            token: desiredItem.token,
            identifierOrCriteria: desiredItem.identifier,
            startAmount: 1,
            endAmount: 1
        });
    }

    function _desiredItemToOfferItem(Item1155 memory desiredItem)
        public
        pure
        returns (OfferItem memory)
    {
        return OfferItem({
            itemType: ItemType.ERC1155,
            token: desiredItem.token,
            identifierOrCriteria: desiredItem.identifier,
            startAmount: desiredItem.amount,
            endAmount: desiredItem.amount
        });
    }

    function _desiredPaymentToOfferItem(Item20 memory desiredPayment)
        public
        pure
        returns (OfferItem memory)
    {
        return OfferItem({
            itemType: ItemType.ERC20,
            token: desiredPayment.token,
            identifierOrCriteria: 0,
            startAmount: desiredPayment.amount,
            endAmount: desiredPayment.amount
        });
    }

    function _desiredItemsToOfferItems(Item721[] memory desiredItems)
        public
        pure
        returns (OfferItem[] memory)
    {
        OfferItem[] memory itemsToBeOfferedByAdapter =
            new OfferItem[](desiredItems.length);

        for (uint256 i; i < desiredItems.length; i++) {
            itemsToBeOfferedByAdapter[i] =
                _desiredItemToOfferItem(desiredItems[i]);
        }

        return itemsToBeOfferedByAdapter;
    }

    function _desiredItemsToOfferItems(Item1155[] memory desiredItems)
        public
        pure
        returns (OfferItem[] memory)
    {
        OfferItem[] memory itemsToBeOfferedByAdapter =
            new OfferItem[](desiredItems.length);

        for (uint256 i; i < desiredItems.length; i++) {
            itemsToBeOfferedByAdapter[i] =
                _desiredItemToOfferItem(desiredItems[i]);
        }

        return itemsToBeOfferedByAdapter;
    }

    function _desiredPaymentsToOfferItems(Item20[] memory desiredPayments)
        public
        pure
        returns (OfferItem[] memory)
    {
        OfferItem[] memory itemsToBeOfferedByAdapter =
            new OfferItem[](desiredPayments.length);

        for (uint256 i; i < desiredPayments.length; i++) {
            itemsToBeOfferedByAdapter[i] =
                _desiredPaymentToOfferItem(desiredPayments[i]);
        }

        return itemsToBeOfferedByAdapter;
    }

    function _desiredPaymentToSidecarItemTransfer(
        Item20 memory desiredPayment,
        CastOfCharacters memory castOfCharacters
    ) public pure returns (ItemTransfer memory) {
        return ItemTransfer({
            from: castOfCharacters.sidecar,
            to: castOfCharacters.adapter,
            token: desiredPayment.token,
            identifier: 0,
            amount: desiredPayment.amount,
            itemType: ItemType.ERC20
        });
    }

    function _desiredItemToSidecarItemTransfer(
        Item721 memory desiredItem,
        CastOfCharacters memory castOfCharacters
    ) public pure returns (ItemTransfer memory) {
        return ItemTransfer({
            from: castOfCharacters.sidecar,
            to: castOfCharacters.adapter,
            token: desiredItem.token,
            identifier: desiredItem.identifier,
            amount: 1,
            itemType: ItemType.ERC721
        });
    }

    function _desiredItemToSidecarItemTransfer(
        Item1155 memory desiredItem,
        CastOfCharacters memory castOfCharacters
    ) public pure returns (ItemTransfer memory) {
        return ItemTransfer({
            from: castOfCharacters.sidecar,
            to: castOfCharacters.adapter,
            token: desiredItem.token,
            identifier: desiredItem.identifier,
            amount: desiredItem.amount,
            itemType: ItemType.ERC1155
        });
    }

    function _desiredPaymentsToSidecarItemTransfers(
        Item20[] memory desiredPayments,
        CastOfCharacters memory castOfCharacters
    ) public pure returns (ItemTransfer[] memory) {
        ItemTransfer[] memory sidecarItemTransfers =
            new ItemTransfer[](desiredPayments.length);

        for (uint256 i; i < desiredPayments.length; i++) {
            sidecarItemTransfers[i] = _desiredPaymentToSidecarItemTransfer(
                desiredPayments[i], castOfCharacters
            );
        }

        return sidecarItemTransfers;
    }

    function _desiredItemsToSidecarItemTransfers(
        Item721[] memory desiredItems,
        CastOfCharacters memory castOfCharacters
    ) public pure returns (ItemTransfer[] memory) {
        ItemTransfer[] memory sidecarItemTransfers =
            new ItemTransfer[](desiredItems.length);

        for (uint256 i; i < desiredItems.length; i++) {
            sidecarItemTransfers[i] = _desiredItemToSidecarItemTransfer(
                desiredItems[i], castOfCharacters
            );
        }

        return sidecarItemTransfers;
    }

    function _desiredItemsToSidecarItemTransfers(
        Item1155[] memory desiredItems,
        CastOfCharacters memory castOfCharacters
    ) public pure returns (ItemTransfer[] memory) {
        ItemTransfer[] memory sidecarItemTransfers =
            new ItemTransfer[](desiredItems.length);

        for (uint256 i; i < desiredItems.length; i++) {
            sidecarItemTransfers[i] = _desiredItemToSidecarItemTransfer(
                desiredItems[i], castOfCharacters
            );
        }

        return sidecarItemTransfers;
    }

    function _paymentToConsiderationItem(Item20 memory payment)
        public
        pure
        returns (ConsiderationItem memory)
    {
        return ConsiderationItem({
            itemType: ItemType.ERC20,
            token: payment.token,
            identifierOrCriteria: 0,
            startAmount: payment.amount,
            endAmount: payment.amount,
            recipient: payable(address(0))
        });
    }
}
