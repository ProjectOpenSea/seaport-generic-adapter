// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import { StdCheats } from "forge-std/StdCheats.sol";

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
    OrderComponents,
    OrderParameters,
    SpentItem
} from "seaport-types/lib/ConsiderationStructs.sol";

import {
    AdapterHelperLib,
    Approval,
    CastOfCharacters,
    Flashloan
} from "../src/lib/AdapterHelperLib.sol";

import { FlashloanOffererInterface } from
    "../src/interfaces/FlashloanOffererInterface.sol";

import { GenericAdapterInterface } from
    "../src/interfaces/GenericAdapterInterface.sol";

import {
    GenericAdapterSidecarInterface,
    Call
} from "../src/interfaces/GenericAdapterSidecarInterface.sol";

import { ConsiderationInterface as ISeaport } from
    "seaport-types/interfaces/ConsiderationInterface.sol";

import { BaseMarketConfig } from "./BaseMarketConfig.sol";

import { BlurConfig } from "../src/marketplaces/blur/BlurConfig.sol";

import { FoundationConfig } from
    "../src/marketplaces/foundation/FoundationConfig.sol";

import { LooksRareConfig } from
    "../src/marketplaces/looksRare/LooksRareConfig.sol";

import { SeaportOnePointFourConfig } from
    "../src/marketplaces/seaport-1.4/SeaportOnePointFourConfig.sol";

import { SudoswapConfig } from "../src/marketplaces/sudoswap/SudoswapConfig.sol";

import { X2Y2Config } from "../src/marketplaces/X2Y2/X2Y2Config.sol";

import { ZeroExConfig } from "../src/marketplaces/zeroEx/ZeroExConfig.sol";

import {
    SetupCall,
    TestCallParameters,
    TestItem20,
    TestItem721,
    TestItem1155,
    TestOrderContext,
    TestOrderPayload
} from "./utils/Types.sol";

import { TestERC20 } from "../src/contracts/test/TestERC20.sol";
import { TestERC721 } from "../src/contracts/test/TestERC721.sol";
import { TestERC1155 } from "../src/contracts/test/TestERC1155.sol";

import { BaseMarketplaceTest } from "./utils/BaseMarketplaceTest.sol";

import { ConsiderationTypeHashes } from
    "../src/marketplaces/seaport-1.4/lib/ConsiderationTypeHashes.sol";

import "forge-std/console.sol";

address constant VM_ADDRESS =
    address(uint160(uint256(keccak256("hevm cheat code"))));
Vm constant vm = Vm(VM_ADDRESS);

contract GenericMarketplaceTest is
    BaseMarketplaceTest,
    StdCheats,
    ConsiderationTypeHashes
{
    using ConsiderationItemLib for ConsiderationItem;
    using ConsiderationItemLib for ConsiderationItem[];
    using OrderParametersLib for OrderParameters;
    using OrderParametersLib for OrderParameters[];
    using AdapterHelperLib for TestCallParameters;
    using AdapterHelperLib for TestCallParameters[];

    BaseMarketConfig blurConfig;
    BaseMarketConfig foundationConfig;
    BaseMarketConfig looksRareConfig;
    BaseMarketConfig seaportOnePointFourConfig;
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

    TestItem20 standardWeth;
    TestItem20 standardERC20;
    TestItem721 standardERC721;
    TestItem721 standardERC721Two;
    TestItem1155 standardERC1155;

    ISeaport internal constant seaport =
        ISeaport(0x00000000000001ad428e4906aE43D8F9852d0dD6);

    CastOfCharacters stdCastOfCharacters;

    constructor() {
        blurConfig = BaseMarketConfig(new BlurConfig());
        foundationConfig = BaseMarketConfig(new FoundationConfig());
        looksRareConfig = BaseMarketConfig(new LooksRareConfig());
        seaportOnePointFourConfig =
            BaseMarketConfig(new SeaportOnePointFourConfig());
        sudoswapConfig = BaseMarketConfig(new SudoswapConfig());
        x2y2Config = BaseMarketConfig(new X2Y2Config());
        zeroExConfig = BaseMarketConfig(new ZeroExConfig());
    }

    // TODO: eventually the *_Adpater functions should be able to be merged into
    // their sibling functions. It'll require resetting the market state
    // between, which might be a pain in the ass or impossible.  And it'll
    // require addressing the taker issue below or else moving the skipping
    // logic around a bit.

    // TODO: after establishing marketplace coverage, think about doing
    // more permutations with flashloans in general

    // Seaport doesn't get tested directly, since there's no need to route
    // through the adapter for native Seaport orders. Also it's impossible bc
    // of the prohibition on reentrant calls.
    // function testSeaportOnePointFour() external {
    //     benchmarkMarket(seaportOnePointFourConfig);
    // }

    function testFoundation() external {
        benchmarkMarket(foundationConfig);
    }

    function testX2Y2() external {
        benchmarkMarket(x2y2Config);
    }

    function testLooksRare() external {
        benchmarkMarket(looksRareConfig);
    }

    function testSudoswap() external {
        benchmarkMarket(sudoswapConfig);
    }

    function testZeroEx() external {
        benchmarkMarket(zeroExConfig);
    }

    function testBlur() external {
        benchmarkMarket(blurConfig);
    }

    function benchmarkMarket(BaseMarketConfig config) public {
        // This is kind of a weird spot for this setup, but the benchmarking
        // repo that this is cribbed from relies on recording logs to wipe them
        // out between function calls. So it's important to be careful where
        // you record logs, because it seems that they collide.
        _doSetup();

        beforeAllPrepareMarketplaceTest(config);

        buyOfferedERC1155WithERC20_ListOnChain(config);
        buyOfferedERC1155WithERC20_ListOnChain_Adapter(config);

        buyOfferedERC1155WithERC20(config);
        buyOfferedERC1155WithERC20_Adapter(config);

        buyOfferedERC1155WithERC721_ListOnChain(config);
        buyOfferedERC1155WithERC721_ListOnChain_Adapter(config);

        buyOfferedERC1155WithERC721(config);
        buyOfferedERC1155WithERC721_Adapter(config);

        buyOfferedERC1155WithEther_ListOnChain(config);
        buyOfferedERC1155WithEther_ListOnChain_Adapter(config);

        buyOfferedERC1155WithEther(config);
        buyOfferedERC1155WithEther_Adapter(config);

        buyOfferedERC20WithERC1155_ListOnChain(config);
        buyOfferedERC20WithERC1155_ListOnChain_Adapter(config);

        buyOfferedERC20WithERC1155(config);
        buyOfferedERC20WithERC1155_Adapter(config);

        buyOfferedERC20WithERC721_ListOnChain(config);
        // There's an issue with resetting storage for sudo, to just reset
        // here.
        if (_sameName(config.name(), sudoswapConfig.name())) {
            beforeAllPrepareMarketplaceTest(config);
        }
        buyOfferedERC20WithERC721_ListOnChain_Adapter(config);

        buyOfferedERC20WithERC721(config);
        buyOfferedERC20WithERC721_Adapter(config);

        buyOfferedERC721WithERC1155_ListOnChain(config);
        buyOfferedERC721WithERC1155_ListOnChain_Adapter(config);

        buyOfferedERC721WithERC1155(config);
        buyOfferedERC721WithERC1155_Adapter(config);

        buyOfferedERC721WithERC20_ListOnChain(config);
        // There's an issue with resetting storage for sudo, to just reset
        // here.
        if (_sameName(config.name(), sudoswapConfig.name())) {
            beforeAllPrepareMarketplaceTest(config);
        }
        buyOfferedERC721WithERC20_ListOnChain_Adapter(config);

        buyOfferedERC721WithERC20(config);
        buyOfferedERC721WithERC20_Adapter(config);

        buyOfferedERC721WithEther(config);
        buyOfferedERC721WithEther_Adapter(config);

        buyOfferedERC721WithEther_ListOnChain(config);
        buyOfferedERC721WithEther_ListOnChain_Adapter(config);

        buyOfferedERC721WithEtherFee(config);
        buyOfferedERC721WithEtherFee_Adapter(config);

        buyOfferedERC721WithEtherFee_ListOnChain(config);
        buyOfferedERC721WithEtherFee_ListOnChain_Adapter(config);

        buyOfferedERC721WithEtherFeeTwoRecipients(config);
        buyOfferedERC721WithEtherFeeTwoRecipients_Adapter(config);

        buyOfferedERC721WithEtherFeeTwoRecipients_ListOnChain(config);
        buyOfferedERC721WithEtherFeeTwoRecipients_ListOnChain_Adapter(config);

        buyOfferedERC721WithWETH(config);
        buyOfferedERC721WithWETH_Adapter(config);

        buyOfferedERC721WithWETH_ListOnChain(config);
        buyOfferedERC721WithWETH_ListOnChain_Adapter(config);

        buyOfferedWETHWithERC721_ListOnChain(config);
        buyOfferedWETHWithERC721_ListOnChain_Adapter(config);

        buyOfferedWETHWithERC721(config);
        buyOfferedWETHWithERC721_Adapter(config);

        buyTenOfferedERC721WithErc20DistinctOrders_ListOnChain(config);
        buyTenOfferedERC721WithErc20DistinctOrders_ListOnChain_Adapter(config);

        buyTenOfferedERC721WithErc20DistinctOrders(config);
        buyTenOfferedERC721WithErc20DistinctOrders_Adapter(config);

        buyTenOfferedERC721WithEther(config);
        buyTenOfferedERC721WithEther_Adapter(config);

        buyTenOfferedERC721WithEther_ListOnChain(config);
        buyTenOfferedERC721WithEther_ListOnChain_Adapter(config);

        buyTenOfferedERC721WithEtherDistinctOrders(config);
        buyTenOfferedERC721WithEtherDistinctOrders_Adapter(config);

        buyTenOfferedERC721WithEtherDistinctOrders_ListOnChain(config);
        buyTenOfferedERC721WithEtherDistinctOrders_ListOnChain_Adapter(config);

        buyTenOfferedERC721WithWETHDistinctOrders(config);
        buyTenOfferedERC721WithWETHDistinctOrders_Adapter(config);

        buyTenOfferedERC721WithWETHDistinctOrders_ListOnChain(config);
        buyTenOfferedERC721WithWETHDistinctOrders_ListOnChain_Adapter(config);

        benchmark_MatchOrders_ABCA(config);
        benchmark_MatchOrders_ABCA_Adapter(config);
    }

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
        configs[3] = seaportOnePointFourConfig;
        benchmarkMixedIndividually(configs);
    }

    function benchmarkMixedIndividually(BaseMarketConfig[] memory configs)
        public
    {
        _doSetup();
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
        configs[3] = seaportOnePointFourConfig;
        benchmarkMixedIndividuallyThroughAdapter(configs);
    }

    function benchmarkMixedIndividuallyThroughAdapter(
        BaseMarketConfig[] memory configs
    ) public {
        _doSetup();
        _prepareMarketplaces(configs);

        uint256 firstOrderGasUsed =
            buyOfferedERC721WithEtherFee_ListOnChain_Adapter(configs[0]);
        uint256 secondOrderGasUsed =
            buyOfferedERC1155WithEther_ListOnChain_Adapter(configs[1]);
        uint256 thirdOrderGasUsed = buyOfferedERC721WithWETH_Adapter(configs[2]);
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
        configs[3] = seaportOnePointFourConfig;

        _doSetup();
        _prepareMarketplaces(configs);

        uint256 gasUsed = benchmarkMixedAggregatedThroughSeaport(configs);

        emit log_named_uint(
            "Total gas for fulfilling orders aggregated through Seaport",
            gasUsed
        );
    }

    struct BenchmarkAggregatedInfra {
        string testLabel;
        TestOrderContext context;
        TestCallParameters[] executionPayloads;
        AdvancedOrder[] adapterOrders;
        Fulfillment[] adapterFulfillments;
        CastOfCharacters castOfCharacters;
        Flashloan[] flashloans;
        ConsiderationItem[] considerationArray;
        TestItem721[] erc721s;
        TestItem1155[] erc1155s;
        TestItem1155 item1155;
        AdvancedOrder[] finalOrders;
        Fulfillment[] finalFulfillments;
    }

    function benchmarkMixedAggregatedThroughSeaport(
        BaseMarketConfig[] memory configs
    ) public prepareAggregationTest(configs) returns (uint256) {
        BenchmarkAggregatedInfra memory infra = BenchmarkAggregatedInfra(
            "Mixed aggregated through Seaport",
            TestOrderContext(
                true, true, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            new TestCallParameters[](3),
            new AdvancedOrder[](3),
            new Fulfillment[](2),
            stdCastOfCharacters,
            new Flashloan[](1),
            new ConsiderationItem[](1),
            new TestItem721[](1),
            new TestItem1155[](2),
            standardERC1155,
            new AdvancedOrder[](5),
            new Fulfillment[](4)
        );

        // Set up the orders. The Seaport order should be passed in normally,
        // and the rest will have to be put together in a big Call array.

        vm.deal(alice, 0);
        test721_1.mint(alice, 1);

        try configs[0].getPayload_BuyOfferedERC721WithEtherOneFeeRecipient(
            infra.context,
            standardERC721,
            500, // increased so that the fee recipient recieves 1%
            feeReciever1,
            5
        ) returns (TestOrderPayload memory payload) {
            // Fire off the actual prep call to ready the order.
            _benchmarkCallWithParams(
                configs[0].name(),
                string(abi.encodePacked(infra.testLabel, " List")),
                false,
                false,
                alice,
                payload.submitOrder
            );

            // Allow the market to escrow after listing
            assert(
                test721_1.ownerOf(1) == alice
                    || test721_1.ownerOf(1) == configs[0].market()
            );
            assertEq(feeReciever1.balance, 0);

            infra.executionPayloads[0] = payload.executeOrder;
        } catch {
            _logNotSupported(configs[0].name(), infra.testLabel);
        }

        test1155_1.mint(alice, 1, 1);

        try configs[1].getPayload_BuyOfferedERC1155WithEther(
            infra.context, infra.item1155, 100
        ) returns (TestOrderPayload memory payload) {
            _benchmarkCallWithParams(
                configs[1].name(),
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
            _logNotSupported(configs[1].name(), infra.testLabel);
        }

        infra.context = TestOrderContext(
            false, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        test721_1.mint(alice, 2);
        hevm.deal(bob, 100);
        hevm.prank(bob);
        weth.deposit{ value: 100 }();

        // Start with all buy offered NFT with X. But eventually test a mix of
        // offered X for NFT. The helper will need more detail about each NFT
        // transfer (sender, receiver, etc.)
        try configs[2].getPayload_BuyOfferedERC721WithWETH(
            infra.context, standardERC721Two, standardWeth
        ) returns (TestOrderPayload memory payload) {
            assertEq(test721_1.ownerOf(2), alice);
            assertEq(weth.balanceOf(bob), 100);
            assertEq(weth.balanceOf(alice), 0);

            infra.executionPayloads[2] = payload.executeOrder;
        } catch {
            _logNotSupported(configs[2].name(), infra.testLabel);
        }

        // Set up the aggregated orders.
        // Orders will be prime seaport order, flashloan, mirror, adapter.

        test1155_1.mint(alice, 2, 1);
        hevm.deal(bob, 100);
        test20.mint(bob, 100);

        assertEq(test20.balanceOf(bob), 100);
        assertEq(test20.balanceOf(alice), 0);

        infra.flashloans[0] = Flashloan({
            amount: 605,
            itemType: ItemType.NATIVE,
            shouldCallback: true,
            recipient: adapter
        });

        infra.erc721s[0] = standardERC721;
        infra.erc1155s[0] = standardERC1155;

        infra.considerationArray[0] = ConsiderationItemLib.fromDefault(
            "standardNativeConsiderationItem"
        ).withStartAmount(605).withEndAmount(605);

        // This should provide all the info required for the aggregated orders.
        (infra.adapterOrders, infra.adapterFulfillments) = AdapterHelperLib
            .createSeaportWrappedTestCallParametersReturnGranular(
            infra.executionPayloads,
            infra.castOfCharacters,
            infra.flashloans,
            infra.considerationArray,
            new TestItem20[](0),
            infra.erc721s,
            infra.erc1155s
        );

        AdvancedOrder memory orderOffer1155;
        AdvancedOrder memory orderConsider1155;

        {
            BasicOrderParameters memory params = configs[3]
                .getComponents_BuyOfferedERC1155WithERC20(
                alice, TestItem1155(_test1155Address, 2, 1), standardERC20
            );

            orderOffer1155 = _createSeaportOrder(params);

            params = configs[3].getComponents_BuyOfferedERC20WithERC1155(
                bob, standardERC20, TestItem1155(_test1155Address, 2, 1)
            );

            orderConsider1155 = _createSeaportOrder(params);
        }

        {
            infra.finalOrders[0] = infra.adapterOrders[0];
            infra.finalOrders[1] = infra.adapterOrders[1];
            infra.finalOrders[2] = infra.adapterOrders[2];
            infra.finalOrders[3] = orderOffer1155;
            infra.finalOrders[4] = orderConsider1155;
        }

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

        TestCallParameters memory finalCallParams;

        {
            finalCallParams = TestCallParameters(
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
            string(abi.encodePacked(infra.testLabel, " Fulfill aggregated")),
            true,
            false,
            bob,
            finalCallParams
        );

        // EXPECTED OUTCOMES
        // Bob should get the 721, 1
        // Bob should get the 721, 2
        assertEq(test721_1.ownerOf(1), bob, "Bob did not get the 721 1");
        assertEq(test721_1.ownerOf(2), bob, "Bob did not get the 721 2");

        // Bob should get the 1155, 1, 1
        // Bob should get the 1155, 2, 1
        assertEq(
            test1155_1.balanceOf(bob, 1), 1, "Bob did not get the 1155 1 1"
        );
        assertEq(
            test1155_1.balanceOf(bob, 2), 1, "Bob did not get the 1155 2 1"
        );

        // Alice gets 500 native
        // Alice gets 100 native
        // 575 after fees.
        assertEq(alice.balance, 575, "Alice did not get the native");

        // Fee reciever gets 5 native
        assertEq(feeReciever1.balance, 5);

        // Alice gets 100 wrapped
        assertEq(weth.balanceOf(alice), 100, "Alice did not get the wrapped");

        // Alice gets 100 test20
        assertEq(test20.balanceOf(alice), 100, "Alice did not get the test20");

        return gasUsed;
    }

    /*//////////////////////////////////////////////////////////////
                        Tests
    //////////////////////////////////////////////////////////////*/

    function buyOfferedERC721WithEther_ListOnChain(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(buyOfferedERC721WithEther_ListOnChain)";
        test721_1.mint(alice, 1);
        try config.getPayload_BuyOfferedERC721WithEther(
            TestOrderContext(
                true, false, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            standardERC721,
            100
        ) returns (TestOrderPayload memory payload) {
            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
                false,
                false,
                alice,
                payload.submitOrder
            );

            // Allow the market to escrow after listing
            assert(
                test721_1.ownerOf(1) == alice
                    || test721_1.ownerOf(1) == config.market()
            );

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill")),
                true,
                false,
                bob,
                payload.executeOrder
            );

            assertEq(test721_1.ownerOf(1), bob);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyOfferedERC721WithEther_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(buyOfferedERC721WithEther_ListOnChain_Adapter)";
        test721_1.mint(alice, 1);

        TestOrderContext memory context = TestOrderContext(
            true, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        try config.getPayload_BuyOfferedERC721WithEther(
            context, standardERC721, 100
        ) returns (TestOrderPayload memory payload) {
            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
                false,
                false,
                alice,
                payload.submitOrder
            );

            // Allow the market to escrow after listing
            assert(
                test721_1.ownerOf(1) == alice
                    || test721_1.ownerOf(1) == config.market()
            );

            Flashloan memory flashloan = Flashloan({
                amount: 100,
                itemType: ItemType.NATIVE,
                shouldCallback: true,
                recipient: adapter
            });

            Flashloan[] memory flashloanArray = new Flashloan[](1);
            flashloanArray[0] = flashloan;

            TestItem721[] memory items;

            if (_sameName(config.name(), sudoswapConfig.name())) {
                items = new TestItem721[](0);
            } else {
                items = new TestItem721[](1);
                items[0] = standardERC721;
            }

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedTestCallParameters(
                stdCastOfCharacters,
                flashloanArray,
                ConsiderationItemLib.fromDefaultMany(
                    "standardNativeConsiderationArray"
                ),
                items
            );

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill*")),
                true,
                true,
                bob,
                payload.executeOrder
            );

            assertEq(test721_1.ownerOf(1), bob);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyOfferedERC721WithEther(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(buyOfferedERC721WithEther)";
        test721_1.mint(alice, 1);
        try config.getPayload_BuyOfferedERC721WithEther(
            TestOrderContext(
                false, false, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            standardERC721,
            100
        ) returns (TestOrderPayload memory payload) {
            assertEq(test721_1.ownerOf(1), alice);

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill, w/ Sig")),
                true,
                false,
                bob,
                payload.executeOrder
            );

            assertEq(test721_1.ownerOf(1), bob);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyOfferedERC721WithEther_Adapter(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(buyOfferedERC721WithEther_Adapter)";
        test721_1.mint(alice, 1);

        TestOrderContext memory context = TestOrderContext(
            false, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        // LR and X2Y2 require that the msg.sender is also the taker.
        // This just causes Blur to fail silently instead of loudly.
        if (
            _sameName(config.name(), looksRareConfig.name())
                || _sameName(config.name(), x2y2Config.name())
                || _sameName(config.name(), blurConfig.name())
        ) {
            context.fulfiller = sidecar;
        }

        try config.getPayload_BuyOfferedERC721WithEther(
            context, standardERC721, 100
        ) returns (TestOrderPayload memory payload) {
            context.fulfiller = bob;

            assertEq(test721_1.ownerOf(1), alice);

            Flashloan memory flashloan = Flashloan({
                amount: 100,
                itemType: ItemType.NATIVE,
                shouldCallback: true,
                recipient: adapter
            });

            Flashloan[] memory flashloanArray = new Flashloan[](1);
            flashloanArray[0] = flashloan;

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedTestCallParameters(
                stdCastOfCharacters,
                flashloanArray,
                ConsiderationItemLib.fromDefaultMany(
                    "standardNativeConsiderationArray"
                ),
                standardERC721
            );

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill, w/ Sig*")),
                true,
                true,
                bob,
                payload.executeOrder
            );

            assertEq(test721_1.ownerOf(1), bob);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyOfferedERC1155WithEther_ListOnChain(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(buyOfferedERC1155WithEther_ListOnChain)";
        test1155_1.mint(alice, 1, 1);
        try config.getPayload_BuyOfferedERC1155WithEther(
            TestOrderContext(
                true, false, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            standardERC1155,
            100
        ) returns (TestOrderPayload memory payload) {
            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
                false,
                false,
                alice,
                payload.submitOrder
            );

            assertEq(test1155_1.balanceOf(alice, 1), 1);
            assertEq(test1155_1.balanceOf(bob, 1), 0);

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill")),
                true,
                false,
                bob,
                payload.executeOrder
            );

            assertEq(test1155_1.balanceOf(alice, 1), 0);
            assertEq(test1155_1.balanceOf(bob, 1), 1);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyOfferedERC1155WithEther_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(buyOfferedERC1155WithEther_ListOnChain_Adapter)";
        test1155_1.mint(alice, 1, 1);

        TestOrderContext memory context = TestOrderContext(
            true, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        try config.getPayload_BuyOfferedERC1155WithEther(
            context, standardERC1155, 100
        ) returns (TestOrderPayload memory payload) {
            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
                false,
                false,
                alice,
                payload.submitOrder
            );

            assertEq(test1155_1.balanceOf(alice, 1), 1);
            assertEq(test1155_1.balanceOf(bob, 1), 0);

            Flashloan memory flashloan = Flashloan({
                amount: 100,
                itemType: ItemType.NATIVE,
                shouldCallback: true,
                recipient: adapter
            });

            Flashloan[] memory flashloanArray = new Flashloan[](1);
            flashloanArray[0] = flashloan;

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedTestCallParameters(
                stdCastOfCharacters,
                flashloanArray,
                ConsiderationItemLib.fromDefaultMany(
                    "standardNativeConsiderationArray"
                ),
                standardERC1155
            );

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill*")),
                true,
                true,
                bob,
                payload.executeOrder
            );

            assertEq(test1155_1.balanceOf(alice, 1), 0);
            assertEq(test1155_1.balanceOf(bob, 1), 1);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyOfferedERC1155WithEther(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(buyOfferedERC1155WithEther)";
        test1155_1.mint(alice, 1, 1);
        try config.getPayload_BuyOfferedERC1155WithEther(
            TestOrderContext(
                false, false, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            standardERC1155,
            100
        ) returns (TestOrderPayload memory payload) {
            assertEq(test1155_1.balanceOf(alice, 1), 1);

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill, w/ Sig")),
                true,
                false,
                bob,
                payload.executeOrder
            );

            assertEq(test1155_1.balanceOf(bob, 1), 1);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyOfferedERC1155WithEther_Adapter(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(buyOfferedERC1155WithEther_Adapter)";
        test1155_1.mint(alice, 1, 1);

        TestOrderContext memory context = TestOrderContext(
            false, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        // LR and X2Y2 require that the msg.sender is also the taker.
        if (
            _sameName(config.name(), looksRareConfig.name())
                || _sameName(config.name(), x2y2Config.name())
        ) {
            context.fulfiller = sidecar;
        }

        try config.getPayload_BuyOfferedERC1155WithEther(
            context, standardERC1155, 100
        ) returns (TestOrderPayload memory payload) {
            context.fulfiller = bob;
            assertEq(test1155_1.balanceOf(alice, 1), 1);

            Flashloan memory flashloan = Flashloan({
                amount: 100,
                itemType: ItemType.NATIVE,
                shouldCallback: true,
                recipient: adapter
            });

            Flashloan[] memory flashloanArray = new Flashloan[](1);
            flashloanArray[0] = flashloan;

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedTestCallParameters(
                stdCastOfCharacters,
                flashloanArray,
                ConsiderationItemLib.fromDefaultMany(
                    "standardNativeConsiderationArray"
                ),
                standardERC1155
            );

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill, w/ Sig*")),
                true,
                true,
                bob,
                payload.executeOrder
            );

            assertEq(test1155_1.balanceOf(bob, 1), 1);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyOfferedERC721WithERC20_ListOnChain(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(buyOfferedERC721WithERC20_ListOnChain)";
        test721_1.mint(alice, 1);
        test20.mint(bob, 100);
        try config.getPayload_BuyOfferedERC721WithERC20(
            TestOrderContext(
                true, false, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            standardERC721,
            standardERC20
        ) returns (TestOrderPayload memory payload) {
            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
                false,
                false,
                alice,
                payload.submitOrder
            );

            // Allow the market to escrow after listing
            assert(
                test721_1.ownerOf(1) == alice
                    || test721_1.ownerOf(1) == config.market()
            );
            assertEq(test20.balanceOf(alice), 0);
            assertEq(test20.balanceOf(bob), 100);

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill")),
                true,
                false,
                bob,
                payload.executeOrder
            );

            assertEq(test721_1.ownerOf(1), bob);
            assertEq(test20.balanceOf(alice), 100);
            assertEq(test20.balanceOf(bob), 0);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyOfferedERC721WithERC20_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(buyOfferedERC721WithERC20_ListOnChain_Adapter)";

        TestOrderContext memory context = TestOrderContext(
            true, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        if (
            _sameName(config.name(), looksRareConfig.name())
                || _sameName(config.name(), x2y2Config.name())
        ) {
            context.fulfiller = sidecar;
        }

        test721_1.mint(alice, 1);
        test20.mint(bob, 100);

        try config.getPayload_BuyOfferedERC721WithERC20(
            TestOrderContext(
                true, true, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            standardERC721,
            standardERC20
        ) returns (TestOrderPayload memory payload) {
            context.fulfiller = bob;
            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
                false,
                false,
                alice,
                payload.submitOrder
            );

            // Allow the market to escrow after listing
            assert(
                test721_1.ownerOf(1) == alice
                    || test721_1.ownerOf(1) == config.market()
            );
            assertEq(test20.balanceOf(alice), 0);
            assertEq(test20.balanceOf(bob), 100);

            TestItem721[] memory erc721s;

            erc721s = new TestItem721[](1);

            if (_sameName(config.name(), sudoswapConfig.name())) {
                erc721s = new TestItem721[](0);
            } else {
                erc721s[0] = standardERC721;
            }

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedTestCallParameters(
                stdCastOfCharacters,
                ConsiderationItemLib.fromDefaultMany(
                    "standardERC20ConsiderationArray"
                ),
                erc721s
            );

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill*")),
                true,
                true,
                bob,
                payload.executeOrder
            );

            assertEq(test721_1.ownerOf(1), bob);
            assertEq(test20.balanceOf(alice), 100, "Alice did not get paid");
            assertEq(test20.balanceOf(bob), 0, "Bob did not pay");
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyOfferedERC721WithERC20(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(buyOfferedERC721WithERC20)";
        test721_1.mint(alice, 1);
        test20.mint(bob, 100);
        try config.getPayload_BuyOfferedERC721WithERC20(
            TestOrderContext(
                false, false, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            standardERC721,
            standardERC20
        ) returns (TestOrderPayload memory payload) {
            assertEq(test721_1.ownerOf(1), alice);
            assertEq(test20.balanceOf(alice), 0);
            assertEq(test20.balanceOf(bob), 100);

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill, w/ Sig")),
                true,
                false,
                bob,
                payload.executeOrder
            );

            assertEq(test721_1.ownerOf(1), bob);
            assertEq(test20.balanceOf(alice), 100);
            assertEq(test20.balanceOf(bob), 0);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyOfferedERC721WithERC20_Adapter(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(buyOfferedERC721WithERC20_Adapter)";

        TestOrderContext memory context = TestOrderContext(
            false, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        if (
            _sameName(config.name(), x2y2Config.name())
                || _sameName(config.name(), looksRareConfig.name())
        ) {
            context.fulfiller = sidecar;
        }

        test721_1.mint(alice, 1);
        test20.mint(bob, 100);
        try config.getPayload_BuyOfferedERC721WithERC20(
            context, standardERC721, standardERC20
        ) returns (TestOrderPayload memory payload) {
            // Put the context back.
            context.fulfiller = bob;

            assertEq(test721_1.ownerOf(1), alice);
            assertEq(test20.balanceOf(alice), 0);
            assertEq(test20.balanceOf(bob), 100);

            TestItem721[] memory erc721s;

            erc721s = new TestItem721[](1);
            erc721s[0] = standardERC721;

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedTestCallParameters(
                stdCastOfCharacters,
                ConsiderationItemLib.fromDefaultMany(
                    "standardERC20ConsiderationArray"
                ),
                erc721s
            );

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill, w/ Sig*")),
                true,
                true,
                bob,
                payload.executeOrder
            );

            assertEq(test721_1.ownerOf(1), bob, "Bob did not get NFT");
            assertEq(test20.balanceOf(alice), 100, "Alice did not get ERC20");
            assertEq(test20.balanceOf(bob), 0);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyOfferedERC721WithWETH_ListOnChain(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(buyOfferedERC721WithWETH_ListOnChain)";
        test721_1.mint(alice, 1);
        hevm.deal(bob, 100);
        hevm.prank(bob);
        weth.deposit{ value: 100 }();
        try config.getPayload_BuyOfferedERC721WithERC20(
            TestOrderContext(
                true, false, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            standardERC721,
            standardWeth
        ) returns (TestOrderPayload memory payload) {
            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
                false,
                false,
                alice,
                payload.submitOrder
            );

            // Allow the market to escrow after listing
            assert(
                test721_1.ownerOf(1) == alice
                    || test721_1.ownerOf(1) == config.market()
            );
            assertEq(weth.balanceOf(alice), 0);
            assertEq(weth.balanceOf(bob), 100);

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill")),
                true,
                false,
                bob,
                payload.executeOrder
            );

            assertEq(test721_1.ownerOf(1), bob);
            assertEq(weth.balanceOf(alice), 100);
            assertEq(weth.balanceOf(bob), 0);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyOfferedERC721WithWETH_Adapter(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(buyOfferedERC721WithWETH_Adapter)";

        test721_1.mint(alice, 1);
        hevm.deal(bob, 100);
        hevm.prank(bob);
        weth.deposit{ value: 100 }();

        TestOrderContext memory context = TestOrderContext(
            false, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        if (
            _sameName(config.name(), x2y2Config.name())
                || _sameName(config.name(), looksRareConfig.name())
        ) {
            context.fulfiller = sidecar;
        }

        try config.getPayload_BuyOfferedERC721WithWETH(
            context, standardERC721, standardWeth
        ) returns (TestOrderPayload memory payload) {
            // Put the context back.
            context.fulfiller = bob;

            assertEq(test721_1.ownerOf(1), alice);
            assertEq(weth.balanceOf(alice), 0);
            assertEq(weth.balanceOf(bob), 100);

            ConsiderationItem[] memory adapterOrderConsideration =
            ConsiderationItemLib.fromDefaultMany(
                "standardWethConsiderationArray"
            );

            TestItem721[] memory erc721s = new TestItem721[](1);
            erc721s[0] = standardERC721;

            if (_sameName(config.name(), blurConfig.name())) {
                adapterOrderConsideration = new ConsiderationItem[](0);
                erc721s = new TestItem721[](0);
            }

            vm.prank(sidecar);
            weth.approve(sidecar, type(uint256).max);

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedTestCallParameters(
                stdCastOfCharacters, adapterOrderConsideration, erc721s
            );

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill, w/ Sig*")),
                true,
                true,
                bob,
                payload.executeOrder
            );

            assertEq(test721_1.ownerOf(1), bob);
            assertEq(weth.balanceOf(alice), 100);
            assertEq(weth.balanceOf(bob), 0);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyOfferedERC721WithWETH_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(buyOfferedERC721WithWETH_ListOnChain_Adapter)";

        test721_1.mint(alice, 1);
        hevm.deal(bob, 100);
        hevm.prank(bob);
        weth.deposit{ value: 100 }();

        TestOrderContext memory context = TestOrderContext(
            true, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        // TODO: Come back and see if there's a way to make this work.
        if (
            _sameName(config.name(), looksRareConfig.name())
                || _sameName(config.name(), x2y2Config.name())
        ) {
            context.fulfiller = sidecar;
        }

        try config.getPayload_BuyOfferedERC721WithERC20(
            context, standardERC721, standardWeth
        ) returns (TestOrderPayload memory payload) {
            context.fulfiller = bob;

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
                false,
                false,
                alice,
                payload.submitOrder
            );

            // Allow the market to escrow after listing
            assert(
                test721_1.ownerOf(1) == alice
                    || test721_1.ownerOf(1) == config.market()
            );
            assertEq(weth.balanceOf(alice), 0);
            assertEq(weth.balanceOf(bob), 100);

            ConsiderationItem[] memory adapterOrderConsideration =
            ConsiderationItemLib.fromDefaultMany(
                "standardWethConsiderationArray"
            );

            TestItem721[] memory erc721s = new TestItem721[](1);
            erc721s[0] = standardERC721;

            if (_sameName(config.name(), blurConfig.name())) {
                adapterOrderConsideration = new ConsiderationItem[](0);
                erc721s = new TestItem721[](0);
            }

            vm.prank(sidecar);
            weth.approve(sidecar, type(uint256).max);

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedTestCallParameters(
                stdCastOfCharacters, adapterOrderConsideration, erc721s
            );

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill*")),
                true,
                true,
                bob,
                payload.executeOrder
            );

            assertEq(test721_1.ownerOf(1), bob);
            assertEq(weth.balanceOf(alice), 100);
            assertEq(weth.balanceOf(bob), 0);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyOfferedERC721WithWETH(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(buyOfferedERC721WithWETH)";
        test721_1.mint(alice, 1);
        hevm.deal(bob, 100);
        hevm.prank(bob);
        weth.deposit{ value: 100 }();

        try config.getPayload_BuyOfferedERC721WithWETH(
            TestOrderContext(
                false, false, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            standardERC721,
            standardWeth
        ) returns (TestOrderPayload memory payload) {
            assertEq(test721_1.ownerOf(1), alice);
            assertEq(weth.balanceOf(alice), 0);
            assertEq(weth.balanceOf(bob), 100);

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill, w/ Sig")),
                true,
                false,
                bob,
                payload.executeOrder
            );

            assertEq(test721_1.ownerOf(1), bob);
            assertEq(weth.balanceOf(alice), 100);
            assertEq(weth.balanceOf(bob), 0);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyOfferedERC1155WithERC20_ListOnChain(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(buyOfferedERC1155WithERC20_ListOnChain)";
        test1155_1.mint(alice, 1, 1);
        test20.mint(bob, 100);
        try config.getPayload_BuyOfferedERC1155WithERC20(
            TestOrderContext(
                true, false, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            standardERC1155,
            standardERC20
        ) returns (TestOrderPayload memory payload) {
            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
                false,
                false,
                alice,
                payload.submitOrder
            );

            assertEq(test1155_1.balanceOf(alice, 1), 1);
            assertEq(test20.balanceOf(alice), 0);
            assertEq(test20.balanceOf(bob), 100);

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill")),
                true,
                false,
                bob,
                payload.executeOrder
            );

            assertEq(test1155_1.balanceOf(bob, 1), 1);
            assertEq(test20.balanceOf(alice), 100);
            assertEq(test20.balanceOf(bob), 0);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyOfferedERC1155WithERC20_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(buyOfferedERC1155WithERC20_ListOnChain_Adapter)";

        TestOrderContext memory context = TestOrderContext(
            true, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        test1155_1.mint(alice, 1, 1);
        test20.mint(bob, 100);
        try config.getPayload_BuyOfferedERC1155WithERC20(
            context, standardERC1155, standardERC20
        ) returns (TestOrderPayload memory payload) {
            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
                false,
                false,
                alice,
                payload.submitOrder
            );

            assertEq(test1155_1.balanceOf(alice, 1), 1);
            assertEq(test20.balanceOf(alice), 0);
            assertEq(test20.balanceOf(bob), 100);

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedTestCallParameters(
                stdCastOfCharacters,
                ConsiderationItemLib.fromDefaultMany(
                    "standardERC20ConsiderationArray"
                ),
                standardERC1155
            );

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill*")),
                true,
                true,
                bob,
                payload.executeOrder
            );

            assertEq(test1155_1.balanceOf(bob, 1), 1);
            assertEq(test20.balanceOf(alice), 100);
            assertEq(test20.balanceOf(bob), 0);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyOfferedERC1155WithERC20(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(buyOfferedERC1155WithERC20)";
        test1155_1.mint(alice, 1, 1);
        test20.mint(bob, 100);
        try config.getPayload_BuyOfferedERC1155WithERC20(
            TestOrderContext(
                false, false, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            standardERC1155,
            standardERC20
        ) returns (TestOrderPayload memory payload) {
            assertEq(test1155_1.balanceOf(alice, 1), 1);
            assertEq(test20.balanceOf(alice), 0);
            assertEq(test20.balanceOf(bob), 100);

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill w/ Sig")),
                true,
                false,
                bob,
                payload.executeOrder
            );

            assertEq(test1155_1.balanceOf(bob, 1), 1);
            assertEq(test20.balanceOf(alice), 100);
            assertEq(test20.balanceOf(bob), 0);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyOfferedERC1155WithERC20_Adapter(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(buyOfferedERC1155WithERC20_Adapter)";

        TestOrderContext memory context = TestOrderContext(
            false, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        // Cheat the context for LR.
        if (_sameName(config.name(), looksRareConfig.name())) {
            context.fulfiller = sidecar;
        }

        test1155_1.mint(alice, 1, 1);
        test20.mint(bob, 100);
        try config.getPayload_BuyOfferedERC1155WithERC20(
            context, standardERC1155, standardERC20
        ) returns (TestOrderPayload memory payload) {
            // Put the context back.
            context.fulfiller = bob;

            assertEq(test1155_1.balanceOf(alice, 1), 1);
            assertEq(test20.balanceOf(alice), 0);
            assertEq(test20.balanceOf(bob), 100);

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedTestCallParameters(
                stdCastOfCharacters,
                ConsiderationItemLib.fromDefaultMany(
                    "standardERC20ConsiderationArray"
                ),
                standardERC1155
            );

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill w/ Sig*")),
                true,
                true,
                bob,
                payload.executeOrder
            );

            assertEq(test1155_1.balanceOf(bob, 1), 1);
            assertEq(test20.balanceOf(alice), 100);
            assertEq(test20.balanceOf(bob), 0);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyOfferedERC20WithERC721_ListOnChain(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(buyOfferedERC20WithERC721_ListOnChain)";
        test20.mint(alice, 100);
        test721_1.mint(bob, 1);
        try config.getPayload_BuyOfferedERC20WithERC721(
            TestOrderContext(
                true, false, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            standardERC20,
            standardERC721
        ) returns (TestOrderPayload memory payload) {
            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
                false,
                false,
                alice,
                payload.submitOrder
            );

            assertEq(test721_1.ownerOf(1), bob);
            // Allow the market to escrow after listing
            assert(
                test20.balanceOf(alice) == 100
                    || test20.balanceOf(config.market()) == 100
            );
            assertEq(test20.balanceOf(bob), 0);

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill")),
                true,
                false,
                bob,
                payload.executeOrder
            );

            assertEq(test721_1.ownerOf(1), alice);
            assertEq(test20.balanceOf(alice), 0);
            assertEq(test20.balanceOf(bob), 100);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyOfferedERC20WithERC721_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(buyOfferedERC20WithERC721_ListOnChain_Adapter)";

        TestOrderContext memory context = TestOrderContext(
            true, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        if (_sameName(config.name(), x2y2Config.name())) {
            context.fulfiller = sidecar;
        }

        test20.mint(alice, 100);
        test721_1.mint(bob, 1);
        try config.getPayload_BuyOfferedERC20WithERC721(
            context, standardERC20, standardERC721
        ) returns (TestOrderPayload memory payload) {
            context.fulfiller = bob;
            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
                false,
                false,
                alice,
                payload.submitOrder
            );

            assertEq(test721_1.ownerOf(1), bob);
            // Allow the market to escrow after listing
            assert(
                test20.balanceOf(alice) == 100
                    || test20.balanceOf(config.market()) == 100
            );
            assertEq(test20.balanceOf(bob), 0);

            TestItem20[] memory erc20s = new TestItem20[](1);
            erc20s[0] = standardERC20;

            if (_sameName(config.name(), sudoswapConfig.name())) {
                erc20s = new TestItem20[](0);
            }

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedTestCallParameters(
                stdCastOfCharacters,
                ConsiderationItemLib.fromDefaultMany(
                    "standardERC721ConsiderationArray"
                ),
                erc20s
            );

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill*")),
                true,
                true,
                bob,
                payload.executeOrder
            );

            assertEq(test721_1.ownerOf(1), alice, "Alice should own the NFT");
            assertEq(test20.balanceOf(alice), 0, "Alice should have no ERC20");
            assertEq(test20.balanceOf(bob), 100, "Bob should have the ERC20");
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyOfferedERC20WithERC721(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(buyOfferedERC20WithERC721)";
        test20.mint(alice, 100);
        test721_1.mint(bob, 1);
        try config.getPayload_BuyOfferedERC20WithERC721(
            TestOrderContext(
                false, false, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            standardERC20,
            standardERC721
        ) returns (TestOrderPayload memory payload) {
            assertEq(test721_1.ownerOf(1), bob);
            assertEq(test20.balanceOf(alice), 100);
            assertEq(test20.balanceOf(bob), 0);

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill w/ Sig")),
                true,
                false,
                bob,
                payload.executeOrder
            );

            assertEq(test721_1.ownerOf(1), alice);
            assertEq(test20.balanceOf(alice), 0);
            assertEq(test20.balanceOf(bob), 100);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyOfferedERC20WithERC721_Adapter(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(buyOfferedERC20WithERC721_Adapter)";

        TestOrderContext memory context = TestOrderContext(
            false, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        // Cheat the context for LR and X2Y2.
        if (
            _sameName(config.name(), looksRareConfig.name())
                || _sameName(config.name(), x2y2Config.name())
        ) {
            context.fulfiller = sidecar;
        }

        test20.mint(alice, 100);
        test721_1.mint(bob, 1);
        try config.getPayload_BuyOfferedERC20WithERC721(
            context, standardERC20, standardERC721
        ) returns (TestOrderPayload memory payload) {
            // Put the context back.
            context.fulfiller = bob;

            assertEq(test721_1.ownerOf(1), bob);
            assertEq(test20.balanceOf(alice), 100);
            assertEq(test20.balanceOf(bob), 0);

            TestItem20[] memory erc20s = new TestItem20[](1);
            erc20s[0] = standardERC20;

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedTestCallParameters(
                stdCastOfCharacters,
                ConsiderationItemLib.fromDefaultMany(
                    "standardERC721ConsiderationArray"
                ),
                erc20s
            );

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill w/ Sig*")),
                true,
                true,
                bob,
                payload.executeOrder
            );

            assertEq(test721_1.ownerOf(1), alice);
            assertEq(test20.balanceOf(alice), 0);
            assertEq(test20.balanceOf(bob), 100);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyOfferedWETHWithERC721_ListOnChain(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(buyOfferedWETHWithERC721_ListOnChain)";
        hevm.deal(alice, 100);
        hevm.prank(alice);
        weth.deposit{ value: 100 }();
        test721_1.mint(bob, 1);
        try config.getPayload_BuyOfferedWETHWithERC721(
            TestOrderContext(
                true, false, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            standardWeth,
            standardERC721
        ) returns (TestOrderPayload memory payload) {
            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
                false,
                false,
                alice,
                payload.submitOrder
            );

            assertEq(test721_1.ownerOf(1), bob);
            // Allow the market to escrow after listing
            assert(
                weth.balanceOf(alice) == 100
                    || weth.balanceOf(config.market()) == 100
            );
            assertEq(weth.balanceOf(bob), 0);

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill")),
                true,
                false,
                bob,
                payload.executeOrder
            );

            assertEq(test721_1.ownerOf(1), alice);
            assertEq(weth.balanceOf(alice), 0);
            assertEq(weth.balanceOf(bob), 100);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyOfferedWETHWithERC721_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(buyOfferedWETHWithERC721_ListOnChain_Adapter)";

        TestOrderContext memory context = TestOrderContext(
            true, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        hevm.deal(alice, 100);
        hevm.prank(alice);
        weth.deposit{ value: 100 }();
        test721_1.mint(bob, 1);

        try config.getPayload_BuyOfferedWETHWithERC721(
            context, standardWeth, standardERC721
        ) returns (TestOrderPayload memory payload) {
            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
                false,
                false,
                alice,
                payload.submitOrder
            );

            assertEq(test721_1.ownerOf(1), bob);
            // Allow the market to escrow after listing
            assert(
                weth.balanceOf(alice) == 100
                    || weth.balanceOf(config.market()) == 100
            );
            assertEq(weth.balanceOf(bob), 0);

            TestItem20[] memory erc20s = new TestItem20[](1);
            erc20s[0] = standardWeth;

            // Look into why test20 requires an explicit approval lol.
            vm.prank(sidecar);
            weth.approve(sidecar, 100);

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedTestCallParameters(
                stdCastOfCharacters,
                ConsiderationItemLib.fromDefaultMany(
                    "standardERC721ConsiderationArray"
                ),
                erc20s
            );

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill*")),
                true,
                true,
                bob,
                payload.executeOrder
            );

            assertEq(test721_1.ownerOf(1), alice);
            assertEq(weth.balanceOf(alice), 0);
            assertEq(weth.balanceOf(bob), 100);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyOfferedWETHWithERC721(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(buyOfferedWETHWithERC721)";
        hevm.deal(alice, 100);
        hevm.prank(alice);
        weth.deposit{ value: 100 }();
        test721_1.mint(bob, 1);
        try config.getPayload_BuyOfferedWETHWithERC721(
            TestOrderContext(
                false, false, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            standardWeth,
            standardERC721
        ) returns (TestOrderPayload memory payload) {
            assertEq(test721_1.ownerOf(1), bob);
            assertEq(weth.balanceOf(alice), 100);
            assertEq(weth.balanceOf(bob), 0);

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill w/ Sig")),
                true,
                false,
                bob,
                payload.executeOrder
            );

            assertEq(test721_1.ownerOf(1), alice);
            assertEq(weth.balanceOf(alice), 0);
            assertEq(weth.balanceOf(bob), 100);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyOfferedWETHWithERC721_Adapter(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(buyOfferedWETHWithERC721_Adapter)";

        TestOrderContext memory context = TestOrderContext(
            false, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        if (
            _sameName(config.name(), looksRareConfig.name())
                || _sameName(config.name(), x2y2Config.name())
        ) {
            context.fulfiller = sidecar;
        }

        hevm.deal(alice, 100);
        hevm.prank(alice);
        weth.deposit{ value: 100 }();
        test721_1.mint(bob, 1);
        try config.getPayload_BuyOfferedWETHWithERC721(
            context, standardWeth, standardERC721
        ) returns (TestOrderPayload memory payload) {
            context.fulfiller = bob;

            assertEq(test721_1.ownerOf(1), bob);
            assertEq(weth.balanceOf(alice), 100);
            assertEq(weth.balanceOf(bob), 0);

            if (_sameName(config.name(), blurConfig.name())) {
                payload.executeOrder = payload
                    .executeOrder
                    .createSeaportWrappedTestCallParameters(
                    stdCastOfCharacters,
                    new ConsiderationItem[](0),
                    new TestItem721[](0)
                );
            } else {
                TestItem20[] memory erc20s = new TestItem20[](1);
                erc20s[0] = standardWeth;

                // Look into why test20 requires an explicit approval lol.
                vm.prank(sidecar);
                weth.approve(sidecar, 100);

                payload.executeOrder = payload
                    .executeOrder
                    .createSeaportWrappedTestCallParameters(
                    stdCastOfCharacters,
                    ConsiderationItemLib.fromDefaultMany(
                        "standardERC721ConsiderationArray"
                    ),
                    erc20s
                );
            }

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill w/ Sig*")),
                true,
                true,
                bob,
                payload.executeOrder
            );

            assertEq(test721_1.ownerOf(1), alice);
            assertEq(weth.balanceOf(alice), 0);
            assertEq(weth.balanceOf(bob), 100);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyOfferedERC20WithERC1155_ListOnChain(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(buyOfferedERC20WithERC1155_ListOnChain)";
        TestOrderContext memory context = TestOrderContext(
            true, false, alice, bob, flashloanOfferer, adapter, sidecar
        );
        test20.mint(alice, 100);
        test1155_1.mint(bob, 1, 1);
        try config.getPayload_BuyOfferedERC20WithERC1155(
            context, standardERC20, standardERC1155
        ) returns (TestOrderPayload memory payload) {
            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
                false,
                false,
                alice,
                payload.submitOrder
            );

            assertEq(test1155_1.balanceOf(bob, 1), 1);
            assertEq(test20.balanceOf(alice), 100);
            assertEq(test20.balanceOf(bob), 0);

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill")),
                true,
                false,
                bob,
                payload.executeOrder
            );

            assertEq(test1155_1.balanceOf(alice, 1), 1);
            assertEq(test20.balanceOf(alice), 0);
            assertEq(test20.balanceOf(bob), 100);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyOfferedERC20WithERC1155_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(buyOfferedERC20WithERC1155_ListOnChain_Adapter)";

        TestOrderContext memory context = TestOrderContext(
            true, true, alice, bob, flashloanOfferer, adapter, sidecar
        );
        test20.mint(alice, 100);
        test1155_1.mint(bob, 1, 1);
        try config.getPayload_BuyOfferedERC20WithERC1155(
            context, standardERC20, standardERC1155
        ) returns (TestOrderPayload memory payload) {
            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
                false,
                false,
                alice,
                payload.submitOrder
            );

            assertEq(test1155_1.balanceOf(bob, 1), 1);
            assertEq(test20.balanceOf(alice), 100);
            assertEq(test20.balanceOf(bob), 0);

            TestItem20[] memory erc20s = new TestItem20[](1);
            erc20s[0] = standardERC20;

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedTestCallParameters(
                stdCastOfCharacters,
                ConsiderationItemLib.fromDefaultMany(
                    "standardERC1155ConsiderationArray"
                ),
                erc20s
            );

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill*")),
                true,
                true,
                bob,
                payload.executeOrder
            );

            assertEq(test1155_1.balanceOf(alice, 1), 1);
            assertEq(test20.balanceOf(alice), 0);
            assertEq(test20.balanceOf(bob), 100);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyOfferedERC20WithERC1155(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(buyOfferedERC20WithERC1155)";
        TestOrderContext memory context = TestOrderContext(
            false, false, alice, bob, flashloanOfferer, adapter, sidecar
        );
        test20.mint(alice, 100);
        test1155_1.mint(bob, 1, 1);
        try config.getPayload_BuyOfferedERC20WithERC1155(
            context, standardERC20, standardERC1155
        ) returns (TestOrderPayload memory payload) {
            assertEq(test1155_1.balanceOf(bob, 1), 1);
            assertEq(test20.balanceOf(alice), 100);
            assertEq(test20.balanceOf(bob), 0);

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill w/ Sig")),
                true,
                false,
                bob,
                payload.executeOrder
            );

            assertEq(test1155_1.balanceOf(alice, 1), 1);
            assertEq(test20.balanceOf(alice), 0);
            assertEq(test20.balanceOf(bob), 100);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyOfferedERC20WithERC1155_Adapter(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(buyOfferedERC20WithERC1155_Adapter)";

        TestOrderContext memory context = TestOrderContext(
            false, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        // Cheat the context for LR.
        if (_sameName(config.name(), looksRareConfig.name())) {
            context.fulfiller = sidecar;
        }

        test20.mint(alice, 100);
        test1155_1.mint(bob, 1, 1);
        try config.getPayload_BuyOfferedERC20WithERC1155(
            context, standardERC20, standardERC1155
        ) returns (TestOrderPayload memory payload) {
            // Put the context back.
            context.fulfiller = bob;

            assertEq(test1155_1.balanceOf(bob, 1), 1);
            assertEq(test20.balanceOf(alice), 100);
            assertEq(test20.balanceOf(bob), 0);

            TestItem20[] memory erc20s = new TestItem20[](1);
            erc20s[0] = standardERC20;

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedTestCallParameters(
                stdCastOfCharacters,
                ConsiderationItemLib.fromDefaultMany(
                    "standardERC1155ConsiderationArray"
                ),
                erc20s
            );

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill w/ Sig*")),
                true,
                true,
                bob,
                payload.executeOrder
            );

            assertEq(test1155_1.balanceOf(alice, 1), 1);
            assertEq(test20.balanceOf(alice), 0);
            assertEq(test20.balanceOf(bob), 100);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyOfferedERC721WithERC1155_ListOnChain(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(buyOfferedERC721WithERC1155_ListOnChain)";
        TestOrderContext memory context = TestOrderContext(
            true, false, alice, bob, flashloanOfferer, adapter, sidecar
        );
        test721_1.mint(alice, 1);
        test1155_1.mint(bob, 1, 1);
        try config.getPayload_BuyOfferedERC721WithERC1155(
            context, standardERC721, standardERC1155
        ) returns (TestOrderPayload memory payload) {
            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
                false,
                false,
                alice,
                payload.submitOrder
            );

            assertEq(test721_1.ownerOf(1), alice);
            assertEq(test1155_1.balanceOf(bob, 1), 1);

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill")),
                true,
                false,
                bob,
                payload.executeOrder
            );

            assertEq(test721_1.ownerOf(1), bob);
            assertEq(test1155_1.balanceOf(alice, 1), 1);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyOfferedERC721WithERC1155_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(buyOfferedERC721WithERC1155_ListOnChain_Adapter)";

        // Only seaport, skip for now.
        _logNotSupported(config.name(), testLabel);
        return 0;

        // TestOrderContext memory context = TestOrderContext(
        //     true, true, alice, bob, flashloanOfferer, adapter, sidecar
        // );
        // test721_1.mint(alice, 1);
        // test1155_1.mint(bob, 1, 1);
        // try config.getPayload_BuyOfferedERC721WithERC1155(
        //     context,
        //     standardERC721,
        //     standardERC1155
        // ) returns (TestOrderPayload memory payload) {
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
        //     _logNotSupported(config.name(), testLabel);
        // }
    }

    function buyOfferedERC721WithERC1155(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(buyOfferedERC721WithERC1155)";
        TestOrderContext memory context = TestOrderContext(
            false, false, alice, bob, flashloanOfferer, adapter, sidecar
        );
        test721_1.mint(alice, 1);
        test1155_1.mint(bob, 1, 1);
        try config.getPayload_BuyOfferedERC721WithERC1155(
            context, standardERC721, standardERC1155
        ) returns (TestOrderPayload memory payload) {
            assertEq(test721_1.ownerOf(1), alice);
            assertEq(test1155_1.balanceOf(bob, 1), 1);

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill w/ Sig")),
                true,
                false,
                bob,
                payload.executeOrder
            );

            assertEq(test721_1.ownerOf(1), bob);
            assertEq(test1155_1.balanceOf(alice, 1), 1);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyOfferedERC721WithERC1155_Adapter(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(buyOfferedERC721WithERC1155_Adapter)";

        // Only seaport, skip for now.
        _logNotSupported(config.name(), testLabel);
        return 0;

        // TestOrderContext memory context = TestOrderContext(
        //     false, true, alice, bob, flashloanOfferer, adapter, sidecar
        // );
        // test721_1.mint(alice, 1);
        // test1155_1.mint(bob, 1, 1);
        // try config.getPayload_BuyOfferedERC721WithERC1155(
        //     context,
        //     standardERC721,
        //     standardERC1155
        // ) returns (TestOrderPayload memory payload) {
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
        //     _logNotSupported(config.name(), testLabel);
        // }
    }

    function buyOfferedERC1155WithERC721_ListOnChain(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(buyOfferedERC1155WithERC721_ListOnChain)";
        TestOrderContext memory context = TestOrderContext(
            true, false, alice, bob, flashloanOfferer, adapter, sidecar
        );
        test1155_1.mint(alice, 1, 1);
        test721_1.mint(bob, 1);
        try config.getPayload_BuyOfferedERC1155WithERC721(
            context, standardERC1155, standardERC721
        ) returns (TestOrderPayload memory payload) {
            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
                false,
                false,
                alice,
                payload.submitOrder
            );

            assertEq(test721_1.ownerOf(1), bob);
            assertEq(test1155_1.balanceOf(alice, 1), 1);

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill")),
                true,
                false,
                bob,
                payload.executeOrder
            );

            assertEq(test721_1.ownerOf(1), alice);
            assertEq(test1155_1.balanceOf(bob, 1), 1);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyOfferedERC1155WithERC721_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(buyOfferedERC1155WithERC721_ListOnChain_Adapter)";

        // Only seaport so skipping here.
        _logNotSupported(config.name(), testLabel);
        return 0;

        // TestOrderContext memory context = TestOrderContext(
        //     true, true, alice, bob, flashloanOfferer, adapter, sidecar
        // );
        // test1155_1.mint(alice, 1, 1);
        // test721_1.mint(bob, 1);
        // try config.getPayload_BuyOfferedERC1155WithERC721(
        //     context,
        //     standardERC1155,
        //     standardERC721
        // ) returns (TestOrderPayload memory payload) {
        //     gasUsed = _benchmarkCallWithParams(
        //         config.name(),
        //         string(abi.encodePacked(testLabel, " List")),
        //         alice,
        //         payload.submitOrder
        //     );

        //     assertEq(test721_1.ownerOf(1), bob);
        //     assertEq(test1155_1.balanceOf(alice, 1), 1);

        //     gasUsed = _benchmarkCallWithParams(
        //         config.name(),
        //         string(abi.encodePacked(testLabel, " Fulfill*")),true,
        //         bob,
        //         payload.executeOrder
        //     );

        //     assertEq(test721_1.ownerOf(1), alice);
        //     assertEq(test1155_1.balanceOf(bob, 1), 1);
        // } catch {
        //     _logNotSupported(config.name(), testLabel);
        // }
    }

    function buyOfferedERC1155WithERC721(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(buyOfferedERC1155WithERC721)";
        TestOrderContext memory context = TestOrderContext(
            false, false, alice, bob, flashloanOfferer, adapter, sidecar
        );
        test1155_1.mint(alice, 1, 1);
        test721_1.mint(bob, 1);
        try config.getPayload_BuyOfferedERC1155WithERC721(
            context, standardERC1155, standardERC721
        ) returns (TestOrderPayload memory payload) {
            assertEq(test721_1.ownerOf(1), bob);
            assertEq(test1155_1.balanceOf(alice, 1), 1);

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill w/ Sig")),
                true,
                false,
                bob,
                payload.executeOrder
            );

            assertEq(test721_1.ownerOf(1), alice);
            assertEq(test1155_1.balanceOf(bob, 1), 1);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyOfferedERC1155WithERC721_Adapter(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(buyOfferedERC1155WithERC721_Adapter)";

        // Only seaport so skipping here.
        _logNotSupported(config.name(), testLabel);
        return 0;

        // TestOrderContext memory context = TestOrderContext(
        //     false, true, alice, bob, flashloanOfferer, adapter, sidecar
        // );
        // test1155_1.mint(alice, 1, 1);
        // test721_1.mint(bob, 1);

        // try config.getPayload_BuyOfferedERC1155WithERC721(
        //     context, standardERC1155, standardERC721
        // ) returns (TestOrderPayload memory payload) {
        //     assertEq(test721_1.ownerOf(1), bob);
        //     assertEq(test1155_1.balanceOf(alice, 1), 1);

        //     payload.executeOrder = AdapterHelperLib
        //         .createSeaportWrappedTestCallParameters(
        //         payload.executeOrder,
        //         address(context.fulfiller),
        //         seaportAddress,
        //         address(context.flashloanOfferer),
        //         address(context.adapter),
        //         sidecar,
        //
        //         standardERC721
        //     );

        //     gasUsed = _benchmarkCallWithParams(
        //         config.name(),
        //         string(abi.encodePacked(testLabel, " Fulfill w/ Sig*")),
        //         true,
        //         true,
        //         bob,
        //         payload.executeOrder
        //     );

        //     assertEq(test721_1.ownerOf(1), alice);
        //     assertEq(test1155_1.balanceOf(bob, 1), 1);
        // } catch {
        //     _logNotSupported(config.name(), testLabel);
        // }
    }

    function buyOfferedERC721WithEtherFee_ListOnChain(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(buyOfferedERC721WithEtherFee_ListOnChain)";
        test721_1.mint(alice, 1);
        try config.getPayload_BuyOfferedERC721WithEtherOneFeeRecipient(
            TestOrderContext(
                true, false, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            standardERC721,
            500, // increased so that the fee recipient recieves 1%
            feeReciever1,
            5
        ) returns (TestOrderPayload memory payload) {
            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
                false,
                false,
                alice,
                payload.submitOrder
            );

            // Allow the market to escrow after listing
            assert(
                test721_1.ownerOf(1) == alice
                    || test721_1.ownerOf(1) == config.market()
            );
            assertEq(feeReciever1.balance, 0);

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill")),
                true,
                false,
                bob,
                payload.executeOrder
            );

            assertEq(test721_1.ownerOf(1), bob);
            assertEq(feeReciever1.balance, 5);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyOfferedERC721WithEtherFee_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(buyOfferedERC721WithEtherFee_ListOnChain_Adapter)";
        test721_1.mint(alice, 1);

        TestOrderContext memory context = TestOrderContext(
            true, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        try config.getPayload_BuyOfferedERC721WithEtherOneFeeRecipient(
            context,
            standardERC721,
            500, // increased so that the fee recipient recieves 1%
            feeReciever1,
            5
        ) returns (TestOrderPayload memory payload) {
            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
                false,
                false,
                alice,
                payload.submitOrder
            );

            // Allow the market to escrow after listing
            assert(
                test721_1.ownerOf(1) == alice
                    || test721_1.ownerOf(1) == config.market()
            );
            assertEq(feeReciever1.balance, 0);

            Flashloan memory flashloan = Flashloan({
                amount: 505,
                itemType: ItemType.NATIVE,
                shouldCallback: true,
                recipient: adapter
            });

            Flashloan[] memory flashloanArray = new Flashloan[](1);
            flashloanArray[0] = flashloan;

            ConsiderationItem[] memory considerationArray =
            new ConsiderationItem[](
                1
            );
            considerationArray[0] = ConsiderationItemLib.fromDefault(
                "standardNativeConsiderationItem"
            ).withStartAmount(505).withEndAmount(505);

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedTestCallParameters(
                stdCastOfCharacters,
                flashloanArray,
                considerationArray,
                standardERC721
            );

            // Increase the value to account for the fee.
            payload.executeOrder.value = 505;

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill*")),
                true,
                true,
                bob,
                payload.executeOrder
            );

            assertEq(test721_1.ownerOf(1), bob);
            assertEq(feeReciever1.balance, 5);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyOfferedERC721WithEtherFee(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(buyOfferedERC721WithEtherFee)";
        test721_1.mint(alice, 1);
        try config.getPayload_BuyOfferedERC721WithEtherOneFeeRecipient(
            TestOrderContext(
                false, false, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            standardERC721,
            100,
            feeReciever1,
            5
        ) returns (TestOrderPayload memory payload) {
            assertEq(test721_1.ownerOf(1), alice);
            assertEq(feeReciever1.balance, 0);

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill w/ Sig")),
                true,
                false,
                bob,
                payload.executeOrder
            );

            assertEq(test721_1.ownerOf(1), bob);
            assertEq(feeReciever1.balance, 5);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyOfferedERC721WithEtherFee_Adapter(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(buyOfferedERC721WithEtherFee_Adapter)";
        test721_1.mint(alice, 1);

        TestOrderContext memory context = TestOrderContext(
            false, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        if (_sameName(config.name(), x2y2Config.name())) {
            context.fulfiller = sidecar;
        }

        try config.getPayload_BuyOfferedERC721WithEtherOneFeeRecipient(
            context, standardERC721, 100, feeReciever1, 5
        ) returns (TestOrderPayload memory payload) {
            context.fulfiller = bob;
            assertEq(test721_1.ownerOf(1), alice);
            assertEq(feeReciever1.balance, 0);

            Flashloan memory flashloan = Flashloan({
                amount: 105,
                itemType: ItemType.NATIVE,
                shouldCallback: true,
                recipient: adapter
            });

            Flashloan[] memory flashloanArray = new Flashloan[](1);
            flashloanArray[0] = flashloan;

            ConsiderationItem[] memory considerationArray =
            new ConsiderationItem[](
                1
            );
            considerationArray[0] = ConsiderationItemLib.fromDefault(
                "standardNativeConsiderationItem"
            ).withStartAmount(105).withEndAmount(105);

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedTestCallParameters(
                stdCastOfCharacters,
                flashloanArray,
                considerationArray,
                standardERC721
            );

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill w/ Sig*")),
                true,
                true,
                bob,
                payload.executeOrder
            );

            assertEq(test721_1.ownerOf(1), bob);
            assertEq(feeReciever1.balance, 5);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyOfferedERC721WithEtherFeeTwoRecipients_ListOnChain(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(buyOfferedERC721WithEtherFeeTwoRecipients_ListOnChain)";
        test721_1.mint(alice, 1);
        try config.getPayload_BuyOfferedERC721WithEtherTwoFeeRecipient(
            TestOrderContext(
                true, false, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            standardERC721,
            100,
            feeReciever1,
            5,
            feeReciever2,
            5
        ) returns (TestOrderPayload memory payload) {
            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
                false,
                false,
                alice,
                payload.submitOrder
            );

            // Allow the market to escrow after listing
            assert(
                test721_1.ownerOf(1) == alice
                    || test721_1.ownerOf(1) == config.market()
            );
            assertEq(feeReciever1.balance, 0);
            assertEq(feeReciever2.balance, 0);

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill")),
                true,
                false,
                bob,
                payload.executeOrder
            );

            assertEq(test721_1.ownerOf(1), bob);
            assertEq(feeReciever1.balance, 5);
            assertEq(feeReciever2.balance, 5);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyOfferedERC721WithEtherFeeTwoRecipients_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(buyOfferedERC721WithEtherFeeTwoRecipients_ListOnChain_Adapter)";
        test721_1.mint(alice, 1);

        TestOrderContext memory context = TestOrderContext(
            true, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        try config.getPayload_BuyOfferedERC721WithEtherTwoFeeRecipient(
            context, standardERC721, 100, feeReciever1, 5, feeReciever2, 5
        ) returns (TestOrderPayload memory payload) {
            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
                false,
                false,
                alice,
                payload.submitOrder
            );

            assert(
                test721_1.ownerOf(1) == alice
                    || test721_1.ownerOf(1) == config.market()
            );
            assertEq(feeReciever1.balance, 0);
            assertEq(feeReciever2.balance, 0);

            Flashloan memory flashloan = Flashloan({
                amount: 110,
                itemType: ItemType.NATIVE,
                shouldCallback: true,
                recipient: adapter
            });

            Flashloan[] memory flashloanArray = new Flashloan[](1);
            flashloanArray[0] = flashloan;

            ConsiderationItem[] memory considerationArray =
            new ConsiderationItem[](
                1
            );
            considerationArray[0] = ConsiderationItemLib.fromDefault(
                "standardNativeConsiderationItem"
            ).withStartAmount(110).withEndAmount(110);

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedTestCallParameters(
                stdCastOfCharacters,
                flashloanArray,
                considerationArray,
                standardERC721
            );

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill*")),
                true,
                true,
                bob,
                payload.executeOrder
            );

            assertEq(test721_1.ownerOf(1), bob);
            assertEq(feeReciever1.balance, 5);
            assertEq(feeReciever2.balance, 5);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyOfferedERC721WithEtherFeeTwoRecipients(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(buyOfferedERC721WithEtherFeeTwoRecipients)";
        test721_1.mint(alice, 1);
        try config.getPayload_BuyOfferedERC721WithEtherTwoFeeRecipient(
            TestOrderContext(
                false, false, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            standardERC721,
            100,
            feeReciever1,
            5,
            feeReciever2,
            5
        ) returns (TestOrderPayload memory payload) {
            assertEq(test721_1.ownerOf(1), alice);
            assertEq(feeReciever1.balance, 0);
            assertEq(feeReciever2.balance, 0);

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fullfil /w Sig")),
                true,
                false,
                bob,
                payload.executeOrder
            );

            assertEq(test721_1.ownerOf(1), bob);
            assertEq(feeReciever1.balance, 5);
            assertEq(feeReciever2.balance, 5);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyOfferedERC721WithEtherFeeTwoRecipients_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(buyOfferedERC721WithEtherFeeTwoRecipients_Adapter)";
        test721_1.mint(alice, 1);

        TestOrderContext memory context = TestOrderContext(
            false, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        if (_sameName(config.name(), x2y2Config.name())) {
            context.fulfiller = sidecar;
        }

        try config.getPayload_BuyOfferedERC721WithEtherTwoFeeRecipient(
            context, standardERC721, 100, feeReciever1, 5, feeReciever2, 5
        ) returns (TestOrderPayload memory payload) {
            context.fulfiller = bob;
            assertEq(test721_1.ownerOf(1), alice);
            assertEq(feeReciever1.balance, 0);
            assertEq(feeReciever2.balance, 0);

            Flashloan memory flashloan = Flashloan({
                amount: 110,
                itemType: ItemType.NATIVE,
                shouldCallback: true,
                recipient: adapter
            });

            Flashloan[] memory flashloanArray = new Flashloan[](1);
            flashloanArray[0] = flashloan;

            ConsiderationItem[] memory considerationArray =
            new ConsiderationItem[](
                1
            );
            considerationArray[0] = ConsiderationItemLib.fromDefault(
                "standardNativeConsiderationItem"
            ).withStartAmount(110).withEndAmount(110);

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedTestCallParameters(
                stdCastOfCharacters,
                flashloanArray,
                considerationArray,
                standardERC721
            );

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill w/ Sig*")),
                true,
                true,
                bob,
                payload.executeOrder
            );

            assertEq(test721_1.ownerOf(1), bob);
            assertEq(feeReciever1.balance, 5);
            assertEq(feeReciever2.balance, 5);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyTenOfferedERC721WithEther_ListOnChain(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(buyTenOfferedERC721WithEther_ListOnChain)";

        TestItem721[] memory nfts = new TestItem721[](10);
        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
            nfts[i] = TestItem721(_test721Address, i + 1);
        }

        try config.getPayload_BuyOfferedManyERC721WithEther(
            TestOrderContext(
                true, false, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            nfts,
            100
        ) returns (TestOrderPayload memory payload) {
            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
                false,
                false,
                alice,
                payload.submitOrder
            );

            for (uint256 i = 0; i < 10; i++) {
                assertTrue(
                    test721_1.ownerOf(i + 1) == alice
                        || test721_1.ownerOf(i + 1) == config.market(),
                    "Not owner"
                );
            }

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill")),
                true,
                false,
                bob,
                payload.executeOrder
            );

            for (uint256 i = 0; i < 10; i++) {
                assertEq(test721_1.ownerOf(i + 1), bob);
            }
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyTenOfferedERC721WithEther_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(buyTenOfferedERC721WithEther_ListOnChain_Adapter)";

        TestOrderContext memory context = TestOrderContext(
            true, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        TestItem721[] memory items = new TestItem721[](10);
        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
            items[i] = TestItem721(_test721Address, i + 1);
        }

        try config.getPayload_BuyOfferedManyERC721WithEther(context, items, 100)
        returns (TestOrderPayload memory payload) {
            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
                false,
                false,
                alice,
                payload.submitOrder
            );

            for (uint256 i = 0; i < 10; i++) {
                assertTrue(
                    test721_1.ownerOf(i + 1) == alice
                        || test721_1.ownerOf(i + 1) == config.market(),
                    "Not owner"
                );
            }

            Flashloan memory flashloan = Flashloan({
                amount: 100,
                itemType: ItemType.NATIVE,
                shouldCallback: true,
                recipient: adapter
            });

            Flashloan[] memory flashloanArray = new Flashloan[](1);
            flashloanArray[0] = flashloan;

            if (_sameName(config.name(), sudoswapConfig.name())) {
                items = new TestItem721[](0);
            }

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedTestCallParameters(
                stdCastOfCharacters,
                flashloanArray,
                ConsiderationItemLib.fromDefaultMany(
                    "standardNativeConsiderationArray"
                ),
                items
            );

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill*")),
                true,
                true,
                bob,
                payload.executeOrder
            );

            for (uint256 i = 0; i < 10; i++) {
                assertEq(test721_1.ownerOf(i + 1), bob);
            }
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyTenOfferedERC721WithEther(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(buyTenOfferedERC721WithEther)";

        TestItem721[] memory nfts = new TestItem721[](10);
        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
            nfts[i] = TestItem721(_test721Address, i + 1);
        }

        try config.getPayload_BuyOfferedManyERC721WithEther(
            TestOrderContext(
                false, false, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            nfts,
            100
        ) returns (TestOrderPayload memory payload) {
            for (uint256 i = 0; i < 10; i++) {
                assertEq(test721_1.ownerOf(i + 1), alice);
            }

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill /w Sig")),
                true,
                false,
                bob,
                payload.executeOrder
            );

            for (uint256 i = 0; i < 10; i++) {
                assertEq(test721_1.ownerOf(i + 1), bob);
            }
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyTenOfferedERC721WithEther_Adapter(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(buyTenOfferedERC721WithEther_Adapter)";

        TestOrderContext memory context = TestOrderContext(
            false, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        if (_sameName(config.name(), x2y2Config.name())) {
            context.fulfiller = sidecar;
        }

        TestItem721[] memory items = new TestItem721[](10);
        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
            items[i] = TestItem721(_test721Address, i + 1);
        }

        try config.getPayload_BuyOfferedManyERC721WithEther(context, items, 100)
        returns (TestOrderPayload memory payload) {
            context.fulfiller = bob;

            for (uint256 i = 0; i < 10; i++) {
                assertEq(test721_1.ownerOf(i + 1), alice);
            }

            Flashloan memory flashloan = Flashloan({
                amount: 100,
                itemType: ItemType.NATIVE,
                shouldCallback: true,
                recipient: adapter
            });

            Flashloan[] memory flashloanArray = new Flashloan[](1);
            flashloanArray[0] = flashloan;

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedTestCallParameters(
                stdCastOfCharacters,
                flashloanArray,
                ConsiderationItemLib.fromDefaultMany(
                    "standardNativeConsiderationArray"
                ),
                items
            );

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill /w Sig*")),
                true,
                true,
                bob,
                payload.executeOrder
            );

            for (uint256 i = 0; i < 10; i++) {
                assertEq(test721_1.ownerOf(i + 1), bob);
            }
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyTenOfferedERC721WithEtherDistinctOrders(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(buyTenOfferedERC721WithEtherDistinctOrders)";

        TestOrderContext[] memory contexts = new TestOrderContext[](10);
        TestItem721[] memory nfts = new TestItem721[](10);
        uint256[] memory ethAmounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
            nfts[i] = TestItem721(_test721Address, i + 1);
            contexts[i] = TestOrderContext(
                false, false, alice, bob, flashloanOfferer, adapter, sidecar
            );
            ethAmounts[i] = 100 + i;
        }

        try config.getPayload_BuyOfferedManyERC721WithEtherDistinctOrders(
            contexts, nfts, ethAmounts
        ) returns (TestOrderPayload memory payload) {
            for (uint256 i = 1; i <= 10; i++) {
                assertEq(test721_1.ownerOf(i), alice);
            }

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill /w Sigs")),
                true,
                false,
                bob,
                payload.executeOrder
            );

            for (uint256 i = 1; i <= 10; i++) {
                assertEq(test721_1.ownerOf(i), bob);
            }
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyTenOfferedERC721WithEtherDistinctOrders_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(buyTenOfferedERC721WithEtherDistinctOrders_Adapter)";

        bool requiresTakerIsSender = _sameName(config.name(), x2y2Config.name())
            || _sameName(config.name(), blurConfig.name());

        TestOrderContext[] memory contexts = new TestOrderContext[](10);
        TestItem721[] memory items = new TestItem721[](10);
        uint256[] memory ethAmounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
            items[i] = TestItem721(_test721Address, i + 1);
            contexts[i] = TestOrderContext(
                false,
                true,
                alice,
                requiresTakerIsSender ? sidecar : bob,
                flashloanOfferer,
                adapter,
                sidecar
            );
            ethAmounts[i] = 100 + i;
        }

        try config.getPayload_BuyOfferedManyERC721WithEtherDistinctOrders(
            contexts, items, ethAmounts
        ) returns (TestOrderPayload memory payload) {
            for (uint256 i = 0; i < 10; i++) {
                contexts[i].fulfiller = bob;
            }

            for (uint256 i = 1; i <= 10; i++) {
                assertEq(test721_1.ownerOf(i), alice);
            }

            uint256 flashloanAmount;

            for (uint256 i = 0; i < ethAmounts.length; i++) {
                flashloanAmount += ethAmounts[i];
            }

            Flashloan memory flashloan = Flashloan({
                amount: uint88(flashloanAmount),
                itemType: ItemType.NATIVE,
                shouldCallback: true,
                recipient: adapter
            });

            Flashloan[] memory flashloanArray = new Flashloan[](1);
            flashloanArray[0] = flashloan;

            ConsiderationItem[] memory considerationArray =
            new ConsiderationItem[](
                1
            );
            considerationArray[0] = ConsiderationItemLib.fromDefault(
                "standardNativeConsiderationItem"
            ).withStartAmount(flashloanAmount).withEndAmount(flashloanAmount);

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedTestCallParameters(
                stdCastOfCharacters, flashloanArray, considerationArray, items
            );

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill /w Sigs*")),
                true,
                true,
                bob,
                payload.executeOrder
            );

            for (uint256 i = 1; i <= 10; i++) {
                assertEq(test721_1.ownerOf(i), bob);
            }
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyTenOfferedERC721WithEtherDistinctOrders_ListOnChain(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(buyTenOfferedERC721WithEtherDistinctOrders_ListOnChain)";

        TestOrderContext[] memory contexts = new TestOrderContext[](10);
        TestItem721[] memory nfts = new TestItem721[](10);
        uint256[] memory ethAmounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
            nfts[i] = TestItem721(_test721Address, i + 1);
            contexts[i] = TestOrderContext(
                true, false, alice, bob, flashloanOfferer, adapter, sidecar
            );
            ethAmounts[i] = 100 + i;
        }

        try config.getPayload_BuyOfferedManyERC721WithEtherDistinctOrders(
            contexts, nfts, ethAmounts
        ) returns (TestOrderPayload memory payload) {
            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
                false,
                false,
                alice,
                payload.submitOrder
            );

            // @dev checking ownership here (when nfts are escrowed in different contracts) is messy so we skip it for now

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill")),
                true,
                false,
                bob,
                payload.executeOrder
            );

            for (uint256 i = 1; i <= 10; i++) {
                assertEq(test721_1.ownerOf(i), bob);
            }
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyTenOfferedERC721WithEtherDistinctOrders_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(buyTenOfferedERC721WithEtherDistinctOrders_ListOnChain_Adapter)";

        TestOrderContext[] memory contexts = new TestOrderContext[](10);
        TestItem721[] memory items = new TestItem721[](10);
        uint256[] memory ethAmounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
            items[i] = TestItem721(_test721Address, i + 1);
            contexts[i] = TestOrderContext(
                true, true, alice, bob, flashloanOfferer, adapter, sidecar
            );
            // There's something screwy with the ETH amounts here. For some
            // reason, this needs to be 101 instead of 100 like it is in its
            // sibling test. Only Sudo and Seaport are set up for this, and
            // Seaport doesn't get tested. So, leaving it alone for now.
            ethAmounts[i] = 101 + i;
        }

        try config.getPayload_BuyOfferedManyERC721WithEtherDistinctOrders(
            contexts, items, ethAmounts
        ) returns (TestOrderPayload memory payload) {
            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
                false,
                false,
                alice,
                payload.submitOrder
            );

            uint256 flashloanAmount;

            for (uint256 i; i < ethAmounts.length; i++) {
                flashloanAmount += ethAmounts[i];
            }

            Flashloan memory flashloan = Flashloan({
                amount: uint88(flashloanAmount),
                itemType: ItemType.NATIVE,
                shouldCallback: true,
                recipient: adapter
            });

            Flashloan[] memory flashloanArray = new Flashloan[](1);
            flashloanArray[0] = flashloan;

            // Sudo does the transfers.
            if (_sameName(config.name(), sudoswapConfig.name())) {
                items = new TestItem721[](0);
            }

            ConsiderationItem[] memory considerationArray =
            new ConsiderationItem[](
                1
            );
            considerationArray[0] = ConsiderationItemLib.fromDefault(
                "standardNativeConsiderationItem"
            ).withStartAmount(flashloanAmount).withEndAmount(flashloanAmount);

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedTestCallParameters(
                stdCastOfCharacters, flashloanArray, considerationArray, items
            );

            payload.executeOrder.value = flashloanAmount;

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill*")),
                true,
                true,
                bob,
                payload.executeOrder
            );

            for (uint256 i = 1; i <= 10; i++) {
                assertEq(test721_1.ownerOf(i), bob);
            }
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyTenOfferedERC721WithErc20DistinctOrders(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(buyTenOfferedERC721WithErc20DistinctOrders)";

        test20.mint(bob, 1045);
        TestOrderContext[] memory contexts = new TestOrderContext[](10);
        TestItem721[] memory nfts = new TestItem721[](10);
        uint256[] memory erc20Amounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
            nfts[i] = TestItem721(_test721Address, i + 1);
            contexts[i] = TestOrderContext(
                false, false, alice, bob, flashloanOfferer, adapter, sidecar
            );
            erc20Amounts[i] = 100 + i;
        }

        try config.getPayload_BuyOfferedManyERC721WithErc20DistinctOrders(
            contexts, _test20Address, nfts, erc20Amounts
        ) returns (TestOrderPayload memory payload) {
            for (uint256 i = 1; i <= 10; i++) {
                assertEq(test721_1.ownerOf(i), alice);
            }

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill /w Sigs")),
                true,
                false,
                bob,
                payload.executeOrder
            );

            for (uint256 i = 1; i <= 10; i++) {
                assertEq(test721_1.ownerOf(i), bob);
            }
            assertEq(test20.balanceOf(alice), 1045);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyTenOfferedERC721WithErc20DistinctOrders_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(buyTenOfferedERC721WithErc20DistinctOrders_Adapter)";

        test20.mint(bob, 1045);
        TestOrderContext[] memory contexts = new TestOrderContext[](10);
        TestItem721[] memory nfts = new TestItem721[](10);
        uint256[] memory erc20Amounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
            nfts[i] = TestItem721(_test721Address, i + 1);
            contexts[i] = TestOrderContext(
                false, true, alice, bob, flashloanOfferer, adapter, sidecar
            );
            erc20Amounts[i] = 100 + i;
        }

        if (
            _sameName(config.name(), x2y2Config.name())
                || _sameName(config.name(), looksRareConfig.name())
        ) {
            for (uint256 i = 0; i < contexts.length; i++) {
                contexts[i].fulfiller = address(contexts[i].sidecar);
            }
        }

        try config.getPayload_BuyOfferedManyERC721WithErc20DistinctOrders(
            contexts, _test20Address, nfts, erc20Amounts
        ) returns (TestOrderPayload memory payload) {
            for (uint256 i = 0; i < contexts.length; i++) {
                contexts[i].fulfiller = bob;
            }

            for (uint256 i = 1; i <= 10; i++) {
                assertEq(test721_1.ownerOf(i), alice);
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

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedTestCallParameters(
                stdCastOfCharacters, adapterOrderConsideration, nfts
            );

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill /w Sigs*")),
                true,
                true,
                bob,
                payload.executeOrder
            );

            for (uint256 i = 1; i <= 10; i++) {
                assertEq(test721_1.ownerOf(i), bob, "Bob did not get the NFT");
            }
            assertEq(test20.balanceOf(alice), 1045, "Alice did not get paid");
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyTenOfferedERC721WithErc20DistinctOrders_ListOnChain(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(buyTenOfferedERC721WithErc20DistinctOrders_ListOnChain)";

        test20.mint(bob, 1045);
        TestOrderContext[] memory contexts = new TestOrderContext[](10);
        TestItem721[] memory nfts = new TestItem721[](10);
        uint256[] memory erc20Amounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
            nfts[i] = TestItem721(_test721Address, i + 1);
            contexts[i] = TestOrderContext(
                true, false, alice, bob, flashloanOfferer, adapter, sidecar
            );
            erc20Amounts[i] = 100 + i;
        }

        try config.getPayload_BuyOfferedManyERC721WithErc20DistinctOrders(
            contexts, _test20Address, nfts, erc20Amounts
        ) returns (TestOrderPayload memory payload) {
            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
                false,
                false,
                alice,
                payload.submitOrder
            );

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill")),
                true,
                false,
                bob,
                payload.executeOrder
            );

            for (uint256 i = 1; i <= 10; i++) {
                assertEq(test721_1.ownerOf(i), bob);
            }
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyTenOfferedERC721WithErc20DistinctOrders_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(buyTenOfferedERC721WithErc20DistinctOrders_ListOnChain_Adapter)";

        test20.mint(bob, 1045);
        TestOrderContext[] memory contexts = new TestOrderContext[](10);
        TestItem721[] memory nfts = new TestItem721[](10);
        uint256[] memory erc20Amounts = new uint256[](10);

        // Ah crap this turns out to be only implemented for Seaport.
        if (
            _sameName(config.name(), x2y2Config.name())
                || _sameName(config.name(), looksRareConfig.name())
        ) {
            for (uint256 i = 0; i < contexts.length; i++) {
                contexts[i].fulfiller = address(contexts[i].sidecar);
            }
        }

        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
            nfts[i] = TestItem721(_test721Address, i + 1);
            contexts[i] = TestOrderContext(
                true, true, alice, bob, flashloanOfferer, adapter, sidecar
            );
            erc20Amounts[i] = 100 + i;
        }

        try config.getPayload_BuyOfferedManyERC721WithErc20DistinctOrders(
            contexts, _test20Address, nfts, erc20Amounts
        ) returns (TestOrderPayload memory payload) {
            for (uint256 i = 0; i < contexts.length; i++) {
                contexts[i].fulfiller = bob;
            }

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
                false,
                false,
                alice,
                payload.submitOrder
            );

            ConsiderationItem[] memory adapterOrderConsideration =
                new ConsiderationItem[](1);

            uint256 totalERC20Amount;

            for (uint256 i = 0; i < contexts.length; i++) {
                totalERC20Amount += erc20Amounts[i];
            }

            adapterOrderConsideration[0] = ConsiderationItemLib.fromDefault(
                "standardERC20ConsiderationItem"
            ).withStartAmount(totalERC20Amount).withEndAmount(totalERC20Amount);

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedTestCallParameters(
                stdCastOfCharacters, adapterOrderConsideration, nfts
            );

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill*")),
                true,
                true,
                bob,
                payload.executeOrder
            );

            for (uint256 i = 1; i <= 10; i++) {
                assertEq(test721_1.ownerOf(i), bob);
            }
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyTenOfferedERC721WithWETHDistinctOrders(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(buyTenOfferedERC721WithWETHDistinctOrders)";

        hevm.deal(bob, 1045);
        hevm.prank(bob);
        weth.deposit{ value: 1045 }();
        TestOrderContext[] memory contexts = new TestOrderContext[](10);
        TestItem721[] memory nfts = new TestItem721[](10);
        uint256[] memory wethAmounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
            nfts[i] = TestItem721(_test721Address, i + 1);
            contexts[i] = TestOrderContext(
                false, false, alice, bob, flashloanOfferer, adapter, sidecar
            );
            wethAmounts[i] = 100 + i;
        }

        try config.getPayload_BuyOfferedManyERC721WithWETHDistinctOrders(
            contexts, wethAddress, nfts, wethAmounts
        ) returns (TestOrderPayload memory payload) {
            for (uint256 i = 1; i <= 10; i++) {
                assertEq(test721_1.ownerOf(i), alice);
            }

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill /w Sigs")),
                true,
                false,
                bob,
                payload.executeOrder
            );

            for (uint256 i = 1; i <= 10; i++) {
                assertEq(test721_1.ownerOf(i), bob);
            }
            assertEq(weth.balanceOf(alice), 1045);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    // NOTE: Blur doesn't support ad hoc signing (a caller has to pass in a
    //       signed taker order and a signed maker order). So in cases where it
    //       also refuses to allow the caller to be different than the taker, it
    //       looks like a hard block.

    function buyTenOfferedERC721WithWETHDistinctOrders_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(buyTenOfferedERC721WithWETHDistinctOrders_Adapter)";

        hevm.deal(bob, 1045);
        hevm.prank(bob);
        weth.deposit{ value: 1045 }();
        TestOrderContext[] memory contexts = new TestOrderContext[](10);
        TestItem721[] memory nfts = new TestItem721[](10);
        uint256[] memory wethAmounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
            nfts[i] = TestItem721(_test721Address, i + 1);
            contexts[i] = TestOrderContext(
                false, true, alice, bob, flashloanOfferer, adapter, sidecar
            );
            wethAmounts[i] = 100 + i;
        }

        // NOTE: Blur doesn't support ad hoc signing, so this just puts Blur on
        //       the `except` path, which currently fails silently.
        if (
            _sameName(config.name(), x2y2Config.name())
                || _sameName(config.name(), blurConfig.name())
        ) {
            for (uint256 i = 0; i < contexts.length; i++) {
                contexts[i].fulfiller = sidecar;
            }
        }

        try config.getPayload_BuyOfferedManyERC721WithWETHDistinctOrders(
            contexts, wethAddress, nfts, wethAmounts
        ) returns (TestOrderPayload memory payload) {
            for (uint256 i = 0; i < contexts.length; i++) {
                contexts[i].fulfiller = bob;
            }

            for (uint256 i = 1; i <= 10; i++) {
                assertEq(test721_1.ownerOf(i), alice);
            }

            uint256 totalWethAmount;

            for (uint256 i = 0; i < wethAmounts.length; i++) {
                totalWethAmount += wethAmounts[i];
            }

            vm.prank(sidecar);
            weth.approve(sidecar, type(uint256).max);

            ConsiderationItem[] memory considerationArray =
                new ConsiderationItem[](1);
            considerationArray[0] = ConsiderationItemLib.fromDefault(
                "standardWethConsiderationItem"
            ).withStartAmount(totalWethAmount).withEndAmount(totalWethAmount);

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedTestCallParameters(
                stdCastOfCharacters, considerationArray, nfts
            );

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill /w Sigs*")),
                true,
                true,
                bob,
                payload.executeOrder
            );

            for (uint256 i = 1; i <= 10; i++) {
                assertEq(test721_1.ownerOf(i), bob);
            }
            assertEq(weth.balanceOf(alice), 1045);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyTenOfferedERC721WithWETHDistinctOrders_ListOnChain(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(buyTenOfferedERC721WithWETHDistinctOrders_ListOnChain)";

        hevm.deal(bob, 1045);
        hevm.prank(bob);
        weth.deposit{ value: 1045 }();
        TestOrderContext[] memory contexts = new TestOrderContext[](10);
        TestItem721[] memory nfts = new TestItem721[](10);
        uint256[] memory wethAmounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
            nfts[i] = TestItem721(_test721Address, i + 1);
            contexts[i] = TestOrderContext(
                true, false, alice, bob, flashloanOfferer, adapter, sidecar
            );
            wethAmounts[i] = 100 + i;
        }

        try config.getPayload_BuyOfferedManyERC721WithWETHDistinctOrders(
            contexts, wethAddress, nfts, wethAmounts
        ) returns (TestOrderPayload memory payload) {
            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
                false,
                false,
                alice,
                payload.submitOrder
            );

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill")),
                true,
                false,
                bob,
                payload.executeOrder
            );

            for (uint256 i = 1; i <= 10; i++) {
                assertEq(test721_1.ownerOf(i), bob);
            }
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyTenOfferedERC721WithWETHDistinctOrders_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(buyTenOfferedERC721WithWETHDistinctOrders_ListOnChain_Adapter)";

        hevm.deal(bob, 1045);
        hevm.prank(bob);
        weth.deposit{ value: 1045 }();
        TestOrderContext[] memory contexts = new TestOrderContext[](10);
        TestItem721[] memory nfts = new TestItem721[](10);
        uint256[] memory wethAmounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
            nfts[i] = TestItem721(_test721Address, i + 1);
            contexts[i] = TestOrderContext(
                true, true, alice, bob, flashloanOfferer, adapter, sidecar
            );
            wethAmounts[i] = 100 + i;
        }

        try config.getPayload_BuyOfferedManyERC721WithWETHDistinctOrders(
            contexts, wethAddress, nfts, wethAmounts
        ) returns (TestOrderPayload memory payload) {
            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
                false,
                false,
                alice,
                payload.submitOrder
            );

            ConsiderationItem[] memory considerationArray =
            new ConsiderationItem[](
                1
            );
            considerationArray[0] = ConsiderationItemLib.fromDefault(
                "standardNativeConsiderationItem"
            ).withStartAmount(0).withEndAmount(0);

            payload.executeOrder = payload
                .executeOrder
                .createSeaportWrappedTestCallParameters(
                stdCastOfCharacters, considerationArray, new TestItem721[](0)
            );

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill*")),
                true,
                true,
                bob,
                payload.executeOrder
            );

            for (uint256 i = 1; i <= 10; i++) {
                assertEq(test721_1.ownerOf(i), bob);
            }
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function benchmark_MatchOrders_ABCA(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(benchmark_MatchOrders_ABCA)";

        test721_1.mint(alice, 1);
        test721_1.mint(cal, 2);
        test721_1.mint(bob, 3);

        TestOrderContext[] memory contexts = new TestOrderContext[](3);
        TestItem721[] memory nfts = new TestItem721[](3);

        contexts[0] = TestOrderContext(
            false, false, alice, address(0), flashloanOfferer, adapter, sidecar
        );
        contexts[1] = TestOrderContext(
            false, false, cal, address(0), flashloanOfferer, adapter, sidecar
        );
        contexts[2] = TestOrderContext(
            false, false, bob, address(0), flashloanOfferer, adapter, sidecar
        );

        nfts[0] = standardERC721;
        nfts[1] = standardERC721Two;
        nfts[2] = TestItem721(_test721Address, 3);

        try config.getPayload_MatchOrders_ABCA(contexts, nfts) returns (
            TestOrderPayload memory payload
        ) {
            assertEq(test721_1.ownerOf(1), alice);
            assertEq(test721_1.ownerOf(2), cal);
            assertEq(test721_1.ownerOf(3), bob);

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill /w Sigs")),
                true,
                false,
                bob,
                payload.executeOrder
            );

            assertEq(test721_1.ownerOf(1), bob);
            assertEq(test721_1.ownerOf(2), alice);
            assertEq(test721_1.ownerOf(3), cal);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function benchmark_MatchOrders_ABCA_Adapter(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(benchmark_MatchOrders_ABCA_Adapter)";

        // Seaport only.
        _logNotSupported(config.name(), testLabel);
        return 0;

        // test721_1.mint(alice, 1);
        // test721_1.mint(cal, 2);
        // test721_1.mint(bob, 3);

        // TestOrderContext[] memory contexts = new TestOrderContext[](3);
        // TestItem721[] memory nfts = new TestItem721[](3);

        // contexts[0] = TestOrderContext(
        //     false, true, alice, address(0), flashloanOfferer, adapter, sidecar
        // );
        // contexts[1] = TestOrderContext(
        //     false, true, cal, address(0), flashloanOfferer, adapter, sidecar
        // );
        // contexts[2] = TestOrderContext(
        //     false, true, bob, address(0), flashloanOfferer, adapter, sidecar
        // );

        // nfts[0] = standardERC721;
        // nfts[1] = standardERC721Two;
        // nfts[2] = TestItem721(_test721Address, 3);

        // try config.getPayload_MatchOrders_ABCA(contexts, nfts) returns (
        //     TestOrderPayload memory payload
        // ) {
        //     assertEq(test721_1.ownerOf(1), alice);
        //     assertEq(test721_1.ownerOf(2), cal);
        //     assertEq(test721_1.ownerOf(3), bob);

        //     gasUsed = _benchmarkCallWithParams(
        //         config.name(),
        //         string(abi.encodePacked(testLabel, " Fulfill*")),true,
        //         bob,
        //         payload.executeOrder
        //     );

        //     assertEq(test721_1.ownerOf(1), bob);
        //     assertEq(test721_1.ownerOf(2), alice);
        //     assertEq(test721_1.ownerOf(3), cal);
        // } catch {
        //     _logNotSupported(config.name(), testLabel);
        // }
    }

    /*//////////////////////////////////////////////////////////////
                          Helpers
    //////////////////////////////////////////////////////////////*/

    function setUp() public virtual override {
        super.setUp();
    }

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
        }
        _;
    }

    modifier prepareTest(BaseMarketConfig config) {
        _resetStorageAndEth(config.market());
        require(
            config.sellerErc20ApprovalTarget() != address(0)
                && config.sellerNftApprovalTarget() != address(0)
                && config.buyerErc20ApprovalTarget() != address(0)
                && config.buyerNftApprovalTarget() != address(0),
            "BaseMarketplaceTester::prepareTest: approval target not set"
        );
        _setApprovals(
            alice,
            config.sellerErc20ApprovalTarget(),
            config.sellerNftApprovalTarget(),
            config.sellerErc1155ApprovalTarget()
        );
        _setApprovals(
            cal,
            config.sellerErc20ApprovalTarget(),
            config.sellerNftApprovalTarget(),
            config.sellerErc1155ApprovalTarget()
        );
        _setApprovals(
            bob,
            config.buyerErc20ApprovalTarget(),
            config.buyerNftApprovalTarget(),
            config.buyerErc1155ApprovalTarget()
        );
        // This simulates passing in a Call that approves some target
        // marketplace.
        _setApprovals(
            sidecar,
            config.buyerErc20ApprovalTarget(),
            config.buyerNftApprovalTarget(),
            config.buyerErc1155ApprovalTarget()
        );
        _setApprovals(
            sidecar,
            config.sellerErc20ApprovalTarget(),
            config.sellerNftApprovalTarget(),
            config.sellerErc1155ApprovalTarget()
        );
        _;
    }

    function signDigest(address signer, bytes32 digest)
        external
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        (v, r, s) = hevm.sign(privateKeys[signer], digest);
    }

    function _signDigest(address signer, bytes32 digest)
        internal
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        (v, r, s) = hevm.sign(privateKeys[signer], digest);
    }

    function _doSetup() internal {
        testFlashloanOfferer = FlashloanOffererInterface(
            deployCode(
                "out/FlashloanOfferer.sol/FlashloanOfferer.json",
                abi.encode(seaportAddress)
            )
        );

        vm.recordLogs();

        testAdapter = GenericAdapterInterface(
            deployCode(
                "out/GenericAdapter.sol/GenericAdapter.json",
                abi.encode(seaportAddress, address(testFlashloanOfferer))
            )
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();

        testSidecar = GenericAdapterSidecarInterface(
            abi.decode(entries[0].data, (address))
        );

        flashloanOfferer = address(testFlashloanOfferer);
        adapter = address(testAdapter);
        sidecar = address(testSidecar);
        wethAddress = address(weth);
        _test20Address = address(test20);
        _test721Address = address(test721_1);
        _test1155Address = address(test1155_1);

        standardWeth = TestItem20(wethAddress, 100);
        standardERC20 = TestItem20(_test20Address, 100);
        standardERC721 = TestItem721(_test721Address, 1);
        standardERC721Two = TestItem721(_test721Address, 2);
        standardERC1155 = TestItem1155(_test1155Address, 1, 1);

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

                vm.prank(adapterUsers[i]);
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
        vm.prank(seaportAddress);
        testAdapter.generateOrder(
            address(this), new SpentItem[](0), new SpentItem[](0), contextArg
        );

        vm.deal(flashloanOfferer, type(uint128).max);

        vm.startPrank(sidecar);
        test20.approve(sidecar, type(uint256).max);
        weth.approve(sidecar, type(uint256).max);
        vm.stopPrank();

        stdCastOfCharacters = CastOfCharacters({
            offerer: alice,
            fulfiller: bob,
            seaport: seaportAddress,
            flashloanOfferer: flashloanOfferer,
            adapter: adapter,
            sidecar: sidecar
        });

        ConsiderationItem memory standardNativeConsideration =
        ConsiderationItemLib.empty().withItemType(ItemType.NATIVE).withToken(
            address(0)
        ).withIdentifierOrCriteria(0).withStartAmount(100).withEndAmount(100)
            .withRecipient(address(0)).saveDefault(
            "standardNativeConsiderationItem"
        );
        ConsiderationItem memory standardWethConsideration =
        ConsiderationItemLib.empty().withItemType(ItemType.ERC20).withToken(
            wethAddress
        ).withIdentifierOrCriteria(0).withStartAmount(100).withEndAmount(100)
            .withRecipient(address(0)).saveDefault("standardWethConsiderationItem");
        ConsiderationItem memory standardERC20Consideration =
        ConsiderationItemLib.empty().withItemType(ItemType.ERC20).withToken(
            _test20Address
        ).withIdentifierOrCriteria(0).withStartAmount(100).withEndAmount(100)
            .withRecipient(address(0)).saveDefault("standardERC20ConsiderationItem");
        ConsiderationItem memory standardERC721Consideration =
        ConsiderationItemLib.empty().withItemType(ItemType.ERC721).withToken(
            _test721Address
        ).withIdentifierOrCriteria(1).withStartAmount(1).withEndAmount(1)
            .withRecipient(address(0)).saveDefault("standard721ConsiderationItem");
        ConsiderationItem memory standardERC1155Consideration =
        ConsiderationItemLib.empty().withItemType(ItemType.ERC1155).withToken(
            _test1155Address
        ).withIdentifierOrCriteria(1).withStartAmount(1).withEndAmount(1)
            .withRecipient(address(0)).saveDefault("standard1155ConsiderationItem");

        ConsiderationItem[] memory adapterOrderConsideration =
            new ConsiderationItem[](1);

        adapterOrderConsideration[0] = standardNativeConsideration;
        adapterOrderConsideration.saveDefaultMany(
            "standardNativeConsiderationArray"
        );

        adapterOrderConsideration[0] = standardWethConsideration;
        adapterOrderConsideration.saveDefaultMany(
            "standardWethConsiderationArray"
        );

        adapterOrderConsideration[0] = standardERC20Consideration;
        adapterOrderConsideration.saveDefaultMany(
            "standardERC20ConsiderationArray"
        );

        adapterOrderConsideration[0] = standardERC721Consideration;
        adapterOrderConsideration.saveDefaultMany(
            "standardERC721ConsiderationArray"
        );

        adapterOrderConsideration[0] = standardERC1155Consideration;
        adapterOrderConsideration.saveDefaultMany(
            "standardERC1155ConsiderationArray"
        );
    }

    function beforeAllPrepareMarketplaceTest(BaseMarketConfig config)
        internal
    {
        // Get requested call from marketplace. Needed by Wyvern to deploy proxy
        SetupCall[] memory setupCalls = config.beforeAllPrepareMarketplaceCall(
            alice, bob, erc20Addresses, erc721Addresses
        );

        for (uint256 i = 0; i < setupCalls.length; i++) {
            hevm.startPrank(setupCalls[i].sender);
            (bool avoidWarning, bytes memory data) =
                (setupCalls[i].target).call(setupCalls[i].data);
            if (!avoidWarning || data.length != 0) {
                uint256 stopPlease;
                stopPlease += 1;
            }
            hevm.stopPrank();
        }

        // Do any final setup within config
        config.beforeAllPrepareMarketplace(alice, bob);
    }

    function _prepareMarketplaces(BaseMarketConfig[] memory configs) public {
        for (uint256 i; i < configs.length; i++) {
            beforeAllPrepareMarketplaceTest(configs[i]);
        }
    }

    function _sameName(string memory name1, string memory name2)
        internal
        pure
        returns (bool)
    {
        return keccak256(bytes(name1)) == keccak256(bytes(name2));
    }

    function _replaceAddress(
        bytes memory data,
        address oldAddress,
        address newAddress
    ) internal pure returns (bytes memory) {
        bytes memory tempBytes = new bytes(20);
        bytes32 replacementAddress = bytes32(uint256(uint160(newAddress)) << 96);

        // Iterate over the bytes data one byte at a time.
        for (uint256 i; i < data.length - 20; i++) {
            // Using each possible starting byte, create a temporary 20 byte
            // candidate address chunk.
            for (uint256 j; j < 20; j++) {
                tempBytes[j] = data[i + j];
            }

            // If the candidate address chunk matches the old address, replace.
            if (
                (uint256(bytes32(tempBytes)) >> 96)
                    == uint256(uint160(oldAddress))
            ) {
                // Replace the old address with the new address.
                for (uint256 j; j < 20; j++) {
                    data[i + j] = replacementAddress[j];
                }
            }
        }

        return data;
    }

    function _formatLog(string memory name, string memory label)
        internal
        pure
        returns (string memory)
    {
        return string(abi.encodePacked("[", name, "] ", label, " -- gas"));
    }

    function _logNotSupported(string memory name, string memory label)
        internal
    {
        // Omit for now to mitigate spammy logging.
        // emit log(
        //     string(
        //         abi.encodePacked("[", name, "] ", label, " -- NOT SUPPORTED")
        //     )
        // );
    }

    function _createSeaportOrder(BasicOrderParameters memory basicParams)
        internal
        returns (AdvancedOrder memory)
    {
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

    function _benchmarkCallWithParams(
        string memory name,
        string memory label,
        bool shouldLog,
        bool shouldLogGasDelta,
        address sender,
        TestCallParameters memory params
    ) internal returns (uint256 gasUsed) {
        hevm.startPrank(sender);
        uint256 gasDelta;
        bool success;
        assembly {
            let to := mload(params)
            let value := mload(add(params, 0x20))
            let data := mload(add(params, 0x40))
            let ptr := add(data, 0x20)
            let len := mload(data)
            let g1 := gas()
            success := call(gas(), to, value, ptr, len, 0, 0)
            let g2 := gas()
            gasDelta := sub(g1, g2)
            if iszero(success) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }
        hevm.stopPrank();

        gasUsed = gasDelta + _additionalGasFee(params.data);

        if (shouldLog) {
            emit log_named_uint(_formatLog(name, label), gasUsed);

            // After the && is just safety.
            if (shouldLogGasDelta && gasUsed > costOfLastCall) {
                emit log_named_uint("gas delta", gasUsed - costOfLastCall);
                console.log("");
            }

            costOfLastCall = gasUsed;
        }
    }

    function _additionalGasFee(bytes memory callData)
        internal
        pure
        returns (uint256)
    {
        uint256 sum = 21000;
        for (uint256 i = 0; i < callData.length; i++) {
            // zero bytes = 4, non-zero = 16
            sum += callData[i] == 0 ? 4 : 16;
        }
        // Remove call opcode cost
        return sum - 2600;
    }
}
