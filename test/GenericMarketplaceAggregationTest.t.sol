// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

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
    Flashloan,
    ItemTransfer
} from "../src/lib/AdapterHelperLib.sol";

import { ConsiderationInterface as ISeaport } from
    "seaport-types/interfaces/ConsiderationInterface.sol";

import { BaseMarketConfig } from "./BaseMarketConfig.sol";

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

import { SetupCall, TestOrderPayload } from "./utils/Types.sol";

import {
    CallParameters,
    Item20,
    Item721,
    Item1155,
    OrderContext
} from "../src/lib/AdapterHelperLib.sol";

import { GenericMarketplaceTest } from "./GenericMarketplaceTest.t.sol";

import "forge-std/console.sol";

address constant VM_ADDRESS =
    address(uint160(uint256(keccak256("hevm cheat code"))));
Vm constant vm = Vm(VM_ADDRESS);

contract GenericMarketplaceAggregationTest is GenericMarketplaceTest {
    using ConsiderationItemLib for ConsiderationItem;
    using ConsiderationItemLib for ConsiderationItem[];
    using OrderParametersLib for OrderParameters;
    using OrderParametersLib for OrderParameters[];
    using AdapterHelperLib for CallParameters;
    using AdapterHelperLib for CallParameters[];

    constructor() {
        blurConfig = BaseMarketConfig(new BlurConfig());
        foundationConfig = BaseMarketConfig(new FoundationConfig());
        looksRareConfig = BaseMarketConfig(new LooksRareConfig());
        looksRareV2Config = BaseMarketConfig(new LooksRareV2Config());
        seaportOnePointFiveConfig =
            BaseMarketConfig(new SeaportOnePointFiveConfig());
        sudoswapConfig = BaseMarketConfig(new SudoswapConfig());
        x2y2Config = BaseMarketConfig(new X2Y2Config());
        zeroExConfig = BaseMarketConfig(new ZeroExConfig());
    }

    function testBlur() external override { }
    function testBlurV2() external override { }
    function testFoundation() external override { }
    function testLooksRare() external override { }
    function testLooksRareV2() external override { }
    function testSudoswap() external override { }
    function testX2Y2() external override { }
    function testZeroEx() external override { }

    /*//////////////////////////////////////////////////////////////////////////
                        Special Case Mixed Order Tests
    //////////////////////////////////////////////////////////////////////////*/

    // The idea here is to fulfill a bunch of orders individually and add up all
    // the gas costs. This is like someone just clicking around on these
    // marketplaces fulfilling orders directly.
    function testFulfillMixedOrdersIndividually() external {
        BaseMarketConfig[] memory configs = new BaseMarketConfig[](4);
        configs[0] = foundationConfig;
        configs[1] = zeroExConfig;
        configs[2] = blurConfig;
        configs[3] = seaportOnePointFiveConfig;
        benchmarkMixedIndividually(configs);
    }

    function benchmarkMixedIndividually(BaseMarketConfig[] memory configs)
        public
    {
        _doSetup();
        _setAdapterSpecificApprovals();
        _prepareMarketplaces(configs);

        uint256 firstOrderGasUsed =
            buyOfferedERC721WithEtherFee_ListOnChain(configs[0]);
        uint256 secondOrderGasUsed =
            buyOfferedERC1155WithEther_ListOnChain(configs[1]);
        uint256 thirdOrderGasUsed = buyOfferedERC721WithWETH(configs[2]);
        uint256 fourthOrderGasUsed = buyOfferedERC1155WithERC20(configs[3]);

        uint256 totalGasUsed = firstOrderGasUsed + secondOrderGasUsed
            + thirdOrderGasUsed + fourthOrderGasUsed;

        emit log_named_uint(
            "Total gas for fulfilling orders individually", totalGasUsed
        );
    }

    function testFulfillMixedOrdersIndividuallyThroughAdapter() external {
        BaseMarketConfig[] memory configs = new BaseMarketConfig[](4);
        configs[0] = foundationConfig;
        configs[1] = zeroExConfig;
        configs[2] = blurConfig;
        configs[3] = seaportOnePointFiveConfig;
        benchmarkMixedIndividuallyThroughAdapter(configs);
    }

    function benchmarkMixedIndividuallyThroughAdapter(
        BaseMarketConfig[] memory configs
    ) public {
        _doSetup();
        _setAdapterSpecificApprovals();
        _prepareMarketplaces(configs);

        uint256 firstOrderGasUsed =
            buyOfferedERC721WithEtherFee_ListOnChain_Adapter(configs[0]);
        uint256 secondOrderGasUsed =
            buyOfferedERC1155WithEther_ListOnChain_Adapter(configs[1]);
        uint256 thirdOrderGasUsed = buyOfferedERC721WithWETH_Adapter(configs[2]);
        // Not through adapter bc it's Seaport.
        uint256 fourthOrderGasUsed = buyOfferedERC1155WithERC20(configs[3]);

        uint256 totalGasUsed = firstOrderGasUsed + secondOrderGasUsed
            + thirdOrderGasUsed + fourthOrderGasUsed;

        emit log_named_uint(
            "Total gas for fulfilling orders individually with adapter",
            totalGasUsed
        );
    }

    function testMixedAggregatedThroughSeaport() external {
        BaseMarketConfig[] memory configs = new BaseMarketConfig[](4);
        configs[0] = foundationConfig;
        configs[1] = zeroExConfig;
        configs[2] = blurConfig;
        configs[3] = seaportOnePointFiveConfig;

        _doSetup();
        _setAdapterSpecificApprovals();
        _prepareMarketplaces(configs);

        uint256 gasUsed = benchmarkMixedAggregatedThroughSeaport(configs);

        emit log_named_uint(
            "Total gas for fulfilling orders aggregated through Seaport",
            gasUsed
        );
    }

    struct BenchmarkAggregatedInfra {
        string testLabel;
        BaseMarketConfig[] configs;
        OrderContext context;
        CallParameters[] executionPayloads;
        AdvancedOrder[] adapterOrders;
        Fulfillment[] adapterFulfillments;
        OfferItem[] adapterOfferArray;
        ConsiderationItem[] adapterConsiderationArray;
        ItemTransfer[] itemTransfers;
        Item1155 item1155;
        AdvancedOrder[] finalOrders;
        Fulfillment[] finalFulfillments;
    }

    function benchmarkMixedAggregatedThroughSeaport(
        BaseMarketConfig[] memory configs
    ) public prepareAggregationTest(configs) returns (uint256) {
        BenchmarkAggregatedInfra memory infra = BenchmarkAggregatedInfra({
            testLabel: "Mixed aggregated through Seaport",
            configs: configs,
            context: OrderContext(true, true, stdCastOfCharacters),
            executionPayloads: new CallParameters[](3),
            adapterOrders: new AdvancedOrder[](3),
            adapterFulfillments: new Fulfillment[](2),
            adapterOfferArray: new OfferItem[](3),
            adapterConsiderationArray: new ConsiderationItem[](2),
            itemTransfers: new ItemTransfer[](3),
            item1155: standardERC1155,
            finalOrders: new AdvancedOrder[](5),
            finalFulfillments: new Fulfillment[](4)
        });

        // Set up the orders. The Seaport order should be passed in normally,
        // and the rest will have to be put together in a big Call array.

        vm.deal(alice, 0);
        test721_1.mint(alice, 1);

        _prepareExternalCalls(infra);

        // Set up the aggregated orders.
        // Orders will be native seaport order, flashloan, mirror, adapter.

        test1155_1.mint(alice, 2, 1);
        hevm.deal(bob, 100);
        test20.mint(bob, 100);

        assertEq(test20.balanceOf(bob), 100);
        assertEq(test20.balanceOf(alice), 0);

        infra.adapterConsiderationArray[0] = ConsiderationItemLib.fromDefault(
            "standardNativeConsiderationItem"
        ).withStartAmount(605).withEndAmount(605);
        infra.adapterConsiderationArray[1] =
            ConsiderationItemLib.fromDefault("standardWethConsiderationItem");

        infra.adapterOfferArray[0] = OfferItem({
            itemType: ItemType.ERC721,
            token: standardERC721.token,
            identifierOrCriteria: 1,
            startAmount: 1,
            endAmount: 1
        });

        infra.adapterOfferArray[1] = OfferItem({
            itemType: ItemType.ERC721,
            token: standardERC721.token,
            identifierOrCriteria: 2,
            startAmount: 1,
            endAmount: 1
        });

        infra.adapterOfferArray[2] = OfferItem({
            itemType: ItemType.ERC1155,
            token: standardERC1155.token,
            identifierOrCriteria: 1,
            startAmount: 1,
            endAmount: 1
        });

        // Stick the items into the adapter so that seaport can yank them out.
        infra.itemTransfers[0] = ItemTransfer({
            from: infra.context.castOfCharacters.sidecar,
            to: infra.context.castOfCharacters.adapter,
            token: standardERC721.token,
            identifier: standardERC721.identifier,
            amount: 1,
            itemType: ItemType.ERC721
        });

        infra.itemTransfers[1] = ItemTransfer({
            from: infra.context.castOfCharacters.sidecar,
            to: infra.context.castOfCharacters.adapter,
            token: standardERC721.token,
            identifier: standardERC721Two.identifier,
            amount: 1,
            itemType: ItemType.ERC721
        });

        infra.itemTransfers[2] = ItemTransfer({
            from: infra.context.castOfCharacters.sidecar,
            to: infra.context.castOfCharacters.adapter,
            token: standardERC1155.token,
            identifier: standardERC1155.identifier,
            amount: 1,
            itemType: ItemType.ERC1155
        });

        // This should provide all the info required for the aggregated orders.
        (infra.adapterOrders, infra.adapterFulfillments) = AdapterHelperLib
            .createSeaportWrappedCallParametersReturnGranular(
            infra.executionPayloads,
            infra.context.castOfCharacters,
            new Call[](0),
            new Call[](0),
            new Flashloan[](0), // The helper will automatically create one.
            infra.adapterOfferArray,
            infra.adapterConsiderationArray,
            infra.itemTransfers
        );

        AdvancedOrder memory orderOffer1155;
        AdvancedOrder memory orderConsider1155;

        {
            BasicOrderParameters memory params = configs[3]
                .getComponents_BuyOfferedERC1155WithERC20(
                alice, Item1155(_test1155Address, 2, 1), standardERC20
            );

            orderOffer1155 = _createSeaportOrderFromBasicParams(params);

            params = configs[3].getComponents_BuyOfferedERC20WithERC1155(
                bob, standardERC20, Item1155(_test1155Address, 2, 1)
            );

            orderConsider1155 = _createSeaportOrderFromBasicParams(params);
        }

        {
            infra.finalOrders[0] = infra.adapterOrders[0];
            infra.finalOrders[1] = infra.adapterOrders[1];
            infra.finalOrders[2] = infra.adapterOrders[2];
            infra.finalOrders[3] = orderOffer1155;
            infra.finalOrders[4] = orderConsider1155;
        }

        _createFulfillmentsForAggregatedTest(infra);

        CallParameters memory finalCallParams;

        {
            finalCallParams = CallParameters(
                seaportAddress, // target will definitely be seaport
                605, // value will be sum of all the values
                abi.encodeWithSelector(
                    ISeaport.matchAdvancedOrders.selector,
                    infra.finalOrders,
                    new CriteriaResolver[](0),
                    infra.finalFulfillments,
                    address(0)
                )
            );
        }

        vm.deal(bob, 605);

        uint256 gasUsed = _benchmarkCallWithParams(
            configs[3].name(),
            string(
                abi.encodePacked(
                    infra.testLabel, " Fulfill aggregated w/ match"
                )
            ),
            true,
            false,
            bob,
            finalCallParams
        );

        // EXPECTED OUTCOMES
        assertEq(test721_1.ownerOf(1), bob, "Bob did not get the 721 1");
        assertEq(test721_1.ownerOf(2), bob, "Bob did not get the 721 2");

        assertEq(
            test1155_1.balanceOf(bob, 1), 1, "Bob did not get the 1155 1 1"
        );
        assertEq(
            test1155_1.balanceOf(bob, 2), 1, "Bob did not get the 1155 2 1"
        );

        // 575 after fees.
        assertEq(alice.balance, 575, "Alice did not get the native");

        assertEq(feeReciever1.balance, 5);

        assertEq(weth.balanceOf(alice), 100, "Alice did not get the wrapped");

        assertEq(test20.balanceOf(alice), 100, "Alice did not get the test20");

        return gasUsed;
    }

    function testMixedAggregatedThroughSeaportFulfillAvailable() external {
        BaseMarketConfig[] memory configs = new BaseMarketConfig[](4);
        configs[0] = x2y2Config;
        configs[1] = zeroExConfig;
        configs[2] = looksRareV2Config;
        configs[3] = seaportOnePointFiveConfig;

        _doSetup();
        _setAdapterSpecificApprovals();
        _prepareMarketplaces(configs);

        uint256 gasUsed =
            benchmarkMixedAggregatedThroughSeaportFulfillAvailable(configs);

        emit log_named_uint(
            "Total gas for fulfilling orders aggregated through Seaport",
            gasUsed
        );
    }

    function benchmarkMixedAggregatedThroughSeaportFulfillAvailable(
        BaseMarketConfig[] memory configs
    ) public prepareAggregationTest(configs) returns (uint256) {
        BenchmarkAggregatedInfra memory infra = BenchmarkAggregatedInfra({
            testLabel: "Mixed aggregated through Seaport Fulfill Available",
            configs: configs,
            context: OrderContext(false, true, stdCastOfCharacters),
            executionPayloads: new CallParameters[](3),
            adapterOrders: new AdvancedOrder[](1),
            adapterFulfillments: new Fulfillment[](0),
            adapterOfferArray: new OfferItem[](3),
            adapterConsiderationArray: new ConsiderationItem[](1),
            itemTransfers: new ItemTransfer[](3),
            item1155: standardERC1155,
            finalOrders: new AdvancedOrder[](2),
            finalFulfillments: new Fulfillment[](4)
        });

        // Set up the orders. The Seaport order should be passed in normally,
        // and the rest will have to be put together in a big Call array.

        vm.deal(alice, 0);
        test721_1.mint(alice, 1);
        test721_1.mint(alice, 2);
        test721_1.mint(alice, 3);
        test721_1.mint(alice, 4);

        test20.mint(bob, 400);

        // Expected starting condition.
        assertEq(test721_1.ownerOf(1), alice, "Alice does not have the 721 1");
        assertEq(test721_1.ownerOf(2), alice, "Alice does not have the 721 2");
        assertEq(test721_1.ownerOf(3), alice, "Alice does not have the 721 3");
        assertEq(test721_1.ownerOf(4), alice, "Alice does not have the 721 4");

        assertEq(test20.balanceOf(bob), 400, "Bob does not have the test20");

        _prepareExternalCallsFulfillAvailable(infra);

        // Set up the aggregated orders.
        // Orders will be native seaport order, adapter.

        infra.adapterConsiderationArray[0] = ConsiderationItemLib.fromDefault(
            "standardERC20ConsiderationItem"
        ).withStartAmount(300).withEndAmount(300);

        infra.adapterOfferArray[0] = OfferItem({
            itemType: ItemType.ERC721,
            token: standardERC721.token,
            identifierOrCriteria: 1,
            startAmount: 1,
            endAmount: 1
        });

        infra.adapterOfferArray[1] = OfferItem({
            itemType: ItemType.ERC721,
            token: standardERC721.token,
            identifierOrCriteria: 2,
            startAmount: 1,
            endAmount: 1
        });

        infra.adapterOfferArray[2] = OfferItem({
            itemType: ItemType.ERC721,
            token: standardERC721.token,
            identifierOrCriteria: 3,
            startAmount: 1,
            endAmount: 1
        });

        infra.itemTransfers[0] = ItemTransfer({
            from: infra.context.castOfCharacters.sidecar,
            to: infra.context.castOfCharacters.adapter,
            token: standardERC721.token,
            identifier: standardERC721.identifier,
            amount: 1,
            itemType: ItemType.ERC721
        });

        infra.itemTransfers[1] = ItemTransfer({
            from: infra.context.castOfCharacters.sidecar,
            to: infra.context.castOfCharacters.adapter,
            token: standardERC721.token,
            identifier: 2,
            amount: 1,
            itemType: ItemType.ERC721
        });

        infra.itemTransfers[2] = ItemTransfer({
            from: infra.context.castOfCharacters.sidecar,
            to: infra.context.castOfCharacters.adapter,
            token: standardERC721.token,
            identifier: 3,
            amount: 1,
            itemType: ItemType.ERC721
        });

        FulfillmentComponent[][] memory offerFulfillments =
            new FulfillmentComponent[][](1);
        FulfillmentComponent[][] memory considerationFulfillments =
            new FulfillmentComponent[][](1);

        (infra.adapterOrders, offerFulfillments, considerationFulfillments) =
        AdapterHelperLib
            .createSeaportWrappedCallParametersReturnGranularFulfillAvailable_TEMP(
            infra.executionPayloads,
            infra.context.castOfCharacters,
            new Call[](0),
            new Call[](0),
            infra.adapterOfferArray,
            infra.adapterConsiderationArray,
            infra.itemTransfers
        );

        AdvancedOrder memory orderOffer721FourForERC20;

        {
            BasicOrderParameters memory params = configs[3]
                .getComponents_BuyOfferedERC721WithERC20(
                alice, Item721(_test721Address, 4), standardERC20
            );

            orderOffer721FourForERC20 =
                _createSeaportOrderFromBasicParams(params);
        }

        {
            infra.finalOrders[0] = orderOffer721FourForERC20;
            infra.finalOrders[1] = infra.adapterOrders[0];
        }

        CallParameters memory finalCallParams;

        {
            finalCallParams = CallParameters(
                seaportAddress, // target will definitely be seaport
                0, // no value
                abi.encodeWithSelector(
                    ISeaport.fulfillAvailableAdvancedOrders.selector,
                    infra.finalOrders,
                    new CriteriaResolver[](0),
                    offerFulfillments,
                    considerationFulfillments,
                    bytes32(0), // fulfillerConduitKey,
                    address(0), // recipient. 0 means the caller should get
                        // everything.
                    2 // maximumFulfilled TODO: set this to a correct value
                )
            );
        }

        uint256 gasUsed = _benchmarkCallWithParams(
            configs[3].name(),
            string(
                abi.encodePacked(
                    infra.testLabel, " Fulfill aggregated w/ fulfillAvailable"
                )
            ),
            true,
            false,
            bob,
            finalCallParams
        );

        // Expected outcomes.
        assertEq(test721_1.ownerOf(1), bob, "Bob did not get the 721 1");
        assertEq(test721_1.ownerOf(2), bob, "Bob did not get the 721 2");
        assertEq(test721_1.ownerOf(3), bob, "Bob did not get the 721 3");
        assertEq(test721_1.ownerOf(4), bob, "Bob did not get the 721 4");

        assertEq(test20.balanceOf(alice), 400, "Alice did not get the test20");

        return gasUsed;
    }

    // /*//////////////////////////////////////////////////////////////
    //                       Helpers
    // //////////////////////////////////////////////////////////////*/

    modifier prepareAggregationTest(BaseMarketConfig[] memory configs) {
        address[] memory markets = new address[](configs.length);
        for (uint256 i = 0; i < configs.length; i++) {
            markets[i] = address(configs[i].market());
        }
        _resetStorageAndEth(markets);

        for (uint256 i = 0; i < configs.length; i++) {
            require(
                configs[i].sellerErc20ApprovalTarget() != address(0)
                    && configs[i].sellerNftApprovalTarget() != address(0)
                    && configs[i].buyerErc20ApprovalTarget() != address(0)
                    && configs[i].buyerNftApprovalTarget() != address(0),
                "BaseMarketplaceTester::prepareAggregationTest: approval target not set"
            );
            _setApprovals(
                alice,
                configs[i].sellerErc20ApprovalTarget(),
                configs[i].sellerNftApprovalTarget(),
                configs[i].sellerErc1155ApprovalTarget()
            );
            _setApprovals(
                cal,
                configs[i].sellerErc20ApprovalTarget(),
                configs[i].sellerNftApprovalTarget(),
                configs[i].sellerErc1155ApprovalTarget()
            );
            _setApprovals(
                bob,
                configs[i].buyerErc20ApprovalTarget(),
                configs[i].buyerNftApprovalTarget(),
                configs[i].buyerErc1155ApprovalTarget()
            );
            // This simulates passing in a Call that approves some target
            // marketplace.
            _setApprovals(
                sidecar,
                configs[i].buyerErc20ApprovalTarget(),
                configs[i].buyerNftApprovalTarget(),
                configs[i].buyerErc1155ApprovalTarget()
            );
            _setApprovals(
                sidecar,
                configs[i].sellerErc20ApprovalTarget(),
                configs[i].sellerNftApprovalTarget(),
                configs[i].sellerErc1155ApprovalTarget()
            );
        }
        _;
    }

    function _prepareMarketplaces(BaseMarketConfig[] memory configs) public {
        for (uint256 i; i < configs.length; i++) {
            beforeAllPrepareMarketplaceTest(configs[i]);
        }
    }

    function _prepareExternalCallsFulfillAvailable(
        BenchmarkAggregatedInfra memory infra
    ) internal {
        // configs[0] = x2y2Config;
        // configs[1] = zeroExConfig;
        // configs[2] = looksRareV2Config;
        // configs[3] = seaportOnePointFiveConfig;
        // LR, and X2Y2 require that the taker is the sender.
        infra.context.castOfCharacters.fulfiller = sidecar;

        try infra.configs[0].getPayload_BuyOfferedERC721WithERC20(
            infra.context, standardERC721, standardERC20
        ) returns (TestOrderPayload memory payload) {
            assertEq(test721_1.ownerOf(1), alice);
            assertEq(test20.balanceOf(alice), 0);
            assertEq(test20.balanceOf(bob), 400);

            infra.executionPayloads[0] = payload.executeOrder;
        } catch {
            _logNotSupported(infra.configs[0].name(), infra.testLabel);
        }

        infra.context.castOfCharacters.fulfiller = bob;

        try infra.configs[1].getPayload_BuyOfferedERC721WithERC20(
            infra.context, Item721(_test721Address, 2), standardERC20
        ) returns (TestOrderPayload memory payload) {
            assertEq(test721_1.ownerOf(2), alice);
            assertEq(test20.balanceOf(alice), 0);
            assertEq(test20.balanceOf(bob), 400);

            infra.executionPayloads[1] = payload.executeOrder;
        } catch {
            _logNotSupported(infra.configs[0].name(), infra.testLabel);
        }

        infra.context.castOfCharacters.fulfiller = sidecar;

        try infra.configs[2].getPayload_BuyOfferedERC721WithERC20(
            infra.context, Item721(_test721Address, 3), standardERC20
        ) returns (TestOrderPayload memory payload) {
            assertEq(test721_1.ownerOf(3), alice);
            assertEq(test20.balanceOf(alice), 0);
            assertEq(test20.balanceOf(bob), 400);

            infra.executionPayloads[2] = payload.executeOrder;
        } catch {
            _logNotSupported(infra.configs[0].name(), infra.testLabel);
        }

        infra.context.castOfCharacters.fulfiller = bob;
    }

    function _prepareExternalCalls(BenchmarkAggregatedInfra memory infra)
        internal
    {
        try infra.configs[0].getPayload_BuyOfferedERC721WithEtherOneFeeRecipient(
            infra.context,
            standardERC721,
            500, // increased so that the fee recipient recieves 1%
            feeReciever1,
            5
        ) returns (TestOrderPayload memory payload) {
            // Fire off the actual prep call to ready the order.
            _benchmarkCallWithParams(
                infra.configs[0].name(),
                string(abi.encodePacked(infra.testLabel, " List")),
                false,
                false,
                alice,
                payload.submitOrder
            );

            // Allow the market to escrow after listing
            assert(
                test721_1.ownerOf(1) == alice
                    || test721_1.ownerOf(1) == infra.configs[0].market()
            );
            assertEq(feeReciever1.balance, 0);

            infra.executionPayloads[0] = payload.executeOrder;
        } catch {
            _logNotSupported(infra.configs[0].name(), infra.testLabel);
        }

        test1155_1.mint(alice, 1, 1);

        try infra.configs[1].getPayload_BuyOfferedERC1155WithEther(
            infra.context, infra.item1155, 100
        ) returns (TestOrderPayload memory payload) {
            _benchmarkCallWithParams(
                infra.configs[1].name(),
                string(abi.encodePacked(infra.testLabel, " List")),
                false,
                false,
                alice,
                payload.submitOrder
            );

            assertEq(test1155_1.balanceOf(alice, 1), 1);
            assertEq(test1155_1.balanceOf(bob, 1), 0);

            infra.executionPayloads[1] = payload.executeOrder;
        } catch {
            _logNotSupported(infra.configs[1].name(), infra.testLabel);
        }

        infra.context = OrderContext(false, true, stdCastOfCharacters);

        test721_1.mint(alice, 2);
        hevm.deal(bob, 100);
        hevm.prank(bob);
        weth.deposit{ value: 100 }();

        // Change the fulfiller to the sidecar to sneak through blur on an ad
        // hoc sig.
        infra.context.castOfCharacters.fulfiller = sidecar;

        // Start with all buy offered NFT with X. But eventually test a mix of
        // offered X for NFT. The helper will need more detail about each NFT
        // transfer (sender, receiver, etc.)
        try infra.configs[2].getPayload_BuyOfferedERC721WithWETH(
            infra.context, standardERC721Two, standardWeth
        ) returns (TestOrderPayload memory payload) {
            infra.context.castOfCharacters.fulfiller = bob;
            assertEq(test721_1.ownerOf(2), alice);
            assertEq(weth.balanceOf(bob), 100);
            assertEq(weth.balanceOf(alice), 0);

            infra.executionPayloads[2] = payload.executeOrder;
        } catch {
            _logNotSupported(infra.configs[2].name(), infra.testLabel);
        }
    }

    function _createFulfillmentsForAggregatedTest(
        BenchmarkAggregatedInfra memory infra
    ) internal pure {
        FulfillmentComponent[] memory offerComponentsPrime =
            new FulfillmentComponent[](1);
        FulfillmentComponent[] memory considerationComponentsPrime =
            new FulfillmentComponent[](1);

        offerComponentsPrime[0] = FulfillmentComponent(3, 0);
        considerationComponentsPrime[0] = FulfillmentComponent(4, 0);

        Fulfillment memory primeFulfillment = Fulfillment({
            offerComponents: offerComponentsPrime,
            considerationComponents: considerationComponentsPrime
        });

        FulfillmentComponent[] memory offerComponentsMirror =
            new FulfillmentComponent[](1);
        FulfillmentComponent[] memory considerationComponentsMirror =
            new FulfillmentComponent[](1);

        offerComponentsMirror[0] = FulfillmentComponent(4, 0);
        considerationComponentsMirror[0] = FulfillmentComponent(3, 0);

        Fulfillment memory mirrorFulfillment = Fulfillment({
            offerComponents: offerComponentsMirror,
            considerationComponents: considerationComponentsMirror
        });

        infra.finalFulfillments[0] = infra.adapterFulfillments[0];
        infra.finalFulfillments[1] = infra.adapterFulfillments[1];
        infra.finalFulfillments[2] = primeFulfillment;
        infra.finalFulfillments[3] = mirrorFulfillment;
    }

    function _createFulfillmentsForFulfillAvailableTest(
        BenchmarkAggregatedInfra memory infra
    ) internal pure { }

    function _createSeaportOrderFromBasicParams(
        BasicOrderParameters memory basicParams
    ) internal returns (AdvancedOrder memory) {
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

        bytes32 digest = _deriveEIP712Digest(_deriveOrderHash(params, 0));

        (uint8 v, bytes32 r, bytes32 s) =
            _signDigest(basicParams.offerer, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        AdvancedOrder memory advancedOrder = AdvancedOrder({
            parameters: params,
            numerator: 1,
            denominator: 1,
            signature: signature,
            extraData: new bytes(0)
        });

        return advancedOrder;
    }
}
