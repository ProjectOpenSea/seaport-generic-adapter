// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import { StdCheats } from "forge-std/StdCheats.sol";

import { Vm } from "forge-std/Vm.sol";

import { ConsiderationItemLib } from "seaport-sol/lib/ConsiderationItemLib.sol";

import { ItemType } from "seaport-types/lib/ConsiderationEnums.sol";

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

import { OrderType } from "seaport-types/lib/ConsiderationEnums.sol";

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
    TestOrderPayload,
    TestOrderContext,
    TestCallParameters,
    TestItem20,
    TestItem721,
    TestItem1155
} from "./utils/Types.sol";

import "../src/contracts/test/TestERC20.sol";
import "../src/contracts/test/TestERC721.sol";
import "../src/contracts/test/TestERC1155.sol";
import "./utils/BaseMarketplaceTest.sol";

import "forge-std/console.sol";

import { ConsiderationTypeHashes } from
    "../src/marketplaces/seaport-1.4/lib/ConsiderationTypeHashes.sol";

import { OrderParametersLib } from "seaport-sol/lib/OrderParametersLib.sol";

address constant VM_ADDRESS =
    address(uint160(uint256(keccak256("hevm cheat code"))));
Vm constant vm = Vm(VM_ADDRESS);

contract GenericMarketplaceTest is
    BaseMarketplaceTest,
    StdCheats,
    ConsiderationTypeHashes
{
    using OrderParametersLib for OrderParameters;
    using OrderParametersLib for OrderParameters[];
    using ConsiderationItemLib for ConsiderationItem;
    using ConsiderationItemLib for ConsiderationItem[];

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

    uint256 public costOfLastCall;

    TestItem721 standardERC721;
    TestItem721 standardERC721Two;

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

    // TODO: after all that, start working on fulfilling multiple orders in a
    // single transaction.

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

    function _doSetup() internal {
        testFlashloanOfferer = FlashloanOffererInterface(
            deployCode(
                "out/FlashloanOfferer.sol/FlashloanOfferer.json",
                abi.encode(address(seaport))
            )
        );

        vm.recordLogs();

        testAdapter = GenericAdapterInterface(
            deployCode(
                "out/GenericAdapter.sol/GenericAdapter.json",
                abi.encode(address(seaport), address(testFlashloanOfferer))
            )
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();

        testSidecar = GenericAdapterSidecarInterface(
            abi.decode(entries[0].data, (address))
        );

        flashloanOfferer = address(testFlashloanOfferer);
        adapter = address(testAdapter);
        sidecar = address(testSidecar);

        standardERC721 = TestItem721(address(test721_1), 1);
        standardERC721Two = TestItem721(address(test721_1), 2);

        // This is where the users of the adapter approve the adapter to
        // transfer their tokens.
        address[] memory adapterUsers = new address[](3);
        adapterUsers[0] = address(alice);
        adapterUsers[1] = address(bob);
        adapterUsers[2] = address(cal);

        Approval[] memory approvalsOfTheAdapter = new Approval[](5);
        approvalsOfTheAdapter[0] = Approval(address(token1), ItemType.ERC20);
        approvalsOfTheAdapter[1] = Approval(address(test721_1), ItemType.ERC721);
        approvalsOfTheAdapter[2] =
            Approval(address(test1155_1), ItemType.ERC1155);
        approvalsOfTheAdapter[3] = Approval(address(weth), ItemType.ERC20);

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
        approvalsByTheAdapter[0] = Approval(address(token1), ItemType.ERC20);
        approvalsByTheAdapter[1] = Approval(address(test721_1), ItemType.ERC721);
        approvalsByTheAdapter[2] =
            Approval(address(test1155_1), ItemType.ERC1155);
        approvalsByTheAdapter[3] = Approval(address(weth), ItemType.ERC20);

        bytes memory contextArg = AdapterHelperLib.createGenericAdapterContext(
            approvalsByTheAdapter, new Call[](0)
        );

        // Prank seaport to allow hitting the adapter directly.
        vm.prank(address(seaport));
        testAdapter.generateOrder(
            address(this), new SpentItem[](0), new SpentItem[](0), contextArg
        );

        vm.deal(flashloanOfferer, type(uint128).max);

        stdCastOfCharacters = CastOfCharacters({
            offerer: alice,
            fulfiller: bob,
            seaport: address(seaport),
            flashloanOfferer: flashloanOfferer,
            adapter: adapter,
            sidecar: sidecar
        });
    }

    function _prepareMarketplaces(BaseMarketConfig[] memory configs) public {
        for (uint256 i; i < configs.length; i++) {
            beforeAllPrepareMarketplaceTest(configs[i]);
        }
    }

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
            benchmark_BuyOfferedERC721WithEtherFee_ListOnChain(configs[0]);
        uint256 secondOrderGasUsed =
            benchmark_BuyOfferedERC1155WithEther_ListOnChain(configs[1]);
        uint256 thirdOrderGasUsed =
            benchmark_BuyOfferedERC721WithWETH(configs[2]);
        uint256 fourthOrderGasUsed =
            benchmark_BuyOfferedERC1155WithERC20(configs[3]);

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
        benchmark_BuyOfferedERC721WithEtherFee_ListOnChain_Adapter(configs[0]);
        uint256 secondOrderGasUsed =
            benchmark_BuyOfferedERC1155WithEther_ListOnChain_Adapter(configs[1]);
        uint256 thirdOrderGasUsed =
            benchmark_BuyOfferedERC721WithWETH_Adapter(configs[2]);
        uint256 fourthOrderGasUsed =
            benchmark_BuyOfferedERC1155WithERC20(configs[3]);

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
            CastOfCharacters(
                alice, bob, address(seaport), flashloanOfferer, adapter, sidecar
            ),
            new Flashloan[](1),
            new TestItem721[](1),
            new TestItem1155[](2),
            TestItem1155(address(test1155_1), 1, 1),
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
            infra.context,
            TestItem721(address(test721_1), 2),
            TestItem20(address(weth), 100)
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
        token1.mint(bob, 100);

        assertEq(token1.balanceOf(bob), 100);
        assertEq(token1.balanceOf(alice), 0);

        infra.flashloans[0] = Flashloan({
            amount: 605,
            itemType: ItemType.NATIVE,
            shouldCallback: true,
            recipient: address(adapter)
        });

        infra.erc721s[0] = TestItem721(address(test721_1), 1);
        infra.erc1155s[0] = TestItem1155(address(test1155_1), 1, 1);

        // This should provide all the info required for the aggregated orders.
        (infra.adapterOrders, infra.adapterFulfillments) = AdapterHelperLib
            .createSeaportWrappedTestCallParametersReturnGranular(
            infra.executionPayloads,
            infra.castOfCharacters,
            infra.flashloans,
            new ConsiderationItem[](0),
            new TestItem20[](0),
            infra.erc721s,
            infra.erc1155s
        );

        AdvancedOrder memory orderOffer1155;
        AdvancedOrder memory orderConsider155;

        {
            BasicOrderParameters memory params = configs[3]
                .getComponents_BuyOfferedERC1155WithERC20(
                alice,
                TestItem1155(address(test1155_1), 2, 1),
                TestItem20(address(token1), 100)
            );

            orderOffer1155 = _createSeaportOrder(params);

            params = configs[3].getComponents_BuyOfferedERC20WithERC1155(
                bob,
                TestItem20(address(token1), 100),
                TestItem1155(address(test1155_1), 2, 1)
            );

            orderConsider155 = _createSeaportOrder(params);
        }

        {
            infra.finalOrders[0] = infra.adapterOrders[0];
            infra.finalOrders[1] = infra.adapterOrders[1];
            infra.finalOrders[2] = infra.adapterOrders[2];
            infra.finalOrders[3] = orderOffer1155;
            infra.finalOrders[4] = orderConsider155;
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
                address(seaport), // target will definitely be seaport
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

        // Alice gets 100 token1
        assertEq(token1.balanceOf(alice), 100, "Alice did not get the token1");

        return gasUsed;
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

    // TODO: GO back and make sure the gas calculations are correct.

    function benchmarkMarket(BaseMarketConfig config) public {
        // This is kind of a weird spot for this setup, but the benchmarking
        // repo that this is cribbed from relies on recording logs to wipe them
        // out between function calls. So it's important to be careful where
        // you record logs, because it seems that they collide.
        _doSetup();

        beforeAllPrepareMarketplaceTest(config);

        benchmark_BuyOfferedERC1155WithERC20_ListOnChain(config);
        benchmark_BuyOfferedERC1155WithERC20_ListOnChain_Adapter(config);

        benchmark_BuyOfferedERC1155WithERC20(config);
        benchmark_BuyOfferedERC1155WithERC20_Adapter(config);

        benchmark_BuyOfferedERC1155WithERC721_ListOnChain(config);
        benchmark_BuyOfferedERC1155WithERC721_ListOnChain_Adapter(config);

        benchmark_BuyOfferedERC1155WithERC721(config);
        benchmark_BuyOfferedERC1155WithERC721_Adapter(config);

        benchmark_BuyOfferedERC1155WithEther_ListOnChain(config);
        benchmark_BuyOfferedERC1155WithEther_ListOnChain_Adapter(config);

        benchmark_BuyOfferedERC1155WithEther(config);
        benchmark_BuyOfferedERC1155WithEther_Adapter(config);

        benchmark_BuyOfferedERC20WithERC1155_ListOnChain(config);
        benchmark_BuyOfferedERC20WithERC1155_ListOnChain_Adapter(config);

        benchmark_BuyOfferedERC20WithERC1155(config);
        benchmark_BuyOfferedERC20WithERC1155_Adapter(config);

        benchmark_BuyOfferedERC20WithERC721_ListOnChain(config);
        benchmark_BuyOfferedERC20WithERC721_ListOnChain_Adapter(config);

        benchmark_BuyOfferedERC20WithERC721(config);
        benchmark_BuyOfferedERC20WithERC721_Adapter(config);

        benchmark_BuyOfferedERC721WithERC1155_ListOnChain(config);
        benchmark_BuyOfferedERC721WithERC1155_ListOnChain_Adapter(config);

        benchmark_BuyOfferedERC721WithERC1155(config);
        benchmark_BuyOfferedERC721WithERC1155_Adapter(config);

        benchmark_BuyOfferedERC721WithERC20_ListOnChain(config);
        benchmark_BuyOfferedERC721WithERC20_ListOnChain_Adapter(config);

        benchmark_BuyOfferedERC721WithERC20(config);
        benchmark_BuyOfferedERC721WithERC20_Adapter(config);

        benchmark_BuyOfferedERC721WithEther(config);
        benchmark_BuyOfferedERC721WithEther_Adapter(config);

        benchmark_BuyOfferedERC721WithEther_ListOnChain(config);
        benchmark_BuyOfferedERC721WithEther_ListOnChain_Adapter(config);

        benchmark_BuyOfferedERC721WithEtherFee(config);
        benchmark_BuyOfferedERC721WithEtherFee_Adapter(config);

        benchmark_BuyOfferedERC721WithEtherFee_ListOnChain(config);
        benchmark_BuyOfferedERC721WithEtherFee_ListOnChain_Adapter(config);

        benchmark_BuyOfferedERC721WithEtherFeeTwoRecipients(config);
        benchmark_BuyOfferedERC721WithEtherFeeTwoRecipients_Adapter(config);

        benchmark_BuyOfferedERC721WithEtherFeeTwoRecipients_ListOnChain(config);
        benchmark_BuyOfferedERC721WithEtherFeeTwoRecipients_ListOnChain_Adapter(
            config
        );

        benchmark_BuyOfferedERC721WithWETH(config);
        benchmark_BuyOfferedERC721WithWETH_Adapter(config);

        benchmark_BuyOfferedERC721WithWETH_ListOnChain(config);
        benchmark_BuyOfferedERC721WithWETH_ListOnChain_Adapter(config);

        benchmark_BuyOfferedWETHWithERC721_ListOnChain(config);
        benchmark_BuyOfferedWETHWithERC721_ListOnChain_Adapter(config);

        benchmark_BuyOfferedWETHWithERC721(config);
        benchmark_BuyOfferedWETHWithERC721_Adapter(config);

        benchmark_BuyTenOfferedERC721WithErc20DistinctOrders_ListOnChain(config);
        benchmark_BuyTenOfferedERC721WithErc20DistinctOrders_ListOnChain_Adapter(
            config
        );

        benchmark_BuyTenOfferedERC721WithErc20DistinctOrders(config);
        benchmark_BuyTenOfferedERC721WithErc20DistinctOrders_Adapter(config);

        benchmark_BuyTenOfferedERC721WithEther(config);
        benchmark_BuyTenOfferedERC721WithEther_Adapter(config);

        benchmark_BuyTenOfferedERC721WithEther_ListOnChain(config);
        benchmark_BuyTenOfferedERC721WithEther_ListOnChain_Adapter(config);

        benchmark_BuyTenOfferedERC721WithEtherDistinctOrders(config);
        benchmark_BuyTenOfferedERC721WithEtherDistinctOrders_Adapter(config);

        benchmark_BuyTenOfferedERC721WithEtherDistinctOrders_ListOnChain(config);
        benchmark_BuyTenOfferedERC721WithEtherDistinctOrders_ListOnChain_Adapter(
            config
        );

        benchmark_BuyTenOfferedERC721WithWETHDistinctOrders(config);
        benchmark_BuyTenOfferedERC721WithWETHDistinctOrders_Adapter(config);

        benchmark_BuyTenOfferedERC721WithWETHDistinctOrders_ListOnChain(config);
        benchmark_BuyTenOfferedERC721WithWETHDistinctOrders_ListOnChain_Adapter(
            config
        );

        benchmark_MatchOrders_ABCA(config);
        benchmark_MatchOrders_ABCA_Adapter(config);
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

    /*//////////////////////////////////////////////////////////////
                        Tests
    //////////////////////////////////////////////////////////////*/

    function benchmark_BuyOfferedERC721WithEther_ListOnChain(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC721WithEther_ListOnChain)";
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

    function benchmark_BuyOfferedERC721WithEther_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC721WithEther_ListOnChain_Adapter)";
        test721_1.mint(alice, 1);

        TestOrderContext memory context = TestOrderContext(
            true, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        // LR and X2Y2 require that the msg.sender is also the taker.
        if (
            _sameName(config.name(), looksRareConfig.name())
                || _sameName(config.name(), x2y2Config.name())
                || _sameName(config.name(), sudoswapConfig.name())
                || _sameName(config.name(), blurConfig.name())
        ) {
            _logNotSupported(config.name(), testLabel);
            return 0;
        }

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
                recipient: address(adapter)
            });

            Flashloan[] memory flashloanArray = new Flashloan[](1);
            flashloanArray[0] = flashloan;

            payload.executeOrder = AdapterHelperLib
                .createSeaportWrappedTestCallParameters(
                payload.executeOrder,
                stdCastOfCharacters,
                flashloanArray,
                new ConsiderationItem[](0),
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
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function benchmark_BuyOfferedERC721WithEther(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(benchmark_BuyOfferedERC721WithEther)";
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

    function benchmark_BuyOfferedERC721WithEther_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC721WithEther_Adapter)";
        test721_1.mint(alice, 1);

        TestOrderContext memory context = TestOrderContext(
            false, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        // LR and X2Y2 require that the msg.sender is also the taker.
        if (
            _sameName(config.name(), looksRareConfig.name())
                || _sameName(config.name(), x2y2Config.name())
            // Not sure why sudo isn't working.
            || _sameName(config.name(), sudoswapConfig.name())
                || _sameName(config.name(), blurConfig.name())
        ) {
            _logNotSupported(config.name(), testLabel);
            return 0;
        }

        try config.getPayload_BuyOfferedERC721WithEther(
            context, standardERC721, 100
        ) returns (TestOrderPayload memory payload) {
            assertEq(test721_1.ownerOf(1), alice);

            Flashloan memory flashloan = Flashloan({
                amount: 100,
                itemType: ItemType.NATIVE,
                shouldCallback: true,
                recipient: address(adapter)
            });

            Flashloan[] memory flashloanArray = new Flashloan[](1);
            flashloanArray[0] = flashloan;

            payload.executeOrder = AdapterHelperLib
                .createSeaportWrappedTestCallParameters(
                payload.executeOrder,
                stdCastOfCharacters,
                flashloanArray,
                new ConsiderationItem[](0),
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

    function benchmark_BuyOfferedERC1155WithEther_ListOnChain(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC1155WithEther_ListOnChain)";
        test1155_1.mint(alice, 1, 1);
        try config.getPayload_BuyOfferedERC1155WithEther(
            TestOrderContext(
                true, false, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            TestItem1155(address(test1155_1), 1, 1),
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

    function benchmark_BuyOfferedERC1155WithEther_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC1155WithEther_ListOnChain_Adapter)";
        test1155_1.mint(alice, 1, 1);

        TestOrderContext memory context = TestOrderContext(
            true, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        TestItem1155 memory item = TestItem1155(address(test1155_1), 1, 1);

        try config.getPayload_BuyOfferedERC1155WithEther(context, item, 100)
        returns (TestOrderPayload memory payload) {
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
                recipient: address(adapter)
            });

            Flashloan[] memory flashloanArray = new Flashloan[](1);
            flashloanArray[0] = flashloan;

            payload.executeOrder = AdapterHelperLib
                .createSeaportWrappedTestCallParameters(
                payload.executeOrder,
                stdCastOfCharacters,
                flashloanArray,
                new ConsiderationItem[](0),
                item
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

    function benchmark_BuyOfferedERC1155WithEther(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(benchmark_BuyOfferedERC1155WithEther)";
        test1155_1.mint(alice, 1, 1);
        try config.getPayload_BuyOfferedERC1155WithEther(
            TestOrderContext(
                false, false, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            TestItem1155(address(test1155_1), 1, 1),
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

    function benchmark_BuyOfferedERC1155WithEther_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC1155WithEther_Adapter)";
        test1155_1.mint(alice, 1, 1);

        TestOrderContext memory context = TestOrderContext(
            false, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        TestItem1155 memory item = TestItem1155(address(test1155_1), 1, 1);

        // LR and X2Y2 require that the msg.sender is also the taker.
        if (
            _sameName(config.name(), looksRareConfig.name())
                || _sameName(config.name(), x2y2Config.name())
        ) {
            _logNotSupported(config.name(), testLabel);
            return 0;
        }

        try config.getPayload_BuyOfferedERC1155WithEther(context, item, 100)
        returns (TestOrderPayload memory payload) {
            assertEq(test1155_1.balanceOf(alice, 1), 1);

            Flashloan memory flashloan = Flashloan({
                amount: 100,
                itemType: ItemType.NATIVE,
                shouldCallback: true,
                recipient: address(adapter)
            });

            Flashloan[] memory flashloanArray = new Flashloan[](1);
            flashloanArray[0] = flashloan;

            payload.executeOrder = AdapterHelperLib
                .createSeaportWrappedTestCallParameters(
                payload.executeOrder,
                stdCastOfCharacters,
                flashloanArray,
                new ConsiderationItem[](0),
                item
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

    function benchmark_BuyOfferedERC721WithERC20_ListOnChain(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC721WithERC20_ListOnChain)";
        test721_1.mint(alice, 1);
        token1.mint(bob, 100);
        try config.getPayload_BuyOfferedERC721WithERC20(
            TestOrderContext(
                true, false, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            standardERC721,
            TestItem20(address(token1), 100)
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
            assertEq(token1.balanceOf(alice), 0);
            assertEq(token1.balanceOf(bob), 100);

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill")),
                true,
                false,
                bob,
                payload.executeOrder
            );

            assertEq(test721_1.ownerOf(1), bob);
            assertEq(token1.balanceOf(alice), 100);
            assertEq(token1.balanceOf(bob), 0);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function benchmark_BuyOfferedERC721WithERC20_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC721WithERC20_ListOnChain_Adapter)";

        // LR, X2Y2, and 0x are not working. Blur, and Foundation don't
        // support this lol.
        // Sudoswap would support it, but Bob would have to have a way to get
        // tokens into the generic adapter sidecar before execution time.
        // TODO: Figure out how to get ERC20s into the adapter/sidecar before
        // execution time.
        if (
            _sameName(config.name(), looksRareConfig.name())
                || _sameName(config.name(), x2y2Config.name())
                || _sameName(config.name(), zeroExConfig.name())
                || _sameName(config.name(), sudoswapConfig.name())
        ) {
            _logNotSupported(config.name(), testLabel);
            return 0;
        }

        TestOrderContext memory context = TestOrderContext(
            true, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        test721_1.mint(alice, 1);
        token1.mint(bob, 100);

        // TODO: come back and tidy this up.
        vm.startPrank(context.sidecar);
        // Pretend like the sidecar has already approved the contract that sudo
        // uses to transfer tokens.
        token1.approve(0x5ba23BEAb987463a64BD05575D3D4a947DfDe32E, 100);
        vm.stopPrank();

        try config.getPayload_BuyOfferedERC721WithERC20(
            TestOrderContext(
                true, true, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            standardERC721,
            TestItem20(address(token1), 100)
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
            assertEq(token1.balanceOf(alice), 0);
            assertEq(token1.balanceOf(bob), 100);

            payload.executeOrder = AdapterHelperLib
                .createSeaportWrappedTestCallParameters(
                payload.executeOrder,
                stdCastOfCharacters,
                new Flashloan[](0),
                new ConsiderationItem[](0),
                new TestItem721[](0)
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
            assertEq(token1.balanceOf(alice), 100);
            assertEq(token1.balanceOf(bob), 0);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function benchmark_BuyOfferedERC721WithERC20(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(benchmark_BuyOfferedERC721WithERC20)";
        test721_1.mint(alice, 1);
        token1.mint(bob, 100);
        try config.getPayload_BuyOfferedERC721WithERC20(
            TestOrderContext(
                false, false, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            standardERC721,
            TestItem20(address(token1), 100)
        ) returns (TestOrderPayload memory payload) {
            assertEq(test721_1.ownerOf(1), alice);
            assertEq(token1.balanceOf(alice), 0);
            assertEq(token1.balanceOf(bob), 100);

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill, w/ Sig")),
                true,
                false,
                bob,
                payload.executeOrder
            );

            assertEq(test721_1.ownerOf(1), bob);
            assertEq(token1.balanceOf(alice), 100);
            assertEq(token1.balanceOf(bob), 0);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    ////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////

    function benchmark_BuyOfferedERC721WithERC20_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC721WithERC20_Adapter)";

        TestOrderContext memory context = TestOrderContext(
            false, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        if (
            _sameName(config.name(), x2y2Config.name())
                || _sameName(config.name(), looksRareConfig.name())
        ) {
            context.fulfiller = address(context.sidecar);
        }

        test721_1.mint(alice, 1);
        token1.mint(bob, 100);
        try config.getPayload_BuyOfferedERC721WithERC20(
            context, standardERC721, TestItem20(address(token1), 100)
        ) returns (TestOrderPayload memory payload) {
            // Put the context back.
            context.fulfiller = bob;

            assertEq(test721_1.ownerOf(1), alice);
            assertEq(token1.balanceOf(alice), 0);
            assertEq(token1.balanceOf(bob), 100);

            ConsiderationItem[] memory adapterOrderConsideration =
                new ConsiderationItem[](1);

            adapterOrderConsideration[0] = ConsiderationItemLib.empty()
                .withItemType(ItemType.ERC20).withToken(address(token1))
                .withIdentifierOrCriteria(0).withStartAmount(100).withEndAmount(100)
                .withRecipient(address(0));

            TestItem20[] memory erc20s;
            TestItem721[] memory erc721s;

            erc20s = new TestItem20[](0);
            erc721s = new TestItem721[](1);
            erc721s[0] = standardERC721;

            vm.prank(address(context.sidecar));
            token1.approve(address(context.sidecar), 100);

            payload.executeOrder = AdapterHelperLib
                .createSeaportWrappedTestCallParameters(
                payload.executeOrder,
                stdCastOfCharacters,
                new Flashloan[](0),
                adapterOrderConsideration,
                erc20s,
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
            assertEq(token1.balanceOf(alice), 100, "Alice did not get ERC20");
            assertEq(token1.balanceOf(bob), 0);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function benchmark_BuyOfferedERC721WithWETH_ListOnChain(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC721WithWETH_ListOnChain)";
        test721_1.mint(alice, 1);
        hevm.deal(bob, 100);
        hevm.prank(bob);
        weth.deposit{ value: 100 }();
        try config.getPayload_BuyOfferedERC721WithERC20(
            TestOrderContext(
                true, false, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            standardERC721,
            TestItem20(address(weth), 100)
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

    function benchmark_BuyOfferedERC721WithWETH_Adapter(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(benchmark_BuyOfferedERC721WithWETH_Adapter)";

        // Only Blur is working. These three error and the others skip bc not
        // supported.
        if (
            // X2Y2 gives an input sig error.
            _sameName(config.name(), x2y2Config.name())
            // LR and 0x try to transfer WETH from the sidecar.
            || _sameName(config.name(), looksRareConfig.name())
                || _sameName(config.name(), zeroExConfig.name())
        ) {
            _logNotSupported(config.name(), testLabel);
            return 0;
        }

        test721_1.mint(alice, 1);
        hevm.deal(bob, 100);
        hevm.prank(bob);
        weth.deposit{ value: 100 }();

        TestOrderContext memory context = TestOrderContext(
            false, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        try config.getPayload_BuyOfferedERC721WithWETH(
            context, standardERC721, TestItem20(address(weth), 100)
        ) returns (TestOrderPayload memory payload) {
            assertEq(test721_1.ownerOf(1), alice);
            assertEq(weth.balanceOf(alice), 0);
            assertEq(weth.balanceOf(bob), 100);

            if (!_sameName(config.name(), blurConfig.name())) {
                payload.executeOrder.data = _replaceAddress(
                    payload.executeOrder.data,
                    context.fulfiller,
                    context.sidecar
                );
            }

            payload.executeOrder = AdapterHelperLib
                .createSeaportWrappedTestCallParameters(
                payload.executeOrder,
                stdCastOfCharacters,
                new Flashloan[](0),
                new ConsiderationItem[](0),
                new TestItem721[](0)
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

    function benchmark_BuyOfferedERC721WithWETH_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC721WithWETH_ListOnChain_Adapter)";

        // LR and X2Y2 require that the msg.sender is also the taker.
        // 0x is OK with the sender and the taker being different, but it
        // appears to grab the weth straight from the msg.sender if the taker is
        // the null address and it reverts if the msg.sender is not the taker
        // and the taker on the order is an address other than the null address.
        if (
            _sameName(config.name(), looksRareConfig.name())
                || _sameName(config.name(), x2y2Config.name())
                || _sameName(config.name(), zeroExConfig.name())
        ) {
            _logNotSupported(config.name(), testLabel);
            return 0;
        }

        test721_1.mint(alice, 1);
        hevm.deal(bob, 100);
        hevm.prank(bob);
        weth.deposit{ value: 100 }();

        TestOrderContext memory context = TestOrderContext(
            true, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        try config.getPayload_BuyOfferedERC721WithERC20(
            context, standardERC721, TestItem20(address(weth), 100)
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

            payload.executeOrder = AdapterHelperLib
                .createSeaportWrappedTestCallParameters(
                payload.executeOrder,
                stdCastOfCharacters,
                new Flashloan[](0),
                new ConsiderationItem[](0),
                new TestItem721[](0)
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

    function benchmark_BuyOfferedERC721WithWETH(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(benchmark_BuyOfferedERC721WithWETH)";
        test721_1.mint(alice, 1);
        hevm.deal(bob, 100);
        hevm.prank(bob);
        weth.deposit{ value: 100 }();

        try config.getPayload_BuyOfferedERC721WithWETH(
            TestOrderContext(
                false, false, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            standardERC721,
            TestItem20(address(weth), 100)
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

    function benchmark_BuyOfferedERC1155WithERC20_ListOnChain(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC1155WithERC20_ListOnChain)";
        test1155_1.mint(alice, 1, 1);
        token1.mint(bob, 100);
        try config.getPayload_BuyOfferedERC1155WithERC20(
            TestOrderContext(
                true, false, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            TestItem1155(address(test1155_1), 1, 1),
            TestItem20(address(token1), 100)
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
            assertEq(token1.balanceOf(alice), 0);
            assertEq(token1.balanceOf(bob), 100);

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill")),
                true,
                false,
                bob,
                payload.executeOrder
            );

            assertEq(test1155_1.balanceOf(bob, 1), 1);
            assertEq(token1.balanceOf(alice), 100);
            assertEq(token1.balanceOf(bob), 0);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function benchmark_BuyOfferedERC1155WithERC20_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC1155WithERC20_ListOnChain_Adapter)";

        TestOrderContext memory context = TestOrderContext(
            true, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        test1155_1.mint(alice, 1, 1);
        token1.mint(bob, 100);
        try config.getPayload_BuyOfferedERC1155WithERC20(
            context,
            TestItem1155(address(test1155_1), 1, 1),
            TestItem20(address(token1), 100)
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
            assertEq(token1.balanceOf(alice), 0);
            assertEq(token1.balanceOf(bob), 100);

            ConsiderationItem[] memory adapterOrderConsideration =
                new ConsiderationItem[](1);

            adapterOrderConsideration[0] = ConsiderationItemLib.empty()
                .withItemType(ItemType.ERC20).withToken(address(token1))
                .withIdentifierOrCriteria(0).withStartAmount(100).withEndAmount(100)
                .withRecipient(address(0));

            payload.executeOrder = AdapterHelperLib
                .createSeaportWrappedTestCallParameters(
                payload.executeOrder,
                stdCastOfCharacters,
                new Flashloan[](0),
                adapterOrderConsideration,
                TestItem1155(address(test1155_1), 1, 1)
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
            assertEq(token1.balanceOf(alice), 100);
            assertEq(token1.balanceOf(bob), 0);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function benchmark_BuyOfferedERC1155WithERC20(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(benchmark_BuyOfferedERC1155WithERC20)";
        test1155_1.mint(alice, 1, 1);
        token1.mint(bob, 100);
        try config.getPayload_BuyOfferedERC1155WithERC20(
            TestOrderContext(
                false, false, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            TestItem1155(address(test1155_1), 1, 1),
            TestItem20(address(token1), 100)
        ) returns (TestOrderPayload memory payload) {
            assertEq(test1155_1.balanceOf(alice, 1), 1);
            assertEq(token1.balanceOf(alice), 0);
            assertEq(token1.balanceOf(bob), 100);

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill w/ Sig")),
                true,
                false,
                bob,
                payload.executeOrder
            );

            assertEq(test1155_1.balanceOf(bob, 1), 1);
            assertEq(token1.balanceOf(alice), 100);
            assertEq(token1.balanceOf(bob), 0);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function benchmark_BuyOfferedERC1155WithERC20_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC1155WithERC20_Adapter)";

        TestOrderContext memory context = TestOrderContext(
            false, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        // Cheat the context for LR.
        if (_sameName(config.name(), looksRareConfig.name())) {
            context.fulfiller = address(context.sidecar);
        }

        test1155_1.mint(alice, 1, 1);
        token1.mint(bob, 100);
        try config.getPayload_BuyOfferedERC1155WithERC20(
            context,
            TestItem1155(address(test1155_1), 1, 1),
            TestItem20(address(token1), 100)
        ) returns (TestOrderPayload memory payload) {
            // Put the context back.
            if (_sameName(config.name(), looksRareConfig.name())) {
                context.fulfiller = bob;
            }
            assertEq(test1155_1.balanceOf(alice, 1), 1);
            assertEq(token1.balanceOf(alice), 0);
            assertEq(token1.balanceOf(bob), 100);

            ConsiderationItem[] memory adapterOrderConsideration =
                new ConsiderationItem[](1);

            adapterOrderConsideration[0] = ConsiderationItemLib.empty()
                .withItemType(ItemType.ERC20).withToken(address(token1))
                .withIdentifierOrCriteria(0).withStartAmount(100).withEndAmount(100)
                .withRecipient(address(0));

            payload.executeOrder = AdapterHelperLib
                .createSeaportWrappedTestCallParameters(
                payload.executeOrder,
                stdCastOfCharacters,
                new Flashloan[](0),
                adapterOrderConsideration,
                TestItem1155(address(test1155_1), 1, 1)
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
            assertEq(token1.balanceOf(alice), 100);
            assertEq(token1.balanceOf(bob), 0);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function benchmark_BuyOfferedERC20WithERC721_ListOnChain(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC20WithERC721_ListOnChain)";
        token1.mint(alice, 100);
        test721_1.mint(bob, 1);
        try config.getPayload_BuyOfferedERC20WithERC721(
            TestOrderContext(
                true, false, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            TestItem20(address(token1), 100),
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
                token1.balanceOf(alice) == 100
                    || token1.balanceOf(config.market()) == 100
            );
            assertEq(token1.balanceOf(bob), 0);

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill")),
                true,
                false,
                bob,
                payload.executeOrder
            );

            assertEq(test721_1.ownerOf(1), alice);
            assertEq(token1.balanceOf(alice), 0);
            assertEq(token1.balanceOf(bob), 100);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function benchmark_BuyOfferedERC20WithERC721_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC20WithERC721_ListOnChain_Adapter)";

        // TODO: Look into why Sudo is broken.
        if (_sameName(config.name(), sudoswapConfig.name())) {
            _logNotSupported(config.name(), testLabel);
            return 0;
        }

        TestOrderContext memory context = TestOrderContext(
            true, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        token1.mint(alice, 100);
        test721_1.mint(bob, 1);
        try config.getPayload_BuyOfferedERC20WithERC721(
            context, TestItem20(address(token1), 100), standardERC721
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
                token1.balanceOf(alice) == 100
                    || token1.balanceOf(config.market()) == 100
            );
            assertEq(token1.balanceOf(bob), 0);

            ConsiderationItem[] memory adapterOrderConsideration =
                new ConsiderationItem[](1);

            adapterOrderConsideration[0] = ConsiderationItemLib.empty()
                .withItemType(ItemType.ERC721).withToken(address(test721_1))
                .withIdentifierOrCriteria(1).withStartAmount(1).withEndAmount(1)
                .withRecipient(address(0));

            TestItem20[] memory erc20s = new TestItem20[](1);
            erc20s[0] = TestItem20(address(token1), 100);

            // Look into why token1 requires an explicit approval lol.
            vm.prank(address(context.sidecar));
            token1.approve(address(context.sidecar), 100);

            payload.executeOrder = AdapterHelperLib
                .createSeaportWrappedTestCallParameters(
                payload.executeOrder,
                stdCastOfCharacters,
                new Flashloan[](0),
                adapterOrderConsideration,
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
            assertEq(token1.balanceOf(alice), 0);
            assertEq(token1.balanceOf(bob), 100);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function benchmark_BuyOfferedERC20WithERC721(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(benchmark_BuyOfferedERC20WithERC721)";
        token1.mint(alice, 100);
        test721_1.mint(bob, 1);
        try config.getPayload_BuyOfferedERC20WithERC721(
            TestOrderContext(
                false, false, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            TestItem20(address(token1), 100),
            standardERC721
        ) returns (TestOrderPayload memory payload) {
            assertEq(test721_1.ownerOf(1), bob);
            assertEq(token1.balanceOf(alice), 100);
            assertEq(token1.balanceOf(bob), 0);

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill w/ Sig")),
                true,
                false,
                bob,
                payload.executeOrder
            );

            assertEq(test721_1.ownerOf(1), alice);
            assertEq(token1.balanceOf(alice), 0);
            assertEq(token1.balanceOf(bob), 100);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function benchmark_BuyOfferedERC20WithERC721_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC20WithERC721_Adapter)";

        TestOrderContext memory context = TestOrderContext(
            false, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        // Cheat the context for LR and X2Y2.
        if (
            _sameName(config.name(), looksRareConfig.name())
                || _sameName(config.name(), x2y2Config.name())
        ) {
            context.fulfiller = address(context.sidecar);
        }

        token1.mint(alice, 100);
        test721_1.mint(bob, 1);
        try config.getPayload_BuyOfferedERC20WithERC721(
            context, TestItem20(address(token1), 100), standardERC721
        ) returns (TestOrderPayload memory payload) {
            // Put the context back.
            if (
                _sameName(config.name(), looksRareConfig.name())
                    || _sameName(config.name(), x2y2Config.name())
            ) {
                context.fulfiller = bob;
            }

            assertEq(test721_1.ownerOf(1), bob);
            assertEq(token1.balanceOf(alice), 100);
            assertEq(token1.balanceOf(bob), 0);

            ConsiderationItem[] memory adapterOrderConsideration =
                new ConsiderationItem[](1);

            adapterOrderConsideration[0] = ConsiderationItemLib.empty()
                .withItemType(ItemType.ERC721).withToken(address(test721_1))
                .withIdentifierOrCriteria(1).withStartAmount(1).withEndAmount(1)
                .withRecipient(address(0));

            TestItem20[] memory erc20s = new TestItem20[](1);
            erc20s[0] = TestItem20(address(token1), 100);

            // Look into why token1 requires an explicit approval lol.
            vm.prank(address(context.sidecar));
            token1.approve(address(context.sidecar), 100);

            payload.executeOrder = AdapterHelperLib
                .createSeaportWrappedTestCallParameters(
                payload.executeOrder,
                stdCastOfCharacters,
                new Flashloan[](0),
                adapterOrderConsideration,
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
            assertEq(token1.balanceOf(alice), 0);
            assertEq(token1.balanceOf(bob), 100);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function benchmark_BuyOfferedWETHWithERC721_ListOnChain(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyOfferedWETHWithERC721_ListOnChain)";
        hevm.deal(alice, 100);
        hevm.prank(alice);
        weth.deposit{ value: 100 }();
        test721_1.mint(bob, 1);
        try config.getPayload_BuyOfferedWETHWithERC721(
            TestOrderContext(
                true, false, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            TestItem20(address(weth), 100),
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

    function benchmark_BuyOfferedWETHWithERC721_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyOfferedWETHWithERC721_ListOnChain_Adapter)";

        // TODO: Come back and see if it's possible to make 0x work.
        if (
            _sameName(config.name(), zeroExConfig.name())
                || _sameName(config.name(), looksRareConfig.name())
                || _sameName(config.name(), x2y2Config.name())
        ) {
            _logNotSupported(config.name(), testLabel);
            return 0;
        }

        TestOrderContext memory context = TestOrderContext(
            true, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        hevm.deal(alice, 100);
        hevm.prank(alice);
        weth.deposit{ value: 100 }();
        test721_1.mint(bob, 1);

        try config.getPayload_BuyOfferedWETHWithERC721(
            context, TestItem20(address(weth), 100), standardERC721
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

            payload.executeOrder = AdapterHelperLib
                .createSeaportWrappedTestCallParameters(
                payload.executeOrder,
                stdCastOfCharacters,
                new Flashloan[](0),
                new ConsiderationItem[](0),
                new TestItem721[](0)
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

    function benchmark_BuyOfferedWETHWithERC721(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(benchmark_BuyOfferedWETHWithERC721)";
        hevm.deal(alice, 100);
        hevm.prank(alice);
        weth.deposit{ value: 100 }();
        test721_1.mint(bob, 1);
        try config.getPayload_BuyOfferedWETHWithERC721(
            TestOrderContext(
                false, false, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            TestItem20(address(weth), 100),
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

    function benchmark_BuyOfferedWETHWithERC721_Adapter(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(benchmark_BuyOfferedWETHWithERC721_Adapter)";

        // Only Blur works.  Invalid signer error for 0x and the rest aren't
        // supported. Sender errors for LR and X2Y2.
        if (
            _sameName(config.name(), zeroExConfig.name())
                || _sameName(config.name(), looksRareConfig.name())
                || _sameName(config.name(), x2y2Config.name())
        ) {
            _logNotSupported(config.name(), testLabel);
            return 0;
        }

        TestOrderContext memory context = TestOrderContext(
            false, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        hevm.deal(alice, 100);
        hevm.prank(alice);
        weth.deposit{ value: 100 }();
        test721_1.mint(bob, 1);
        try config.getPayload_BuyOfferedWETHWithERC721(
            context, TestItem20(address(weth), 100), standardERC721
        ) returns (TestOrderPayload memory payload) {
            assertEq(test721_1.ownerOf(1), bob);
            assertEq(weth.balanceOf(alice), 100);
            assertEq(weth.balanceOf(bob), 0);

            payload.executeOrder = AdapterHelperLib
                .createSeaportWrappedTestCallParameters(
                payload.executeOrder,
                stdCastOfCharacters,
                new Flashloan[](0),
                new ConsiderationItem[](0),
                new TestItem721[](0)
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
            assertEq(weth.balanceOf(alice), 0);
            assertEq(weth.balanceOf(bob), 100);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function benchmark_BuyOfferedERC20WithERC1155_ListOnChain(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC20WithERC1155_ListOnChain)";
        TestOrderContext memory context = TestOrderContext(
            true, false, alice, bob, flashloanOfferer, adapter, sidecar
        );
        token1.mint(alice, 100);
        test1155_1.mint(bob, 1, 1);
        try config.getPayload_BuyOfferedERC20WithERC1155(
            context,
            TestItem20(address(token1), 100),
            TestItem1155(address(test1155_1), 1, 1)
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
            assertEq(token1.balanceOf(alice), 100);
            assertEq(token1.balanceOf(bob), 0);

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill")),
                true,
                false,
                bob,
                payload.executeOrder
            );

            assertEq(test1155_1.balanceOf(alice, 1), 1);
            assertEq(token1.balanceOf(alice), 0);
            assertEq(token1.balanceOf(bob), 100);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function benchmark_BuyOfferedERC20WithERC1155_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC20WithERC1155_ListOnChain_Adapter)";

        TestOrderContext memory context = TestOrderContext(
            true, true, alice, bob, flashloanOfferer, adapter, sidecar
        );
        token1.mint(alice, 100);
        test1155_1.mint(bob, 1, 1);
        try config.getPayload_BuyOfferedERC20WithERC1155(
            context,
            TestItem20(address(token1), 100),
            TestItem1155(address(test1155_1), 1, 1)
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
            assertEq(token1.balanceOf(alice), 100);
            assertEq(token1.balanceOf(bob), 0);

            ConsiderationItem[] memory adapterOrderConsideration =
                new ConsiderationItem[](1);

            adapterOrderConsideration[0] = ConsiderationItemLib.empty()
                .withItemType(ItemType.ERC1155).withToken(address(test1155_1))
                .withIdentifierOrCriteria(1).withStartAmount(1).withEndAmount(1)
                .withRecipient(address(0));

            TestItem20[] memory erc20s = new TestItem20[](1);
            erc20s[0] = TestItem20(address(token1), 100);

            // Look into why token1 requires an explicit approval lol.
            vm.prank(address(context.sidecar));
            token1.approve(address(context.sidecar), 100);

            payload.executeOrder = AdapterHelperLib
                .createSeaportWrappedTestCallParameters(
                payload.executeOrder,
                stdCastOfCharacters,
                new Flashloan[](0),
                adapterOrderConsideration,
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
            assertEq(token1.balanceOf(alice), 0);
            assertEq(token1.balanceOf(bob), 100);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function benchmark_BuyOfferedERC20WithERC1155(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(benchmark_BuyOfferedERC20WithERC1155)";
        TestOrderContext memory context = TestOrderContext(
            false, false, alice, bob, flashloanOfferer, adapter, sidecar
        );
        token1.mint(alice, 100);
        test1155_1.mint(bob, 1, 1);
        try config.getPayload_BuyOfferedERC20WithERC1155(
            context,
            TestItem20(address(token1), 100),
            TestItem1155(address(test1155_1), 1, 1)
        ) returns (TestOrderPayload memory payload) {
            assertEq(test1155_1.balanceOf(bob, 1), 1);
            assertEq(token1.balanceOf(alice), 100);
            assertEq(token1.balanceOf(bob), 0);

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill w/ Sig")),
                true,
                false,
                bob,
                payload.executeOrder
            );

            assertEq(test1155_1.balanceOf(alice, 1), 1);
            assertEq(token1.balanceOf(alice), 0);
            assertEq(token1.balanceOf(bob), 100);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function benchmark_BuyOfferedERC20WithERC1155_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC20WithERC1155_Adapter)";

        TestOrderContext memory context = TestOrderContext(
            false, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        // Cheat the context for LR.
        if (_sameName(config.name(), looksRareConfig.name())) {
            context.fulfiller = address(context.sidecar);
        }

        token1.mint(alice, 100);
        test1155_1.mint(bob, 1, 1);
        try config.getPayload_BuyOfferedERC20WithERC1155(
            context,
            TestItem20(address(token1), 100),
            TestItem1155(address(test1155_1), 1, 1)
        ) returns (TestOrderPayload memory payload) {
            // Put the context back.
            if (_sameName(config.name(), looksRareConfig.name())) {
                context.fulfiller = bob;
            }

            assertEq(test1155_1.balanceOf(bob, 1), 1);
            assertEq(token1.balanceOf(alice), 100);
            assertEq(token1.balanceOf(bob), 0);

            ConsiderationItem[] memory adapterOrderConsideration =
                new ConsiderationItem[](1);

            adapterOrderConsideration[0] = ConsiderationItemLib.empty()
                .withItemType(ItemType.ERC1155).withToken(address(test1155_1))
                .withIdentifierOrCriteria(1).withStartAmount(1).withEndAmount(1)
                .withRecipient(address(0));

            TestItem20[] memory erc20s = new TestItem20[](1);
            erc20s[0] = TestItem20(address(token1), 100);

            // Look into why token1 requires an explicit approval lol.
            vm.prank(address(context.sidecar));
            token1.approve(address(context.sidecar), 100);

            payload.executeOrder = AdapterHelperLib
                .createSeaportWrappedTestCallParameters(
                payload.executeOrder,
                stdCastOfCharacters,
                new Flashloan[](0),
                adapterOrderConsideration,
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
            assertEq(token1.balanceOf(alice), 0);
            assertEq(token1.balanceOf(bob), 100);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function benchmark_BuyOfferedERC721WithERC1155_ListOnChain(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC721WithERC1155_ListOnChain)";
        TestOrderContext memory context = TestOrderContext(
            true, false, alice, bob, flashloanOfferer, adapter, sidecar
        );
        test721_1.mint(alice, 1);
        test1155_1.mint(bob, 1, 1);
        try config.getPayload_BuyOfferedERC721WithERC1155(
            context, standardERC721, TestItem1155(address(test1155_1), 1, 1)
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

    function benchmark_BuyOfferedERC721WithERC1155_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC721WithERC1155_ListOnChain_Adapter)";

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
        //     TestItem1155(address(test1155_1), 1, 1)
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

    function benchmark_BuyOfferedERC721WithERC1155(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(benchmark_BuyOfferedERC721WithERC1155)";
        TestOrderContext memory context = TestOrderContext(
            false, false, alice, bob, flashloanOfferer, adapter, sidecar
        );
        test721_1.mint(alice, 1);
        test1155_1.mint(bob, 1, 1);
        try config.getPayload_BuyOfferedERC721WithERC1155(
            context, standardERC721, TestItem1155(address(test1155_1), 1, 1)
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

    function benchmark_BuyOfferedERC721WithERC1155_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC721WithERC1155_Adapter)";

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
        //     TestItem1155(address(test1155_1), 1, 1)
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

    function benchmark_BuyOfferedERC1155WithERC721_ListOnChain(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC1155WithERC721_ListOnChain)";
        TestOrderContext memory context = TestOrderContext(
            true, false, alice, bob, flashloanOfferer, adapter, sidecar
        );
        test1155_1.mint(alice, 1, 1);
        test721_1.mint(bob, 1);
        try config.getPayload_BuyOfferedERC1155WithERC721(
            context, TestItem1155(address(test1155_1), 1, 1), standardERC721
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

    function benchmark_BuyOfferedERC1155WithERC721_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC1155WithERC721_ListOnChain_Adapter)";

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
        //     TestItem1155(address(test1155_1), 1, 1),
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

    function benchmark_BuyOfferedERC1155WithERC721(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(benchmark_BuyOfferedERC1155WithERC721)";
        TestOrderContext memory context = TestOrderContext(
            false, false, alice, bob, flashloanOfferer, adapter, sidecar
        );
        test1155_1.mint(alice, 1, 1);
        test721_1.mint(bob, 1);
        try config.getPayload_BuyOfferedERC1155WithERC721(
            context, TestItem1155(address(test1155_1), 1, 1), standardERC721
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

    function benchmark_BuyOfferedERC1155WithERC721_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC1155WithERC721_Adapter)";

        // Only seaport so skipping here.
        _logNotSupported(config.name(), testLabel);
        return 0;

        // TestOrderContext memory context = TestOrderContext(
        //     false, true, alice, bob, flashloanOfferer, adapter, sidecar
        // );
        // test1155_1.mint(alice, 1, 1);
        // test721_1.mint(bob, 1);

        // TestItem1155 memory item1155 = TestItem1155(address(test1155_1), 1, 1);
        // try config.getPayload_BuyOfferedERC1155WithERC721(
        //     context, item1155, standardERC721
        // ) returns (TestOrderPayload memory payload) {
        //     assertEq(test721_1.ownerOf(1), bob);
        //     assertEq(test1155_1.balanceOf(alice, 1), 1);

        //     payload.executeOrder = AdapterHelperLib
        //         .createSeaportWrappedTestCallParameters(
        //         payload.executeOrder,
        //         address(context.fulfiller),
        //         address(seaport),
        //         address(context.flashloanOfferer),
        //         address(context.adapter),
        //         address(context.sidecar),
        //         new Flashloan[](0),
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

    function benchmark_BuyOfferedERC721WithEtherFee_ListOnChain(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC721WithEtherFee_ListOnChain)";
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

    function benchmark_BuyOfferedERC721WithEtherFee_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC721WithEtherFee_ListOnChain_Adapter)";
        test721_1.mint(alice, 1);

        // LR and X2Y2 require that the msg.sender is also the taker.
        if (
            _sameName(config.name(), looksRareConfig.name())
                || _sameName(config.name(), x2y2Config.name())
                || _sameName(config.name(), blurConfig.name())
        ) {
            _logNotSupported(config.name(), testLabel);
            return 0;
        }

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
                recipient: address(adapter)
            });

            Flashloan[] memory flashloanArray = new Flashloan[](1);
            flashloanArray[0] = flashloan;

            payload.executeOrder = AdapterHelperLib
                .createSeaportWrappedTestCallParameters(
                payload.executeOrder,
                stdCastOfCharacters,
                flashloanArray,
                new ConsiderationItem[](0),
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

    function benchmark_BuyOfferedERC721WithEtherFee(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(benchmark_BuyOfferedERC721WithEtherFee)";
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

    function benchmark_BuyOfferedERC721WithEtherFee_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC721WithEtherFee_Adapter)";
        test721_1.mint(alice, 1);

        TestOrderContext memory context = TestOrderContext(
            false, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        // LR and X2Y2 require that the msg.sender is also the taker.
        if (
            _sameName(config.name(), looksRareConfig.name())
                || _sameName(config.name(), x2y2Config.name())
                || _sameName(config.name(), blurConfig.name())
        ) {
            _logNotSupported(config.name(), testLabel);
            return 0;
        }

        try config.getPayload_BuyOfferedERC721WithEtherOneFeeRecipient(
            context, standardERC721, 100, feeReciever1, 5
        ) returns (TestOrderPayload memory payload) {
            assertEq(test721_1.ownerOf(1), alice);
            assertEq(feeReciever1.balance, 0);

            Flashloan memory flashloan = Flashloan({
                amount: 105,
                itemType: ItemType.NATIVE,
                shouldCallback: true,
                recipient: address(adapter)
            });

            Flashloan[] memory flashloanArray = new Flashloan[](1);
            flashloanArray[0] = flashloan;

            payload.executeOrder = AdapterHelperLib
                .createSeaportWrappedTestCallParameters(
                payload.executeOrder,
                stdCastOfCharacters,
                flashloanArray,
                new ConsiderationItem[](0),
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

    function benchmark_BuyOfferedERC721WithEtherFeeTwoRecipients_ListOnChain(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC721WithEtherFeeTwoRecipients_ListOnChain)";
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

    function benchmark_BuyOfferedERC721WithEtherFeeTwoRecipients_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC721WithEtherFeeTwoRecipients_ListOnChain_Adapter)";
        test721_1.mint(alice, 1);

        TestOrderContext memory context = TestOrderContext(
            true, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        if (
            _sameName(config.name(), x2y2Config.name())
                || _sameName(config.name(), blurConfig.name())
        ) {
            _logNotSupported(config.name(), testLabel);
            return 0;
        }

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
                recipient: address(adapter)
            });

            Flashloan[] memory flashloanArray = new Flashloan[](1);
            flashloanArray[0] = flashloan;

            payload.executeOrder = AdapterHelperLib
                .createSeaportWrappedTestCallParameters(
                payload.executeOrder,
                stdCastOfCharacters,
                flashloanArray,
                new ConsiderationItem[](0),
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

    function benchmark_BuyOfferedERC721WithEtherFeeTwoRecipients(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC721WithEtherFeeTwoRecipients)";
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

    function benchmark_BuyOfferedERC721WithEtherFeeTwoRecipients_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC721WithEtherFeeTwoRecipients_Adapter)";
        test721_1.mint(alice, 1);

        if (
            _sameName(config.name(), x2y2Config.name())
                || _sameName(config.name(), blurConfig.name())
        ) {
            _logNotSupported(config.name(), testLabel);
            return 0;
        }

        TestOrderContext memory context = TestOrderContext(
            false, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        try config.getPayload_BuyOfferedERC721WithEtherTwoFeeRecipient(
            context, standardERC721, 100, feeReciever1, 5, feeReciever2, 5
        ) returns (TestOrderPayload memory payload) {
            assertEq(test721_1.ownerOf(1), alice);
            assertEq(feeReciever1.balance, 0);
            assertEq(feeReciever2.balance, 0);

            Flashloan memory flashloan = Flashloan({
                amount: 110,
                itemType: ItemType.NATIVE,
                shouldCallback: true,
                recipient: address(adapter)
            });

            Flashloan[] memory flashloanArray = new Flashloan[](1);
            flashloanArray[0] = flashloan;

            payload.executeOrder = AdapterHelperLib
                .createSeaportWrappedTestCallParameters(
                payload.executeOrder,
                stdCastOfCharacters,
                flashloanArray,
                new ConsiderationItem[](0),
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

    function benchmark_BuyTenOfferedERC721WithEther_ListOnChain(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyTenOfferedERC721WithEther_ListOnChain)";

        TestItem721[] memory nfts = new TestItem721[](10);
        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
            nfts[i] = TestItem721(address(test721_1), i + 1);
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

    function benchmark_BuyTenOfferedERC721WithEther_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyTenOfferedERC721WithEther_ListOnChain_Adapter)";

        if (
            _sameName(config.name(), blurConfig.name())
                || _sameName(config.name(), sudoswapConfig.name())
        ) {
            _logNotSupported(config.name(), testLabel);
            return 0;
        }

        TestOrderContext memory context = TestOrderContext(
            true, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        TestItem721[] memory items = new TestItem721[](10);
        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
            items[i] = TestItem721(address(test721_1), i + 1);
        }

        if (_sameName(config.name(), x2y2Config.name())) {
            _logNotSupported(config.name(), testLabel);
            return 0;
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
                recipient: address(adapter)
            });

            Flashloan[] memory flashloanArray = new Flashloan[](1);
            flashloanArray[0] = flashloan;

            payload.executeOrder = AdapterHelperLib
                .createSeaportWrappedTestCallParameters(
                payload.executeOrder,
                stdCastOfCharacters,
                flashloanArray,
                new ConsiderationItem[](0),
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

    function benchmark_BuyTenOfferedERC721WithEther(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(benchmark_BuyTenOfferedERC721WithEther)";

        TestItem721[] memory nfts = new TestItem721[](10);
        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
            nfts[i] = TestItem721(address(test721_1), i + 1);
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

    function benchmark_BuyTenOfferedERC721WithEther_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyTenOfferedERC721WithEther_Adapter)";

        if (_sameName(config.name(), blurConfig.name())) {
            _logNotSupported(config.name(), testLabel);
            return 0;
        }

        if (_sameName(config.name(), x2y2Config.name())) {
            _logNotSupported(config.name(), testLabel);
            return 0;
        }

        TestOrderContext memory context = TestOrderContext(
            false, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        TestItem721[] memory items = new TestItem721[](10);
        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
            items[i] = TestItem721(address(test721_1), i + 1);
        }

        try config.getPayload_BuyOfferedManyERC721WithEther(
            context,
            items,
            100
        ) returns (TestOrderPayload memory payload) {
            for (uint256 i = 0; i < 10; i++) {
                assertEq(test721_1.ownerOf(i + 1), alice);
            }

            Flashloan memory flashloan = Flashloan({
                amount: 100,
                itemType: ItemType.NATIVE,
                shouldCallback: true,
                recipient: address(adapter)
            });

            Flashloan[] memory flashloanArray = new Flashloan[](1);
            flashloanArray[0] = flashloan;

            payload.executeOrder = AdapterHelperLib
                .createSeaportWrappedTestCallParameters(
                payload.executeOrder,
                stdCastOfCharacters,
                flashloanArray,
                new ConsiderationItem[](0),
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

    function benchmark_BuyTenOfferedERC721WithEtherDistinctOrders(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyTenOfferedERC721WithEtherDistinctOrders)";

        TestOrderContext[] memory contexts = new TestOrderContext[](10);
        TestItem721[] memory nfts = new TestItem721[](10);
        uint256[] memory ethAmounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
            nfts[i] = TestItem721(address(test721_1), i + 1);
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

    function benchmark_BuyTenOfferedERC721WithEtherDistinctOrders_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyTenOfferedERC721WithEtherDistinctOrders_Adapter)";

        if (
            _sameName(config.name(), x2y2Config.name())
                || _sameName(config.name(), blurConfig.name())
                || _sameName(config.name(), sudoswapConfig.name())
        ) {
            _logNotSupported(config.name(), testLabel);
            return 0;
        }

        TestOrderContext[] memory contexts = new TestOrderContext[](10);
        TestItem721[] memory items = new TestItem721[](10);
        uint256[] memory ethAmounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
            items[i] = TestItem721(address(test721_1), i + 1);
            contexts[i] = TestOrderContext(
                false, true, alice, bob, flashloanOfferer, adapter, sidecar
            );
            ethAmounts[i] = 100 + i;
        }

        try config.getPayload_BuyOfferedManyERC721WithEtherDistinctOrders(
            contexts, items, ethAmounts
        ) returns (TestOrderPayload memory payload) {
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
                recipient: address(adapter)
            });

            Flashloan[] memory flashloanArray = new Flashloan[](1);
            flashloanArray[0] = flashloan;

            payload.executeOrder = AdapterHelperLib
                .createSeaportWrappedTestCallParameters(
                payload.executeOrder,
                stdCastOfCharacters,
                flashloanArray,
                new ConsiderationItem[](0),
                items
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

    function benchmark_BuyTenOfferedERC721WithEtherDistinctOrders_ListOnChain(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyTenOfferedERC721WithEtherDistinctOrders_ListOnChain)";

        TestOrderContext[] memory contexts = new TestOrderContext[](10);
        TestItem721[] memory nfts = new TestItem721[](10);
        uint256[] memory ethAmounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
            nfts[i] = TestItem721(address(test721_1), i + 1);
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

    function benchmark_BuyTenOfferedERC721WithEtherDistinctOrders_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyTenOfferedERC721WithEtherDistinctOrders_ListOnChain_Adapter)";

        if (
            _sameName(config.name(), x2y2Config.name())
                || _sameName(config.name(), blurConfig.name())
                || _sameName(config.name(), sudoswapConfig.name())
        ) {
            _logNotSupported(config.name(), testLabel);
            return 0;
        }

        TestOrderContext[] memory contexts = new TestOrderContext[](10);
        TestItem721[] memory items = new TestItem721[](10);
        uint256[] memory ethAmounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
            items[i] = TestItem721(address(test721_1), i + 1);
            contexts[i] = TestOrderContext(
                true, true, alice, bob, flashloanOfferer, adapter, sidecar
            );
            ethAmounts[i] = 100 + i;
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

            Flashloan memory flashloan = Flashloan({
                amount: 0xfffffffffff,
                itemType: ItemType.NATIVE,
                shouldCallback: true,
                recipient: address(adapter)
            });

            Flashloan[] memory flashloanArray = new Flashloan[](1);
            flashloanArray[0] = flashloan;

            payload.executeOrder = AdapterHelperLib
                .createSeaportWrappedTestCallParameters(
                payload.executeOrder,
                stdCastOfCharacters,
                flashloanArray,
                new ConsiderationItem[](0),
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

            for (uint256 i = 1; i <= 10; i++) {
                assertEq(test721_1.ownerOf(i), bob);
            }
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function benchmark_BuyTenOfferedERC721WithErc20DistinctOrders(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyTenOfferedERC721WithErc20DistinctOrders)";

        token1.mint(bob, 1045);
        TestOrderContext[] memory contexts = new TestOrderContext[](10);
        TestItem721[] memory nfts = new TestItem721[](10);
        uint256[] memory erc20Amounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
            nfts[i] = TestItem721(address(test721_1), i + 1);
            contexts[i] = TestOrderContext(
                false, false, alice, bob, flashloanOfferer, adapter, sidecar
            );
            erc20Amounts[i] = 100 + i;
        }

        try config.getPayload_BuyOfferedManyERC721WithErc20DistinctOrders(
            contexts, address(token1), nfts, erc20Amounts
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
            assertEq(token1.balanceOf(alice), 1045);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function benchmark_BuyTenOfferedERC721WithErc20DistinctOrders_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyTenOfferedERC721WithErc20DistinctOrders_Adapter)";

        token1.mint(bob, 1045);
        TestOrderContext[] memory contexts = new TestOrderContext[](10);
        TestItem721[] memory nfts = new TestItem721[](10);
        uint256[] memory erc20Amounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
            nfts[i] = TestItem721(address(test721_1), i + 1);
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
            contexts, address(token1), nfts, erc20Amounts
        ) returns (TestOrderPayload memory payload) {
            if (
                _sameName(config.name(), x2y2Config.name())
                    || _sameName(config.name(), looksRareConfig.name())
            ) {
                for (uint256 i = 0; i < contexts.length; i++) {
                    contexts[i].fulfiller = bob;
                }
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

            adapterOrderConsideration[0] = ConsiderationItemLib.empty()
                .withItemType(ItemType.ERC20).withToken(address(token1))
                .withIdentifierOrCriteria(0).withStartAmount(totalERC20Amount)
                .withEndAmount(totalERC20Amount).withRecipient(address(0));

            vm.prank(address(contexts[0].sidecar));
            token1.approve(address(contexts[0].sidecar), totalERC20Amount);

            payload.executeOrder = AdapterHelperLib
                .createSeaportWrappedTestCallParameters(
                payload.executeOrder,
                stdCastOfCharacters,
                new Flashloan[](0),
                adapterOrderConsideration,
                nfts
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
            assertEq(token1.balanceOf(alice), 1045, "Alice did not get paid");
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function benchmark_BuyTenOfferedERC721WithErc20DistinctOrders_ListOnChain(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyTenOfferedERC721WithErc20DistinctOrders_ListOnChain)";

        token1.mint(bob, 1045);
        TestOrderContext[] memory contexts = new TestOrderContext[](10);
        TestItem721[] memory nfts = new TestItem721[](10);
        uint256[] memory erc20Amounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
            nfts[i] = TestItem721(address(test721_1), i + 1);
            contexts[i] = TestOrderContext(
                true, false, alice, bob, flashloanOfferer, adapter, sidecar
            );
            erc20Amounts[i] = 100 + i;
        }

        try config.getPayload_BuyOfferedManyERC721WithErc20DistinctOrders(
            contexts, address(token1), nfts, erc20Amounts
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

    function benchmark_BuyTenOfferedERC721WithErc20DistinctOrders_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyTenOfferedERC721WithErc20DistinctOrders_ListOnChain_Adapter)";

        _logNotSupported(config.name(), testLabel);
        return 0;

        // token1.mint(bob, 1045);
        // TestOrderContext[] memory contexts = new TestOrderContext[](10);
        // TestItem721[] memory nfts = new TestItem721[](10);
        // uint256[] memory erc20Amounts = new uint256[](10);

        // for (uint256 i = 0; i < 10; i++) {
        //     test721_1.mint(alice, i + 1);
        //     nfts[i] = TestItem721(address(test721_1), i + 1);
        //     contexts[i] = TestOrderContext(
        //         true, true, alice, bob, flashloanOfferer, adapter, sidecar
        //     );
        //     erc20Amounts[i] = 100 + i;
        // }

        // try config.getPayload_BuyOfferedManyERC721WithErc20DistinctOrders(
        //     contexts, address(token1), nfts, erc20Amounts
        // ) returns (TestOrderPayload memory payload) {
        //     gasUsed = _benchmarkCallWithParams(
        //         config.name(),
        //         string(abi.encodePacked(testLabel, " List")),
        //         alice,
        //         payload.submitOrder
        //     );

        //     gasUsed = _benchmarkCallWithParams(
        //         config.name(),
        //         string(abi.encodePacked(testLabel, " Fulfill*")),true,
        //         bob,
        //         payload.executeOrder
        //     );

        //     for (uint256 i = 1; i <= 10; i++) {
        //         assertEq(test721_1.ownerOf(i), bob);
        //     }
        // } catch {
        //     _logNotSupported(config.name(), testLabel);
        // }
    }

    function benchmark_BuyTenOfferedERC721WithWETHDistinctOrders(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyTenOfferedERC721WithWETHDistinctOrders)";

        hevm.deal(bob, 1045);
        hevm.prank(bob);
        weth.deposit{ value: 1045 }();
        TestOrderContext[] memory contexts = new TestOrderContext[](10);
        TestItem721[] memory nfts = new TestItem721[](10);
        uint256[] memory wethAmounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
            nfts[i] = TestItem721(address(test721_1), i + 1);
            contexts[i] = TestOrderContext(
                false, false, alice, bob, flashloanOfferer, adapter, sidecar
            );
            wethAmounts[i] = 100 + i;
        }

        try config.getPayload_BuyOfferedManyERC721WithWETHDistinctOrders(
            contexts, address(weth), nfts, wethAmounts
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

    function benchmark_BuyTenOfferedERC721WithWETHDistinctOrders_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyTenOfferedERC721WithWETHDistinctOrders_Adapter)";

        // Blur already doesn't support this, adapter or otherwise.
        if (
            _sameName(config.name(), zeroExConfig.name())
                || _sameName(config.name(), x2y2Config.name())
                || _sameName(config.name(), sudoswapConfig.name())
        ) {
            _logNotSupported(config.name(), testLabel);
            return 0;
        }

        hevm.deal(bob, 1045);
        hevm.prank(bob);
        weth.deposit{ value: 1045 }();
        TestOrderContext[] memory contexts = new TestOrderContext[](10);
        TestItem721[] memory nfts = new TestItem721[](10);
        uint256[] memory wethAmounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
            nfts[i] = TestItem721(address(test721_1), i + 1);
            contexts[i] = TestOrderContext(
                false, true, alice, bob, flashloanOfferer, adapter, sidecar
            );
            wethAmounts[i] = 100 + i;
        }

        try config.getPayload_BuyOfferedManyERC721WithWETHDistinctOrders(
            contexts, address(weth), nfts, wethAmounts
        ) returns (TestOrderPayload memory payload) {
            for (uint256 i = 1; i <= 10; i++) {
                assertEq(test721_1.ownerOf(i), alice);
            }

            payload.executeOrder = AdapterHelperLib
                .createSeaportWrappedTestCallParameters(
                payload.executeOrder,
                stdCastOfCharacters,
                new Flashloan[](0),
                new ConsiderationItem[](0),
                new TestItem721[](0)
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

    function benchmark_BuyTenOfferedERC721WithWETHDistinctOrders_ListOnChain(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyTenOfferedERC721WithWETHDistinctOrders_ListOnChain)";

        hevm.deal(bob, 1045);
        hevm.prank(bob);
        weth.deposit{ value: 1045 }();
        TestOrderContext[] memory contexts = new TestOrderContext[](10);
        TestItem721[] memory nfts = new TestItem721[](10);
        uint256[] memory wethAmounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
            nfts[i] = TestItem721(address(test721_1), i + 1);
            contexts[i] = TestOrderContext(
                true, false, alice, bob, flashloanOfferer, adapter, sidecar
            );
            wethAmounts[i] = 100 + i;
        }

        try config.getPayload_BuyOfferedManyERC721WithWETHDistinctOrders(
            contexts, address(weth), nfts, wethAmounts
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

    function benchmark_BuyTenOfferedERC721WithWETHDistinctOrders_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(benchmark_BuyTenOfferedERC721WithWETHDistinctOrders_ListOnChain_Adapter)";

        hevm.deal(bob, 1045);
        hevm.prank(bob);
        weth.deposit{ value: 1045 }();
        TestOrderContext[] memory contexts = new TestOrderContext[](10);
        TestItem721[] memory nfts = new TestItem721[](10);
        uint256[] memory wethAmounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
            nfts[i] = TestItem721(address(test721_1), i + 1);
            contexts[i] = TestOrderContext(
                true, true, alice, bob, flashloanOfferer, adapter, sidecar
            );
            wethAmounts[i] = 100 + i;
        }

        try config.getPayload_BuyOfferedManyERC721WithWETHDistinctOrders(
            contexts, address(weth), nfts, wethAmounts
        ) returns (TestOrderPayload memory payload) {
            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
                false,
                false,
                alice,
                payload.submitOrder
            );

            payload.executeOrder = AdapterHelperLib
                .createSeaportWrappedTestCallParameters(
                payload.executeOrder,
                stdCastOfCharacters,
                new Flashloan[](0),
                new ConsiderationItem[](0),
                new TestItem721[](0)
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
        nfts[1] = TestItem721(address(test721_1), 2);
        nfts[2] = TestItem721(address(test721_1), 3);

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
        // nfts[1] = TestItem721(address(test721_1), 2);
        // nfts[2] = TestItem721(address(test721_1), 3);

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
