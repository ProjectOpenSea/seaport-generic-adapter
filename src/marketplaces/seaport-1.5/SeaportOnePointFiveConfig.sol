// SPDX-License-Identifier: MIT
pragma solidity >=0.8.7;

import { BaseMarketConfig } from "../BaseMarketConfig.sol";
import { OrderPayload } from "../../utils/Types.sol";

import {
    Call,
    Item721,
    Item1155,
    Item20,
    OrderContext
} from "../../lib/AdapterHelperLib.sol";
import "seaport-types/lib/ConsiderationStructs.sol";
import "./lib/ConsiderationTypeHashes.sol";
import { ConsiderationInterface as ISeaport } from
    "seaport-types/interfaces/ConsiderationInterface.sol";
import "forge-std/console2.sol";

// prettier-ignore
enum BasicOrderRouteType
// 0: provide Ether (or other native token) to receive offered ERC721 item.
{
    ETH_TO_ERC721,
    // 1: provide Ether (or other native token) to receive offered ERC1155 item.
    ETH_TO_ERC1155,
    // 2: provide ERC20 item to receive offered ERC721 item.
    ERC20_TO_ERC721,
    // 3: provide ERC20 item to receive offered ERC1155 item.
    ERC20_TO_ERC1155,
    // 4: provide ERC721 item to receive offered ERC20 item.
    ERC721_TO_ERC20,
    // 5: provide ERC1155 item to receive offered ERC20 item.
    ERC1155_TO_ERC20
}

contract SeaportOnePointFiveConfig is
    BaseMarketConfig,
    ConsiderationTypeHashes
{
    function name() external pure override returns (string memory) {
        return "Seaport 1.5";
    }

    function market() public pure override returns (address) {
        return address(seaport);
    }

    // ISeaport internal constant seaport =
    //     ISeaport(0x00000000000000ADc04C56Bf30aC9d3c0aAF14dC);

    function buildBasicOrder(
        BasicOrderRouteType routeType,
        address offerer,
        OfferItem memory offerItem,
        ConsiderationItem memory considerationItem
    )
        internal
        view
        returns (
            Order memory order,
            BasicOrderParameters memory basicComponents
        )
    {
        OrderParameters memory components = order.parameters;
        components.offerer = offerer;
        components.offer = new OfferItem[](1);
        components.consideration = new ConsiderationItem[](1);
        components.offer[0] = offerItem;
        components.consideration[0] = considerationItem;
        components.startTime = 0;
        components.endTime = block.timestamp + 1;
        components.totalOriginalConsiderationItems = 1;
        basicComponents.startTime = 0;
        basicComponents.endTime = block.timestamp + 1;
        basicComponents.considerationToken = considerationItem.token;
        basicComponents.considerationIdentifier =
            considerationItem.identifierOrCriteria;
        basicComponents.considerationAmount = considerationItem.endAmount;
        basicComponents.offerer = payable(offerer);
        basicComponents.offerToken = offerItem.token;
        basicComponents.offerIdentifier = offerItem.identifierOrCriteria;
        basicComponents.offerAmount = offerItem.endAmount;
        basicComponents.basicOrderType = BasicOrderType(uint256(routeType) * 4);
        basicComponents.totalOriginalAdditionalRecipients = 0;
        bytes32 digest = _deriveEIP712Digest(_deriveOrderHash(components, 0));
        (uint8 v, bytes32 r, bytes32 s) = _sign(offerer, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        basicComponents.signature = (order.signature = signature);
    }

    function buildBasicOrder(
        BasicOrderRouteType routeType,
        address offerer,
        OfferItem memory offerItem,
        ConsiderationItem memory considerationItem,
        AdditionalRecipient[] memory additionalRecipients
    )
        internal
        view
        returns (
            Order memory order,
            BasicOrderParameters memory basicComponents
        )
    {
        OrderParameters memory components = order.parameters;
        components.offerer = offerer;
        components.offer = new OfferItem[](1);
        components.consideration = new ConsiderationItem[](
            1 + additionalRecipients.length
        );
        components.offer[0] = offerItem;
        components.consideration[0] = considerationItem;

        // Add additional recipients
        address additionalRecipientsToken;
        if (
            routeType == BasicOrderRouteType.ERC721_TO_ERC20
                || routeType == BasicOrderRouteType.ERC1155_TO_ERC20
        ) {
            additionalRecipientsToken = offerItem.token;
        } else {
            additionalRecipientsToken = considerationItem.token;
        }
        ItemType additionalRecipientsItemType;
        if (
            routeType == BasicOrderRouteType.ETH_TO_ERC721
                || routeType == BasicOrderRouteType.ETH_TO_ERC1155
        ) {
            additionalRecipientsItemType = ItemType.NATIVE;
        } else {
            additionalRecipientsItemType = ItemType.ERC20;
        }
        for (uint256 i = 0; i < additionalRecipients.length; i++) {
            components.consideration[i + 1] = ConsiderationItem(
                additionalRecipientsItemType,
                additionalRecipientsToken,
                0,
                additionalRecipients[i].amount,
                additionalRecipients[i].amount,
                additionalRecipients[i].recipient
            );
        }

        components.startTime = 0;
        components.endTime = block.timestamp + 1;
        components.totalOriginalConsiderationItems =
            1 + additionalRecipients.length;
        basicComponents.startTime = 0;
        basicComponents.endTime = block.timestamp + 1;
        basicComponents.considerationToken = considerationItem.token;
        basicComponents.considerationIdentifier =
            considerationItem.identifierOrCriteria;
        basicComponents.considerationAmount = considerationItem.endAmount;
        basicComponents.offerer = payable(offerer);
        basicComponents.offerToken = offerItem.token;
        basicComponents.offerIdentifier = offerItem.identifierOrCriteria;
        basicComponents.offerAmount = offerItem.endAmount;
        basicComponents.basicOrderType = BasicOrderType(uint256(routeType) * 4);
        basicComponents.additionalRecipients = additionalRecipients;
        basicComponents.totalOriginalAdditionalRecipients =
            additionalRecipients.length;
        bytes32 digest = _deriveEIP712Digest(_deriveOrderHash(components, 0));
        (uint8 v, bytes32 r, bytes32 s) = _sign(offerer, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        basicComponents.signature = (order.signature = signature);
    }

    function buildOrder(
        address offerer,
        OfferItem[] memory offerItems,
        ConsiderationItem[] memory considerationItems,
        bool skipSignature
    ) internal view returns (Order memory order) {
        OrderParameters memory components = order.parameters;
        components.offerer = offerer;
        components.offer = offerItems;
        components.consideration = considerationItems;
        components.orderType = OrderType.FULL_OPEN;
        components.startTime = 0;
        components.endTime = block.timestamp + 1;
        components.totalOriginalConsiderationItems = considerationItems.length;

        if (!skipSignature) {
            bytes32 digest =
                _deriveEIP712Digest(_deriveOrderHash(components, 0));
            (uint8 v, bytes32 r, bytes32 s) = _sign(offerer, digest);
            bytes memory signature = abi.encodePacked(r, s, v);
            order.signature = signature;
        }
    }

    function buildOrderAndFulfillmentManyDistinctOrders(
        OrderContext[] memory contexts,
        address paymentTokenAddress,
        Item721[] memory nfts,
        uint256[] memory amounts,
        bool skipSignatures
    )
        public
        view
        override
        returns (Order[] memory, Fulfillment[] memory, uint256)
    {
        Order[] memory orders = new Order[](nfts.length + 1);

        ConsiderationItem[] memory fulfillerConsiderationItems =
        new ConsiderationItem[](
                nfts.length
            );

        Fulfillment[] memory fullfillments = new Fulfillment[](nfts.length + 1);

        for (uint256 i = 0; i < nfts.length; i++) {
            // Build offer orders
            OfferItem[] memory offerItems = new OfferItem[](1);

            ConsiderationItem[] memory considerationItems =
                new ConsiderationItem[](1);
            {
                offerItems[0] = OfferItem(
                    ItemType.ERC721, nfts[i].token, nfts[i].identifier, 1, 1
                );
            }
            {
                considerationItems[0] = ConsiderationItem(
                    paymentTokenAddress != address(0)
                        ? ItemType.ERC20
                        : ItemType.NATIVE,
                    paymentTokenAddress,
                    0,
                    amounts[i],
                    amounts[i],
                    payable(contexts[i].castOfCharacters.offerer)
                );
            }
            {
                orders[i] = buildOrder(
                    contexts[i].castOfCharacters.offerer,
                    offerItems,
                    considerationItems,
                    skipSignatures
                );
            }
            {
                fulfillerConsiderationItems[i] = ConsiderationItem(
                    ItemType.ERC721,
                    nfts[i].token,
                    nfts[i].identifier,
                    1,
                    1,
                    payable(contexts[i].castOfCharacters.fulfiller)
                );
            }
            {
                // Add fulfillment components for each NFT

                FulfillmentComponent memory nftConsiderationComponent =
                    FulfillmentComponent(nfts.length, i);

                FulfillmentComponent memory nftOfferComponent =
                    FulfillmentComponent(i, 0);

                FulfillmentComponent[] memory nftOfferComponents =
                    new FulfillmentComponent[](1);
                nftOfferComponents[0] = nftOfferComponent;

                FulfillmentComponent[] memory nftConsiderationComponents =
                new FulfillmentComponent[](
                        1
                    );
                nftConsiderationComponents[0] = nftConsiderationComponent;
                fullfillments[i] =
                    Fulfillment(nftOfferComponents, nftConsiderationComponents);
            }
        }

        uint256 sumAmounts = 0;

        for (uint256 i = 0; i < nfts.length; i++) {
            sumAmounts += amounts[i];
        }

        {
            FulfillmentComponent memory paymentTokenOfferComponent =
                FulfillmentComponent(nfts.length, 0);

            FulfillmentComponent[] memory paymentTokenOfferComponents =
            new FulfillmentComponent[](
                    1
                );
            paymentTokenOfferComponents[0] = paymentTokenOfferComponent;

            FulfillmentComponent[] memory paymentTokenConsiderationComponents =
            new FulfillmentComponent[](
                    nfts.length
                );
            for (uint256 i = 0; i < nfts.length; i++) {
                {
                    FulfillmentComponent memory
                        paymentTokenConsiderationComponent =
                            FulfillmentComponent(i, 0);
                    paymentTokenConsiderationComponents[i] =
                        paymentTokenConsiderationComponent;
                }
            }
            fullfillments[nfts.length] = Fulfillment(
                paymentTokenOfferComponents, paymentTokenConsiderationComponents
            );
        }

        // Build sweep floor order
        OfferItem[] memory fulfillerOfferItems = new OfferItem[](1);
        fulfillerOfferItems[0] = OfferItem(
            paymentTokenAddress != address(0) ? ItemType.ERC20 : ItemType.NATIVE,
            paymentTokenAddress,
            0,
            sumAmounts,
            sumAmounts
        );
        orders[nfts.length] = buildOrder(
            contexts[0].castOfCharacters.fulfiller,
            fulfillerOfferItems,
            fulfillerConsiderationItems,
            skipSignatures
        );
        orders[nfts.length].signature = ""; // Signature isn't needed since
            // fulfiller is msg.sender

        return (orders, fullfillments, sumAmounts);
    }

    function beforeAllPrepareMarketplace(address, address) external override {
        buyerNftApprovalTarget = sellerNftApprovalTarget =
        buyerErc20ApprovalTarget = sellerErc20ApprovalTarget = address(seaport);
    }

    function getPayload_BuyOfferedERC721WithEther(
        OrderContext calldata context,
        Item721 memory nft,
        uint256 ethAmount
    ) external view override returns (OrderPayload memory execution) {
        (Order memory order, BasicOrderParameters memory basicComponents) =
        buildBasicOrder(
            BasicOrderRouteType.ETH_TO_ERC721,
            context.castOfCharacters.offerer,
            OfferItem(ItemType.ERC721, nft.token, nft.identifier, 1, 1),
            ConsiderationItem(
                ItemType.NATIVE,
                address(0),
                0,
                ethAmount,
                ethAmount,
                payable(context.castOfCharacters.offerer)
            )
        );
        if (context.listOnChain) {
            order.signature = "";
            basicComponents.signature = "";

            Order[] memory orders = new Order[](1);
            orders[0] = order;
            execution.submitOrder = Call(
                address(seaport),
                false,
                0,
                abi.encodeWithSelector(ISeaport.validate.selector, orders)
            );
        }
        execution.executeOrder = Call(
            address(seaport),
            false,
            ethAmount,
            abi.encodeWithSelector(
                ISeaport.fulfillBasicOrder_efficient_6GL6yc.selector,
                basicComponents
            )
        );
    }

    function getPayload_BuyOfferedERC1155WithEther(
        OrderContext calldata context,
        Item1155 memory nft,
        uint256 ethAmount
    ) external view override returns (OrderPayload memory execution) {
        (Order memory order, BasicOrderParameters memory basicComponents) =
        buildBasicOrder(
            BasicOrderRouteType.ETH_TO_ERC1155,
            context.castOfCharacters.offerer,
            OfferItem(
                ItemType.ERC1155,
                nft.token,
                nft.identifier,
                nft.amount,
                nft.amount
            ),
            ConsiderationItem(
                ItemType.NATIVE,
                address(0),
                0,
                ethAmount,
                ethAmount,
                payable(context.castOfCharacters.offerer)
            )
        );
        if (context.listOnChain) {
            order.signature = "";
            basicComponents.signature = "";

            Order[] memory orders = new Order[](1);
            orders[0] = order;
            execution.submitOrder = Call(
                address(seaport),
                false,
                0,
                abi.encodeWithSelector(ISeaport.validate.selector, orders)
            );
        }
        execution.executeOrder = Call(
            address(seaport),
            false,
            ethAmount,
            abi.encodeWithSelector(
                ISeaport.fulfillBasicOrder_efficient_6GL6yc.selector,
                basicComponents
            )
        );
    }

    function getComponents_BuyOfferedERC721WithERC20(
        address offerer,
        Item721 calldata nft,
        Item20 calldata erc20
    )
        external
        view
        override
        returns (BasicOrderParameters memory basicComponents)
    {
        (, basicComponents) = buildBasicOrder(
            BasicOrderRouteType.ERC20_TO_ERC721,
            offerer,
            OfferItem(ItemType.ERC721, nft.token, nft.identifier, 1, 1),
            ConsiderationItem(
                ItemType.ERC20,
                erc20.token,
                0,
                erc20.amount,
                erc20.amount,
                payable(offerer)
            )
        );
    }

    function getPayload_BuyOfferedERC721WithERC20(
        OrderContext calldata context,
        Item721 memory nft,
        Item20 memory erc20
    ) external view override returns (OrderPayload memory execution) {
        (Order memory order, BasicOrderParameters memory basicComponents) =
        buildBasicOrder(
            BasicOrderRouteType.ERC20_TO_ERC721,
            context.castOfCharacters.offerer,
            OfferItem(ItemType.ERC721, nft.token, nft.identifier, 1, 1),
            ConsiderationItem(
                ItemType.ERC20,
                erc20.token,
                0,
                erc20.amount,
                erc20.amount,
                payable(context.castOfCharacters.offerer)
            )
        );
        if (context.listOnChain) {
            order.signature = "";
            basicComponents.signature = "";

            Order[] memory orders = new Order[](1);
            orders[0] = order;
            execution.submitOrder = Call(
                address(seaport),
                false,
                0,
                abi.encodeWithSelector(ISeaport.validate.selector, orders)
            );
        }
        execution.executeOrder = Call(
            address(seaport),
            false,
            0,
            abi.encodeWithSelector(
                ISeaport.fulfillBasicOrder_efficient_6GL6yc.selector,
                basicComponents
            )
        );
    }

    function getPayload_BuyOfferedERC721WithWETH(
        OrderContext calldata context,
        Item721 memory nft,
        Item20 memory erc20
    ) external view override returns (OrderPayload memory execution) {
        (Order memory order, BasicOrderParameters memory basicComponents) =
        buildBasicOrder(
            BasicOrderRouteType.ERC20_TO_ERC721,
            context.castOfCharacters.offerer,
            OfferItem(ItemType.ERC721, nft.token, nft.identifier, 1, 1),
            ConsiderationItem(
                ItemType.ERC20,
                erc20.token,
                0,
                erc20.amount,
                erc20.amount,
                payable(context.castOfCharacters.offerer)
            )
        );
        if (context.listOnChain) {
            order.signature = "";
            basicComponents.signature = "";

            Order[] memory orders = new Order[](1);
            orders[0] = order;
            execution.submitOrder = Call(
                address(seaport),
                false,
                0,
                abi.encodeWithSelector(ISeaport.validate.selector, orders)
            );
        }
        execution.executeOrder = Call(
            address(seaport),
            false,
            0,
            abi.encodeWithSelector(
                ISeaport.fulfillBasicOrder_efficient_6GL6yc.selector,
                basicComponents
            )
        );
    }

    function getComponents_BuyOfferedERC1155WithERC20(
        address maker,
        Item1155 calldata nft,
        Item20 memory erc20
    ) public view override returns (BasicOrderParameters memory) {
        (, BasicOrderParameters memory basicComponents) = buildBasicOrder(
            BasicOrderRouteType.ERC20_TO_ERC1155,
            maker,
            OfferItem(
                ItemType.ERC1155,
                nft.token,
                nft.identifier,
                nft.amount,
                nft.amount
            ),
            ConsiderationItem(
                ItemType.ERC20,
                erc20.token,
                0,
                erc20.amount,
                erc20.amount,
                payable(maker)
            )
        );

        return basicComponents;
    }

    function getPayload_BuyOfferedERC1155WithERC20(
        OrderContext calldata context,
        Item1155 calldata nft,
        Item20 memory erc20
    ) external view override returns (OrderPayload memory execution) {
        (Order memory order, BasicOrderParameters memory basicComponents) =
        buildBasicOrder(
            BasicOrderRouteType.ERC20_TO_ERC1155,
            context.castOfCharacters.offerer,
            OfferItem(
                ItemType.ERC1155,
                nft.token,
                nft.identifier,
                nft.amount,
                nft.amount
            ),
            ConsiderationItem(
                ItemType.ERC20,
                erc20.token,
                0,
                erc20.amount,
                erc20.amount,
                payable(context.castOfCharacters.offerer)
            )
        );
        if (context.listOnChain) {
            order.signature = "";
            basicComponents.signature = "";

            Order[] memory orders = new Order[](1);
            orders[0] = order;
            execution.submitOrder = Call(
                address(seaport),
                false,
                0,
                abi.encodeWithSelector(ISeaport.validate.selector, orders)
            );
        }
        execution.executeOrder = Call(
            address(seaport),
            false,
            0,
            abi.encodeWithSelector(
                ISeaport.fulfillBasicOrder_efficient_6GL6yc.selector,
                basicComponents
            )
        );
    }

    function getPayload_BuyOfferedERC20WithERC721(
        OrderContext calldata context,
        Item20 memory erc20,
        Item721 memory nft
    ) external view override returns (OrderPayload memory execution) {
        (Order memory order, BasicOrderParameters memory basicComponents) =
        buildBasicOrder(
            BasicOrderRouteType.ERC721_TO_ERC20,
            context.castOfCharacters.offerer,
            OfferItem(
                ItemType.ERC20, erc20.token, 0, erc20.amount, erc20.amount
            ),
            ConsiderationItem(
                ItemType.ERC721,
                nft.token,
                nft.identifier,
                1,
                1,
                payable(context.castOfCharacters.offerer)
            )
        );
        if (context.listOnChain) {
            order.signature = "";
            basicComponents.signature = "";

            Order[] memory orders = new Order[](1);
            orders[0] = order;
            execution.submitOrder = Call(
                address(seaport),
                false,
                0,
                abi.encodeWithSelector(ISeaport.validate.selector, orders)
            );
        }
        execution.executeOrder = Call(
            address(seaport),
            false,
            0,
            abi.encodeWithSelector(
                ISeaport.fulfillBasicOrder_efficient_6GL6yc.selector,
                basicComponents
            )
        );
    }

    function getPayload_BuyOfferedWETHWithERC721(
        OrderContext calldata context,
        Item20 memory erc20,
        Item721 memory nft
    ) external view override returns (OrderPayload memory execution) {
        (Order memory order, BasicOrderParameters memory basicComponents) =
        buildBasicOrder(
            BasicOrderRouteType.ERC721_TO_ERC20,
            context.castOfCharacters.offerer,
            OfferItem(
                ItemType.ERC20, erc20.token, 0, erc20.amount, erc20.amount
            ),
            ConsiderationItem(
                ItemType.ERC721,
                nft.token,
                nft.identifier,
                1,
                1,
                payable(context.castOfCharacters.offerer)
            )
        );
        if (context.listOnChain) {
            order.signature = "";
            basicComponents.signature = "";

            Order[] memory orders = new Order[](1);
            orders[0] = order;
            execution.submitOrder = Call(
                address(seaport),
                false,
                0,
                abi.encodeWithSelector(ISeaport.validate.selector, orders)
            );
        }
        execution.executeOrder = Call(
            address(seaport),
            false,
            0,
            abi.encodeWithSelector(
                ISeaport.fulfillBasicOrder_efficient_6GL6yc.selector,
                basicComponents
            )
        );
    }

    function getComponents_BuyOfferedERC20WithERC1155(
        address maker,
        Item20 calldata erc20,
        Item1155 calldata nft
    )
        external
        view
        override
        returns (BasicOrderParameters memory basicComponents)
    {
        (, basicComponents) = buildBasicOrder(
            BasicOrderRouteType.ERC1155_TO_ERC20,
            maker,
            OfferItem(
                ItemType.ERC20, erc20.token, 0, erc20.amount, erc20.amount
            ),
            ConsiderationItem(
                ItemType.ERC1155,
                nft.token,
                nft.identifier,
                nft.amount,
                nft.amount,
                payable(maker)
            )
        );
    }

    function getPayload_BuyOfferedERC20WithERC1155(
        OrderContext calldata context,
        Item20 memory erc20,
        Item1155 calldata nft
    ) external view override returns (OrderPayload memory execution) {
        (Order memory order, BasicOrderParameters memory basicComponents) =
        buildBasicOrder(
            BasicOrderRouteType.ERC1155_TO_ERC20,
            context.castOfCharacters.offerer,
            OfferItem(
                ItemType.ERC20, erc20.token, 0, erc20.amount, erc20.amount
            ),
            ConsiderationItem(
                ItemType.ERC1155,
                nft.token,
                nft.identifier,
                nft.amount,
                nft.amount,
                payable(context.castOfCharacters.offerer)
            )
        );
        if (context.listOnChain) {
            order.signature = "";
            basicComponents.signature = "";

            Order[] memory orders = new Order[](1);
            orders[0] = order;
            execution.submitOrder = Call(
                address(seaport),
                false,
                0,
                abi.encodeWithSelector(ISeaport.validate.selector, orders)
            );
        }
        execution.executeOrder = Call(
            address(seaport),
            false,
            0,
            abi.encodeWithSelector(
                ISeaport.fulfillBasicOrder_efficient_6GL6yc.selector,
                basicComponents
            )
        );
    }

    function getPayload_BuyOfferedERC721WithERC1155(
        OrderContext calldata context,
        Item721 memory sellNft,
        Item1155 calldata buyNft
    ) external view override returns (OrderPayload memory execution) {
        OfferItem[] memory offerItems = new OfferItem[](1);
        ConsiderationItem[] memory considerationItems = new ConsiderationItem[](
            1
        );

        offerItems[0] =
            OfferItem(ItemType.ERC721, sellNft.token, sellNft.identifier, 1, 1);
        considerationItems[0] = ConsiderationItem(
            ItemType.ERC1155,
            buyNft.token,
            buyNft.identifier,
            buyNft.amount,
            buyNft.amount,
            payable(context.castOfCharacters.offerer)
        );

        Order memory order = buildOrder(
            context.castOfCharacters.offerer,
            offerItems,
            considerationItems,
            false
        );

        if (context.listOnChain) {
            order.signature = "";

            Order[] memory orders = new Order[](1);
            orders[0] = order;
            execution.submitOrder = Call(
                address(seaport),
                false,
                0,
                abi.encodeWithSelector(ISeaport.validate.selector, orders)
            );
        }
        execution.executeOrder = Call(
            address(seaport),
            false,
            0,
            abi.encodeWithSelector(ISeaport.fulfillOrder.selector, order, 0)
        );
    }

    function getPayload_BuyOfferedERC1155WithERC721(
        OrderContext calldata context,
        Item1155 memory sellNft,
        Item721 calldata buyNft
    ) external view override returns (OrderPayload memory execution) {
        OfferItem[] memory offerItems = new OfferItem[](1);
        ConsiderationItem[] memory considerationItems = new ConsiderationItem[](
            1
        );

        offerItems[0] = OfferItem(
            ItemType.ERC1155,
            sellNft.token,
            sellNft.identifier,
            sellNft.amount,
            sellNft.amount
        );
        considerationItems[0] = ConsiderationItem(
            ItemType.ERC721,
            buyNft.token,
            buyNft.identifier,
            1,
            1,
            payable(context.castOfCharacters.offerer)
        );

        Order memory order = buildOrder(
            context.castOfCharacters.offerer,
            offerItems,
            considerationItems,
            false
        );

        if (context.listOnChain) {
            order.signature = "";

            Order[] memory orders = new Order[](1);
            orders[0] = order;
            execution.submitOrder = Call(
                address(seaport),
                false,
                0,
                abi.encodeWithSelector(ISeaport.validate.selector, orders)
            );
        }
        execution.executeOrder = Call(
            address(seaport),
            false,
            0,
            abi.encodeWithSelector(ISeaport.fulfillOrder.selector, order, 0)
        );
    }

    function getPayload_BuyOfferedERC721WithEtherOneFeeRecipient(
        OrderContext calldata context,
        Item721 memory nft,
        uint256 priceEthAmount,
        address feeRecipient,
        uint256 feeEthAmount
    ) external view override returns (OrderPayload memory execution) {
        AdditionalRecipient[] memory additionalRecipients =
            new AdditionalRecipient[](1);
        additionalRecipients[0] =
            AdditionalRecipient(feeEthAmount, payable(feeRecipient));
        (Order memory order, BasicOrderParameters memory basicComponents) =
        buildBasicOrder(
            BasicOrderRouteType.ETH_TO_ERC721,
            context.castOfCharacters.offerer,
            OfferItem(ItemType.ERC721, nft.token, nft.identifier, 1, 1),
            ConsiderationItem(
                ItemType.NATIVE,
                address(0),
                0,
                priceEthAmount,
                priceEthAmount,
                payable(context.castOfCharacters.offerer)
            ),
            additionalRecipients
        );
        if (context.listOnChain) {
            order.signature = "";
            basicComponents.signature = "";

            Order[] memory orders = new Order[](1);
            orders[0] = order;
            execution.submitOrder = Call(
                address(seaport),
                false,
                0,
                abi.encodeWithSelector(ISeaport.validate.selector, orders)
            );
        }
        execution.executeOrder = Call(
            address(seaport),
            false,
            priceEthAmount + feeEthAmount,
            abi.encodeWithSelector(
                ISeaport.fulfillBasicOrder_efficient_6GL6yc.selector,
                basicComponents
            )
        );
    }

    function getPayload_BuyOfferedERC721WithEtherTwoFeeRecipient(
        OrderContext calldata context,
        Item721 memory nft,
        uint256 priceEthAmount,
        address feeRecipient1,
        uint256 feeEthAmount1,
        address feeRecipient2,
        uint256 feeEthAmount2
    ) external view override returns (OrderPayload memory execution) {
        AdditionalRecipient[] memory additionalRecipients =
            new AdditionalRecipient[](2);

        additionalRecipients[0] =
            AdditionalRecipient(feeEthAmount1, payable(feeRecipient1));
        additionalRecipients[1] =
            AdditionalRecipient(feeEthAmount2, payable(feeRecipient2));
        ConsiderationItem memory consideration = ConsiderationItem(
            ItemType.NATIVE,
            address(0),
            0,
            priceEthAmount,
            priceEthAmount,
            payable(context.castOfCharacters.offerer)
        );
        (Order memory order, BasicOrderParameters memory basicComponents) =
        buildBasicOrder(
            BasicOrderRouteType.ETH_TO_ERC721,
            context.castOfCharacters.offerer,
            OfferItem(ItemType.ERC721, nft.token, nft.identifier, 1, 1),
            consideration,
            additionalRecipients
        );
        if (context.listOnChain) {
            order.signature = "";
            basicComponents.signature = "";

            Order[] memory orders = new Order[](1);
            orders[0] = order;
            execution.submitOrder = Call(
                address(seaport),
                false,
                0,
                abi.encodeWithSelector(ISeaport.validate.selector, orders)
            );
        }
        execution.executeOrder = Call(
            address(seaport),
            false,
            priceEthAmount + feeEthAmount1 + feeEthAmount2,
            abi.encodeWithSelector(
                ISeaport.fulfillBasicOrder_efficient_6GL6yc.selector,
                basicComponents
            )
        );
    }

    function getPayload_BuyManyOfferedERC721WithEther(
        OrderContext calldata context,
        Item721[] calldata nfts,
        uint256 ethAmount
    ) external view override returns (OrderPayload memory execution) {
        OfferItem[] memory offerItems = new OfferItem[](nfts.length);

        for (uint256 i = 0; i < nfts.length; i++) {
            offerItems[i] = OfferItem(
                ItemType.ERC721, nfts[i].token, nfts[i].identifier, 1, 1
            );
        }

        ConsiderationItem[] memory considerationItems = new ConsiderationItem[](
            1
        );

        considerationItems[0] = ConsiderationItem(
            ItemType.NATIVE,
            address(0),
            0,
            ethAmount,
            ethAmount,
            payable(context.castOfCharacters.offerer)
        );

        Order memory order = buildOrder(
            context.castOfCharacters.offerer,
            offerItems,
            considerationItems,
            false
        );

        if (context.listOnChain) {
            order.signature = "";

            Order[] memory orders = new Order[](1);
            orders[0] = order;
            execution.submitOrder = Call(
                address(seaport),
                false,
                0,
                abi.encodeWithSelector(ISeaport.validate.selector, orders)
            );
        }

        execution.executeOrder = Call(
            address(seaport),
            false,
            ethAmount,
            abi.encodeWithSelector(ISeaport.fulfillOrder.selector, order, 0)
        );
    }

    function getPayload_BuyManyOfferedERC721WithEtherDistinctOrders(
        OrderContext[] calldata contexts,
        Item721[] calldata nfts,
        uint256[] calldata ethAmounts
    ) external view override returns (OrderPayload memory execution) {
        require(
            contexts.length == nfts.length && nfts.length == ethAmounts.length,
            "SeaportConfig::getPayload_BuyManyOfferedERC721WithEtherDistinctOrders: invalid input"
        );

        (
            Order[] memory orders,
            Fulfillment[] memory fullfillments,
            uint256 sumEthAmount
        ) = buildOrderAndFulfillmentManyDistinctOrders(
            contexts, address(0), nfts, ethAmounts, false
        );

        // Validate all for simplicity for now, could make this combination of
        // on-chain and not
        if (contexts[0].listOnChain) {
            Order[] memory ordersToValidate = new Order[](orders.length - 1); // Last
                // order is fulfiller order
            for (uint256 i = 0; i < orders.length - 1; i++) {
                orders[i].signature = "";
                ordersToValidate[i] = orders[i];
            }

            execution.submitOrder = Call(
                address(seaport),
                false,
                0,
                abi.encodeWithSelector(
                    ISeaport.validate.selector, ordersToValidate
                )
            );
        }

        execution.executeOrder = Call(
            address(seaport),
            false,
            sumEthAmount,
            abi.encodeWithSelector(
                ISeaport.matchOrders.selector, orders, fullfillments
            )
        );
    }

    function getPayload_BuyManyOfferedERC721WithErc20DistinctOrders(
        OrderContext[] calldata contexts,
        Item721[] calldata nfts,
        Item20[] calldata erc20s
    ) external view override returns (OrderPayload memory execution) {
        require(
            contexts.length == nfts.length && nfts.length == erc20s.length,
            "SeaportConfig::getPayload_BuyManyOfferedERC721WithEtherDistinctOrders: invalid input"
        );

        uint256[] memory prices = new uint256[](erc20s.length);
        for (uint256 i = 0; i < erc20s.length; i++) {
            prices[i] = erc20s[i].amount;
        }

        (Order[] memory orders, Fulfillment[] memory fullfillments,) =
        buildOrderAndFulfillmentManyDistinctOrders(
            contexts, erc20s[0].token, nfts, prices, false
        );

        // Validate all for simplicity for now, could make this combination of
        // on-chain and not
        if (contexts[0].listOnChain) {
            Order[] memory ordersToValidate = new Order[](orders.length - 1); // Last
                // order is fulfiller order
            for (uint256 i = 0; i < orders.length - 1; i++) {
                orders[i].signature = "";
                ordersToValidate[i] = orders[i];
            }

            execution.submitOrder = Call(
                address(seaport),
                false,
                0,
                abi.encodeWithSelector(
                    ISeaport.validate.selector, ordersToValidate
                )
            );
        }

        execution.executeOrder = Call(
            address(seaport),
            false,
            0,
            abi.encodeWithSelector(
                ISeaport.matchOrders.selector, orders, fullfillments
            )
        );
    }

    function getPayload_BuyManyOfferedERC721WithWETHDistinctOrders(
        OrderContext[] calldata contexts,
        address erc20Address,
        Item721[] calldata nfts,
        uint256[] calldata erc20Amounts
    ) external view override returns (OrderPayload memory execution) {
        require(
            contexts.length == nfts.length && nfts.length == erc20Amounts.length,
            "SeaportConfig::getPayload_BuyManyOfferedERC721WithEtherDistinctOrders: invalid input"
        );
        (Order[] memory orders, Fulfillment[] memory fullfillments,) =
        buildOrderAndFulfillmentManyDistinctOrders(
            contexts, erc20Address, nfts, erc20Amounts, false
        );

        // Validate all for simplicity for now, could make this combination of
        // on-chain and not
        if (contexts[0].listOnChain) {
            Order[] memory ordersToValidate = new Order[](orders.length - 1); // Last
                // order is fulfiller order
            for (uint256 i = 0; i < orders.length - 1; i++) {
                orders[i].signature = "";
                ordersToValidate[i] = orders[i];
            }

            execution.submitOrder = Call(
                address(seaport),
                false,
                0,
                abi.encodeWithSelector(
                    ISeaport.validate.selector, ordersToValidate
                )
            );
        }

        execution.executeOrder = Call(
            address(seaport),
            false,
            0,
            abi.encodeWithSelector(
                ISeaport.matchOrders.selector, orders, fullfillments
            )
        );
    }

    function getPayload_MatchOrders_ABCA(
        OrderContext[] calldata contexts,
        Item721[] calldata nfts
    ) external view override returns (OrderPayload memory execution) {
        require(contexts.length == nfts.length, "invalid input");

        Order[] memory orders = new Order[](contexts.length);
        Fulfillment[] memory fullfillments = new Fulfillment[](nfts.length);

        for (uint256 i = 0; i < nfts.length; i++) {
            uint256 wrappedIndex = i + 1 == nfts.length ? 0 : i + 1; // wrap
                // around back to 0
            {
                OfferItem[] memory offerItems = new OfferItem[](1);
                offerItems[0] = OfferItem(
                    ItemType.ERC721, nfts[i].token, nfts[i].identifier, 1, 1
                );

                ConsiderationItem[] memory considerationItems =
                    new ConsiderationItem[](1);
                considerationItems[0] = ConsiderationItem(
                    ItemType.ERC721,
                    nfts[wrappedIndex].token,
                    nfts[wrappedIndex].identifier,
                    1,
                    1,
                    payable(contexts[i].castOfCharacters.offerer)
                );
                orders[i] = buildOrder(
                    contexts[i].castOfCharacters.offerer,
                    offerItems,
                    considerationItems,
                    false
                );
            }
            // Set fulfillment
            {
                FulfillmentComponent memory nftConsiderationComponent =
                    FulfillmentComponent(i, 0);

                FulfillmentComponent memory nftOfferComponent =
                    FulfillmentComponent(wrappedIndex, 0);

                FulfillmentComponent[] memory nftOfferComponents =
                    new FulfillmentComponent[](1);
                nftOfferComponents[0] = nftOfferComponent;

                FulfillmentComponent[] memory nftConsiderationComponents =
                new FulfillmentComponent[](
                        1
                    );
                nftConsiderationComponents[0] = nftConsiderationComponent;
                fullfillments[i] =
                    Fulfillment(nftOfferComponents, nftConsiderationComponents);
            }
        }

        execution.executeOrder = Call(
            address(seaport),
            false,
            0,
            abi.encodeWithSelector(
                ISeaport.matchOrders.selector, orders, fullfillments
            )
        );
    }

    // This should take an arbitrary number of "prime" seaport orders. Then it
    // should also take in the relevant data to add on flashloans if necessary,
    // their corresponding mirror orders, and the adapter order to execute
    // the aggregated orders from other marketplaces.
    function getPayload_MatchOrders_Aggregate(
        OrderContext[] calldata contexts,
        Item721[] calldata nfts
    ) external view override returns (OrderPayload memory execution) {
        require(contexts.length == nfts.length, "invalid input");

        Order[] memory orders = new Order[](contexts.length);
        Fulfillment[] memory fullfillments = new Fulfillment[](nfts.length);

        for (uint256 i = 0; i < nfts.length; i++) {
            uint256 wrappedIndex = i + 1 == nfts.length ? 0 : i + 1; // wrap
                // around back to 0
            {
                OfferItem[] memory offerItems = new OfferItem[](1);
                offerItems[0] = OfferItem(
                    ItemType.ERC721, nfts[i].token, nfts[i].identifier, 1, 1
                );

                ConsiderationItem[] memory considerationItems =
                    new ConsiderationItem[](1);
                considerationItems[0] = ConsiderationItem(
                    ItemType.ERC721,
                    nfts[wrappedIndex].token,
                    nfts[wrappedIndex].identifier,
                    1,
                    1,
                    payable(contexts[i].castOfCharacters.offerer)
                );
                orders[i] = buildOrder(
                    contexts[i].castOfCharacters.offerer,
                    offerItems,
                    considerationItems,
                    false
                );
            }
            // Set fulfillment
            {
                FulfillmentComponent memory nftConsiderationComponent =
                    FulfillmentComponent(i, 0);

                FulfillmentComponent memory nftOfferComponent =
                    FulfillmentComponent(wrappedIndex, 0);

                FulfillmentComponent[] memory nftOfferComponents =
                    new FulfillmentComponent[](1);
                nftOfferComponents[0] = nftOfferComponent;

                FulfillmentComponent[] memory nftConsiderationComponents =
                new FulfillmentComponent[](
                        1
                    );
                nftConsiderationComponents[0] = nftConsiderationComponent;
                fullfillments[i] =
                    Fulfillment(nftOfferComponents, nftConsiderationComponents);
            }
        }

        execution.executeOrder = Call(
            address(seaport),
            false,
            0,
            abi.encodeWithSelector(
                ISeaport.matchOrders.selector, orders, fullfillments
            )
        );
    }
}
