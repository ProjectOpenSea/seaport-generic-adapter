// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import { StdCheats } from "forge-std/StdCheats.sol";

import { Vm } from "forge-std/Vm.sol";

import { ItemType } from "seaport-types/lib/ConsiderationEnums.sol";

import { SpentItem } from "seaport-types/lib/ConsiderationStructs.sol";

import {
    AdapterHelperLib,
    Approval,
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

address constant VM_ADDRESS =
    address(uint160(uint256(keccak256("hevm cheat code"))));
Vm constant vm = Vm(VM_ADDRESS);

contract GenericMarketplaceTest is BaseMarketplaceTest, StdCheats {
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

    // TODO: think about globally or at least in some cases changing the payload
    // to make the taker the sidecar to get around the taker == msg.sender
    // requirements.

    // TODO: set up the no-flashloan versions of all these. Should be possible
    // to just use the native tokens sent by the fulfiller.

    // TODO: after establishing marketplace coverage, think about doing
    // more permutations with flashloans in general

    // TODO: after all that, start working on fulfilling multiple orders in a
    // single transaction.

    // Maybe eventually useful when it's time for combining orders from multiple
    // marketplaces.
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

        Approval[] memory approvalsOfTheAdapter = new Approval[](4);
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

        vm.deal(address(flashloanOfferer), type(uint128).max);

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
    ) internal prepareTest(config) {
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
            _benchmarkCallWithParams(
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

            _benchmarkCallWithParams(
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
    ) internal prepareTest(config) {
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
            return;
        }

        try config.getPayload_BuyOfferedERC721WithEther(
            context, standardERC721, 100
        ) returns (TestOrderPayload memory payload) {
            _benchmarkCallWithParams(
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
                address(context.fulfiller),
                address(seaport),
                address(context.flashloanOfferer),
                address(context.adapter),
                address(context.sidecar),
                flashloanArray,
                standardERC721
            );

            _benchmarkCallWithParams(
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

            _benchmarkCallWithParams(
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
    ) internal prepareTest(config) {
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
            return;
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
                address(context.fulfiller),
                address(seaport),
                address(context.flashloanOfferer),
                address(context.adapter),
                address(context.sidecar),
                flashloanArray,
                standardERC721
            );

            _benchmarkCallWithParams(
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
    ) internal prepareTest(config) {
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
            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
                false,
                false,
                alice,
                payload.submitOrder
            );

            assertEq(test1155_1.balanceOf(alice, 1), 1);
            assertEq(test1155_1.balanceOf(bob, 1), 0);

            _benchmarkCallWithParams(
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
    ) internal prepareTest(config) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC1155WithEther_ListOnChain_Adapter)";
        test1155_1.mint(alice, 1, 1);

        TestOrderContext memory context = TestOrderContext(
            true, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        TestItem1155 memory item = TestItem1155(address(test1155_1), 1, 1);

        try config.getPayload_BuyOfferedERC1155WithEther(context, item, 100)
        returns (TestOrderPayload memory payload) {
            _benchmarkCallWithParams(
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
                address(context.fulfiller),
                address(seaport),
                address(context.flashloanOfferer),
                address(context.adapter),
                address(context.sidecar),
                flashloanArray,
                item
            );

            _benchmarkCallWithParams(
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

            _benchmarkCallWithParams(
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
    ) internal prepareTest(config) {
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
            return;
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
                address(context.fulfiller),
                address(seaport),
                address(context.flashloanOfferer),
                address(context.adapter),
                address(context.sidecar),
                flashloanArray,
                item
            );

            _benchmarkCallWithParams(
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
    ) internal prepareTest(config) {
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
            _benchmarkCallWithParams(
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

            _benchmarkCallWithParams(
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
    ) internal prepareTest(config) {
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
            return;
        }

        TestOrderContext memory context = TestOrderContext(
            true, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        test721_1.mint(alice, 1);
        token1.mint(bob, 100);

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
            _benchmarkCallWithParams(
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
                address(context.fulfiller),
                address(seaport),
                address(context.flashloanOfferer),
                address(context.adapter),
                address(context.sidecar),
                new Flashloan[](0),
                new TestItem721[](0)
            );

            _benchmarkCallWithParams(
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

            _benchmarkCallWithParams(
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

    function benchmark_BuyOfferedERC721WithERC20_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC721WithERC20_Adapter)";

        // LR, X2Y2, and 0x are not working. Blur, Foundation, and Sudo don't
        // support this lol.
        if (
            _sameName(config.name(), looksRareConfig.name())
                || _sameName(config.name(), x2y2Config.name())
                || _sameName(config.name(), zeroExConfig.name())
        ) {
            _logNotSupported(config.name(), testLabel);
            return;
        }

        TestOrderContext memory context = TestOrderContext(
            true, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        test721_1.mint(alice, 1);
        token1.mint(bob, 100);
        try config.getPayload_BuyOfferedERC721WithERC20(
            TestOrderContext(
                false, true, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            standardERC721,
            TestItem20(address(token1), 100)
        ) returns (TestOrderPayload memory payload) {
            assertEq(test721_1.ownerOf(1), alice);
            assertEq(token1.balanceOf(alice), 0);
            assertEq(token1.balanceOf(bob), 100);

            payload.executeOrder = AdapterHelperLib
                .createSeaportWrappedTestCallParameters(
                payload.executeOrder,
                address(context.fulfiller),
                address(seaport),
                address(context.flashloanOfferer),
                address(context.adapter),
                address(context.sidecar),
                new Flashloan[](0),
                new TestItem721[](0)
            );

            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill, w/ Sig*")),
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

    function benchmark_BuyOfferedERC721WithWETH_ListOnChain(
        BaseMarketConfig config
    ) internal prepareTest(config) {
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
            _benchmarkCallWithParams(
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

            _benchmarkCallWithParams(
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
            return;
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
                address(context.fulfiller),
                address(seaport),
                address(context.flashloanOfferer),
                address(context.adapter),
                address(context.sidecar),
                new Flashloan[](0),
                new TestItem721[](0)
            );

            _benchmarkCallWithParams(
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
    ) internal prepareTest(config) {
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
            return;
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
            _benchmarkCallWithParams(
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
                address(context.fulfiller),
                address(seaport),
                address(context.flashloanOfferer),
                address(context.adapter),
                address(context.sidecar),
                new Flashloan[](0),
                new TestItem721[](0)
            );

            _benchmarkCallWithParams(
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

            _benchmarkCallWithParams(
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
    ) internal prepareTest(config) {
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
            _benchmarkCallWithParams(
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

            _benchmarkCallWithParams(
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
    ) internal prepareTest(config) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC1155WithERC20_ListOnChain_Adapter)";

        _logNotSupported(config.name(), testLabel);
        return;

        // test1155_1.mint(alice, 1, 1);
        // token1.mint(bob, 100);
        // try config.getPayload_BuyOfferedERC1155WithERC20(
        //     TestOrderContext(
        //         true, true, alice, bob, flashloanOfferer, adapter, sidecar
        //     ),
        //     TestItem1155(address(test1155_1), 1, 1),
        //     TestItem20(address(token1), 100)
        // ) returns (TestOrderPayload memory payload) {
        //     _benchmarkCallWithParams(
        //         config.name(),
        //         string(abi.encodePacked(testLabel, " List")),
        //         alice,
        //         payload.submitOrder
        //     );

        //     assertEq(test1155_1.balanceOf(alice, 1), 1);
        //     assertEq(token1.balanceOf(alice), 0);
        //     assertEq(token1.balanceOf(bob), 100);

        //     _benchmarkCallWithParams(
        //         config.name(),
        //         string(abi.encodePacked(testLabel, " Fulfill*")),true,
        //         bob,
        //         payload.executeOrder
        //     );

        //     assertEq(test1155_1.balanceOf(bob, 1), 1);
        //     assertEq(token1.balanceOf(alice), 100);
        //     assertEq(token1.balanceOf(bob), 0);
        // } catch {
        //     _logNotSupported(config.name(), testLabel);
        // }
    }

    function benchmark_BuyOfferedERC1155WithERC20(BaseMarketConfig config)
        internal
        prepareTest(config)
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

            _benchmarkCallWithParams(
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
    ) internal prepareTest(config) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC1155WithERC20_Adapter)";

        _logNotSupported(config.name(), testLabel);
        return;

        // test1155_1.mint(alice, 1, 1);
        // token1.mint(bob, 100);
        // try config.getPayload_BuyOfferedERC1155WithERC20(
        //     TestOrderContext(
        //         false, true, alice, bob, flashloanOfferer, adapter, sidecar
        //     ),
        //     TestItem1155(address(test1155_1), 1, 1),
        //     TestItem20(address(token1), 100)
        // ) returns (TestOrderPayload memory payload) {
        //     assertEq(test1155_1.balanceOf(alice, 1), 1);
        //     assertEq(token1.balanceOf(alice), 0);
        //     assertEq(token1.balanceOf(bob), 100);

        //     _benchmarkCallWithParams(
        //         config.name(),
        //         string(abi.encodePacked(testLabel, " Fulfill w/ Sig*")),true,
        //         bob,
        //         payload.executeOrder
        //     );

        //     assertEq(test1155_1.balanceOf(bob, 1), 1);
        //     assertEq(token1.balanceOf(alice), 100);
        //     assertEq(token1.balanceOf(bob), 0);
        // } catch {
        //     _logNotSupported(config.name(), testLabel);
        // }
    }

    function benchmark_BuyOfferedERC20WithERC721_ListOnChain(
        BaseMarketConfig config
    ) internal prepareTest(config) {
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
            _benchmarkCallWithParams(
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

            _benchmarkCallWithParams(
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
    ) internal prepareTest(config) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC20WithERC721_ListOnChain_Adapter)";

        _logNotSupported(config.name(), testLabel);
        return;

        // token1.mint(alice, 100);
        // test721_1.mint(bob, 1);
        // try config.getPayload_BuyOfferedERC20WithERC721(
        //     TestOrderContext(
        //         true, true, alice, bob, flashloanOfferer, adapter, sidecar
        //     ),
        //     TestItem20(address(token1), 100),
        //     standardERC721
        // ) returns (TestOrderPayload memory payload) {
        //     _benchmarkCallWithParams(
        //         config.name(),
        //         string(abi.encodePacked(testLabel, " List")),
        //         alice,
        //         payload.submitOrder
        //     );

        //     assertEq(test721_1.ownerOf(1), bob);
        //     // Allow the market to escrow after listing
        //     assert(
        //         token1.balanceOf(alice) == 100
        //             || token1.balanceOf(config.market()) == 100
        //     );
        //     assertEq(token1.balanceOf(bob), 0);

        //     _benchmarkCallWithParams(
        //         config.name(),
        //         string(abi.encodePacked(testLabel, " Fulfill*")),true,
        //         bob,
        //         payload.executeOrder
        //     );

        //     assertEq(test721_1.ownerOf(1), alice);
        //     assertEq(token1.balanceOf(alice), 0);
        //     assertEq(token1.balanceOf(bob), 100);
        // } catch {
        //     _logNotSupported(config.name(), testLabel);
        // }
    }

    function benchmark_BuyOfferedERC20WithERC721(BaseMarketConfig config)
        internal
        prepareTest(config)
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

            _benchmarkCallWithParams(
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
    ) internal prepareTest(config) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC20WithERC721_Adapter)";

        _logNotSupported(config.name(), testLabel);
        return;

        // token1.mint(alice, 100);
        // test721_1.mint(bob, 1);
        // try config.getPayload_BuyOfferedERC20WithERC721(
        //     TestOrderContext(
        //         false, true, alice, bob, flashloanOfferer, adapter, sidecar
        //     ),
        //     TestItem20(address(token1), 100),
        //     standardERC721
        // ) returns (TestOrderPayload memory payload) {
        //     assertEq(test721_1.ownerOf(1), bob);
        //     assertEq(token1.balanceOf(alice), 100);
        //     assertEq(token1.balanceOf(bob), 0);

        //     _benchmarkCallWithParams(
        //         config.name(),
        //         string(abi.encodePacked(testLabel, " Fulfill w/ Sig*")),true,
        //         bob,
        //         payload.executeOrder
        //     );

        //     assertEq(test721_1.ownerOf(1), alice);
        //     assertEq(token1.balanceOf(alice), 0);
        //     assertEq(token1.balanceOf(bob), 100);
        // } catch {
        //     _logNotSupported(config.name(), testLabel);
        // }
    }

    function benchmark_BuyOfferedWETHWithERC721_ListOnChain(
        BaseMarketConfig config
    ) internal prepareTest(config) {
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
            _benchmarkCallWithParams(
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

            _benchmarkCallWithParams(
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
    ) internal prepareTest(config) {
        string memory testLabel =
            "(benchmark_BuyOfferedWETHWithERC721_ListOnChain_Adapter)";

        // TODO: Come back and see if it's possible to make 0x work.
        if (
            _sameName(config.name(), zeroExConfig.name())
                || _sameName(config.name(), looksRareConfig.name())
                || _sameName(config.name(), x2y2Config.name())
        ) {
            _logNotSupported(config.name(), testLabel);
            return;
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
            _benchmarkCallWithParams(
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
                address(context.fulfiller),
                address(seaport),
                address(context.flashloanOfferer),
                address(context.adapter),
                address(context.sidecar),
                new Flashloan[](0),
                new TestItem721[](0)
            );

            _benchmarkCallWithParams(
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

            _benchmarkCallWithParams(
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
            return;
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
                address(context.fulfiller),
                address(seaport),
                address(context.flashloanOfferer),
                address(context.adapter),
                address(context.sidecar),
                new Flashloan[](0),
                new TestItem721[](0)
            );

            _benchmarkCallWithParams(
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
    ) internal prepareTest(config) {
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
            _benchmarkCallWithParams(
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

            _benchmarkCallWithParams(
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
    ) internal prepareTest(config) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC20WithERC1155_ListOnChain_Adapter)";

        _logNotSupported(config.name(), testLabel);
        return;

        // TestOrderContext memory context = TestOrderContext(
        //     true, true, alice, bob, flashloanOfferer, adapter, sidecar
        // );
        // token1.mint(alice, 100);
        // test1155_1.mint(bob, 1, 1);
        // try config.getPayload_BuyOfferedERC20WithERC1155(
        //     context,
        //     TestItem20(address(token1), 100),
        //     TestItem1155(address(test1155_1), 1, 1)
        // ) returns (TestOrderPayload memory payload) {
        //     _benchmarkCallWithParams(
        //         config.name(),
        //         string(abi.encodePacked(testLabel, " List")),
        //         alice,
        //         payload.submitOrder
        //     );

        //     assertEq(test1155_1.balanceOf(bob, 1), 1);
        //     assertEq(token1.balanceOf(alice), 100);
        //     assertEq(token1.balanceOf(bob), 0);

        //     _benchmarkCallWithParams(
        //         config.name(),
        //         string(abi.encodePacked(testLabel, " Fulfill*")),true,
        //         bob,
        //         payload.executeOrder
        //     );

        //     assertEq(test1155_1.balanceOf(alice, 1), 1);
        //     assertEq(token1.balanceOf(alice), 0);
        //     assertEq(token1.balanceOf(bob), 100);
        // } catch {
        //     _logNotSupported(config.name(), testLabel);
        // }
    }

    function benchmark_BuyOfferedERC20WithERC1155(BaseMarketConfig config)
        internal
        prepareTest(config)
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

            _benchmarkCallWithParams(
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
    ) internal prepareTest(config) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC20WithERC1155_Adapter)";

        _logNotSupported(config.name(), testLabel);
        return;

        // TestOrderContext memory context = TestOrderContext(
        //     false, true, alice, bob, flashloanOfferer, adapter, sidecar
        // );
        // token1.mint(alice, 100);
        // test1155_1.mint(bob, 1, 1);
        // try config.getPayload_BuyOfferedERC20WithERC1155(
        //     context,
        //     TestItem20(address(token1), 100),
        //     TestItem1155(address(test1155_1), 1, 1)
        // ) returns (TestOrderPayload memory payload) {
        //     assertEq(test1155_1.balanceOf(bob, 1), 1);
        //     assertEq(token1.balanceOf(alice), 100);
        //     assertEq(token1.balanceOf(bob), 0);

        //     _benchmarkCallWithParams(
        //         config.name(),
        //         string(abi.encodePacked(testLabel, " Fulfill w/ Sig*")),true,
        //         bob,
        //         payload.executeOrder
        //     );

        //     assertEq(test1155_1.balanceOf(alice, 1), 1);
        //     assertEq(token1.balanceOf(alice), 0);
        //     assertEq(token1.balanceOf(bob), 100);
        // } catch {
        //     _logNotSupported(config.name(), testLabel);
        // }
    }

    function benchmark_BuyOfferedERC721WithERC1155_ListOnChain(
        BaseMarketConfig config
    ) internal prepareTest(config) {
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
            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
                false,
                false,
                alice,
                payload.submitOrder
            );

            assertEq(test721_1.ownerOf(1), alice);
            assertEq(test1155_1.balanceOf(bob, 1), 1);

            _benchmarkCallWithParams(
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
    ) internal prepareTest(config) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC721WithERC1155_ListOnChain_Adapter)";

        _logNotSupported(config.name(), testLabel);
        return;

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
        //     _benchmarkCallWithParams(
        //         config.name(),
        //         string(abi.encodePacked(testLabel, " List")),
        //         alice,
        //         payload.submitOrder
        //     );

        //     assertEq(test721_1.ownerOf(1), alice);
        //     assertEq(test1155_1.balanceOf(bob, 1), 1);

        //     _benchmarkCallWithParams(
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

            _benchmarkCallWithParams(
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
    ) internal prepareTest(config) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC721WithERC1155_Adapter)";

        _logNotSupported(config.name(), testLabel);
        return;

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

        //     _benchmarkCallWithParams(
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
    ) internal prepareTest(config) {
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
            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
                false,
                false,
                alice,
                payload.submitOrder
            );

            assertEq(test721_1.ownerOf(1), bob);
            assertEq(test1155_1.balanceOf(alice, 1), 1);

            _benchmarkCallWithParams(
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
    ) internal prepareTest(config) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC1155WithERC721_ListOnChain_Adapter)";

        _logNotSupported(config.name(), testLabel);
        return;

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
        //     _benchmarkCallWithParams(
        //         config.name(),
        //         string(abi.encodePacked(testLabel, " List")),
        //         alice,
        //         payload.submitOrder
        //     );

        //     assertEq(test721_1.ownerOf(1), bob);
        //     assertEq(test1155_1.balanceOf(alice, 1), 1);

        //     _benchmarkCallWithParams(
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

            _benchmarkCallWithParams(
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
    ) internal prepareTest(config) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC1155WithERC721_Adapter)";

        // _logNotSupported(config.name(), testLabel);
        // return;

        TestOrderContext memory context = TestOrderContext(
            false, true, alice, bob, flashloanOfferer, adapter, sidecar
        );
        test1155_1.mint(alice, 1, 1);
        test721_1.mint(bob, 1);

        TestItem1155 memory item1155 = TestItem1155(address(test1155_1), 1, 1);
        try config.getPayload_BuyOfferedERC1155WithERC721(
            context, item1155, standardERC721
        ) returns (TestOrderPayload memory payload) {
            assertEq(test721_1.ownerOf(1), bob);
            assertEq(test1155_1.balanceOf(alice, 1), 1);

            payload.executeOrder = AdapterHelperLib
                .createSeaportWrappedTestCallParameters(
                payload.executeOrder,
                address(context.fulfiller),
                address(seaport),
                address(context.flashloanOfferer),
                address(context.adapter),
                address(context.sidecar),
                new Flashloan[](0),
                standardERC721
            );

            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill w/ Sig*")),
                true,
                true,
                bob,
                payload.executeOrder
            );

            assertEq(test721_1.ownerOf(1), alice);
            assertEq(test1155_1.balanceOf(bob, 1), 1);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function benchmark_BuyOfferedERC721WithEtherFee_ListOnChain(
        BaseMarketConfig config
    ) internal prepareTest(config) {
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
            _benchmarkCallWithParams(
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

            _benchmarkCallWithParams(
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
    ) internal prepareTest(config) {
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
            return;
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
            _benchmarkCallWithParams(
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
                address(context.fulfiller),
                address(seaport),
                address(context.flashloanOfferer),
                address(context.adapter),
                address(context.sidecar),
                flashloanArray,
                standardERC721
            );

            // Increase the value to account for the fee.
            payload.executeOrder.value = 505;

            _benchmarkCallWithParams(
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

            _benchmarkCallWithParams(
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
    ) internal prepareTest(config) {
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
            return;
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
                address(context.fulfiller),
                address(seaport),
                address(context.flashloanOfferer),
                address(context.adapter),
                address(context.sidecar),
                flashloanArray,
                standardERC721
            );

            _benchmarkCallWithParams(
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
    ) internal prepareTest(config) {
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
            _benchmarkCallWithParams(
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

            _benchmarkCallWithParams(
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
    ) internal prepareTest(config) {
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
            return;
        }

        try config.getPayload_BuyOfferedERC721WithEtherTwoFeeRecipient(
            context, standardERC721, 100, feeReciever1, 5, feeReciever2, 5
        ) returns (TestOrderPayload memory payload) {
            _benchmarkCallWithParams(
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
                address(context.fulfiller),
                address(seaport),
                address(context.flashloanOfferer),
                address(context.adapter),
                address(context.sidecar),
                flashloanArray,
                standardERC721
            );

            _benchmarkCallWithParams(
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
    ) internal prepareTest(config) {
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

            _benchmarkCallWithParams(
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
    ) internal prepareTest(config) {
        string memory testLabel =
            "(benchmark_BuyOfferedERC721WithEtherFeeTwoRecipients_Adapter)";
        test721_1.mint(alice, 1);

        if (
            _sameName(config.name(), x2y2Config.name())
                || _sameName(config.name(), blurConfig.name())
        ) {
            _logNotSupported(config.name(), testLabel);
            return;
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
                address(context.fulfiller),
                address(seaport),
                address(context.flashloanOfferer),
                address(context.adapter),
                address(context.sidecar),
                flashloanArray,
                standardERC721
            );

            _benchmarkCallWithParams(
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
    ) internal prepareTest(config) {
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
            _benchmarkCallWithParams(
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

            _benchmarkCallWithParams(
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
    ) internal prepareTest(config) {
        string memory testLabel =
            "(benchmark_BuyTenOfferedERC721WithEther_ListOnChain_Adapter)";

        if (
            _sameName(config.name(), blurConfig.name())
                || _sameName(config.name(), sudoswapConfig.name())
        ) {
            _logNotSupported(config.name(), testLabel);
            return;
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
            return;
        }

        try config.getPayload_BuyOfferedManyERC721WithEther(context, items, 100)
        returns (TestOrderPayload memory payload) {
            _benchmarkCallWithParams(
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
                address(context.fulfiller),
                address(seaport),
                address(context.flashloanOfferer),
                address(context.adapter),
                address(context.sidecar),
                flashloanArray,
                items
            );

            _benchmarkCallWithParams(
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

            _benchmarkCallWithParams(
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
    ) internal prepareTest(config) {
        string memory testLabel =
            "(benchmark_BuyTenOfferedERC721WithEther_Adapter)";

        if (_sameName(config.name(), blurConfig.name())) {
            _logNotSupported(config.name(), testLabel);
            return;
        }

        if (_sameName(config.name(), x2y2Config.name())) {
            _logNotSupported(config.name(), testLabel);
            return;
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
            TestOrderContext(
                false, true, alice, bob, flashloanOfferer, adapter, sidecar
            ),
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
                address(context.fulfiller),
                address(seaport),
                address(context.flashloanOfferer),
                address(context.adapter),
                address(context.sidecar),
                flashloanArray,
                items
            );

            _benchmarkCallWithParams(
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
    ) internal prepareTest(config) {
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

            _benchmarkCallWithParams(
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
    ) internal prepareTest(config) {
        string memory testLabel =
            "(benchmark_BuyTenOfferedERC721WithEtherDistinctOrders_Adapter)";

        if (
            _sameName(config.name(), x2y2Config.name())
                || _sameName(config.name(), blurConfig.name())
                || _sameName(config.name(), sudoswapConfig.name())
        ) {
            _logNotSupported(config.name(), testLabel);
            return;
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
                address(contexts[0].fulfiller),
                address(seaport),
                address(contexts[0].flashloanOfferer),
                address(contexts[0].adapter),
                address(contexts[0].sidecar),
                flashloanArray,
                items
            );

            _benchmarkCallWithParams(
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
    ) internal prepareTest(config) {
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
            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
                false,
                false,
                alice,
                payload.submitOrder
            );

            // @dev checking ownership here (when nfts are escrowed in different contracts) is messy so we skip it for now

            _benchmarkCallWithParams(
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
    ) internal prepareTest(config) {
        string memory testLabel =
            "(benchmark_BuyTenOfferedERC721WithEtherDistinctOrders_ListOnChain_Adapter)";

        if (
            _sameName(config.name(), x2y2Config.name())
                || _sameName(config.name(), blurConfig.name())
                || _sameName(config.name(), sudoswapConfig.name())
        ) {
            _logNotSupported(config.name(), testLabel);
            return;
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
            _benchmarkCallWithParams(
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
                address(contexts[0].fulfiller),
                address(seaport),
                address(contexts[0].flashloanOfferer),
                address(contexts[0].adapter),
                address(contexts[0].sidecar),
                flashloanArray,
                items
            );

            _benchmarkCallWithParams(
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
    ) internal prepareTest(config) {
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

            _benchmarkCallWithParams(
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
    ) internal prepareTest(config) {
        string memory testLabel =
            "(benchmark_BuyTenOfferedERC721WithErc20DistinctOrders_Adapter)";

        _logNotSupported(config.name(), testLabel);
        return;

        // token1.mint(bob, 1045);
        // TestOrderContext[] memory contexts = new TestOrderContext[](10);
        // TestItem721[] memory nfts = new TestItem721[](10);
        // uint256[] memory erc20Amounts = new uint256[](10);

        // for (uint256 i = 0; i < 10; i++) {
        //     test721_1.mint(alice, i + 1);
        //     nfts[i] = TestItem721(address(test721_1), i + 1);
        //     contexts[i] = TestOrderContext(
        //         false, true, alice, bob, flashloanOfferer, adapter, sidecar
        //     );
        //     erc20Amounts[i] = 100 + i;
        // }

        // try config.getPayload_BuyOfferedManyERC721WithErc20DistinctOrders(
        //     contexts, address(token1), nfts, erc20Amounts
        // ) returns (TestOrderPayload memory payload) {
        //     for (uint256 i = 1; i <= 10; i++) {
        //         assertEq(test721_1.ownerOf(i), alice);
        //     }

        //     _benchmarkCallWithParams(
        //         config.name(),
        //         string(abi.encodePacked(testLabel, " Fulfill /w Sigs*")),
        //         bob,
        //         payload.executeOrder
        //     );

        //     for (uint256 i = 1; i <= 10; i++) {
        //         assertEq(test721_1.ownerOf(i), bob);
        //     }
        //     assertEq(token1.balanceOf(alice), 1045);
        // } catch {
        //     _logNotSupported(config.name(), testLabel);
        // }
    }

    function benchmark_BuyTenOfferedERC721WithErc20DistinctOrders_ListOnChain(
        BaseMarketConfig config
    ) internal prepareTest(config) {
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
            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
                false,
                false,
                alice,
                payload.submitOrder
            );

            _benchmarkCallWithParams(
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
    ) internal prepareTest(config) {
        string memory testLabel =
            "(benchmark_BuyTenOfferedERC721WithErc20DistinctOrders_ListOnChain_Adapter)";

        _logNotSupported(config.name(), testLabel);
        return;

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
        //     _benchmarkCallWithParams(
        //         config.name(),
        //         string(abi.encodePacked(testLabel, " List")),
        //         alice,
        //         payload.submitOrder
        //     );

        //     _benchmarkCallWithParams(
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
    ) internal prepareTest(config) {
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

            _benchmarkCallWithParams(
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
    ) internal prepareTest(config) {
        string memory testLabel =
            "(benchmark_BuyTenOfferedERC721WithWETHDistinctOrders_Adapter)";

        // Blur already doesn't support this, adapter or otherwise.
        if (
            _sameName(config.name(), zeroExConfig.name())
                || _sameName(config.name(), x2y2Config.name())
                || _sameName(config.name(), sudoswapConfig.name())
        ) {
            _logNotSupported(config.name(), testLabel);
            return;
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
                address(contexts[0].fulfiller),
                address(seaport),
                address(contexts[0].flashloanOfferer),
                address(contexts[0].adapter),
                address(contexts[0].sidecar),
                new Flashloan[](0),
                new TestItem721[](0)
            );

            _benchmarkCallWithParams(
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
    ) internal prepareTest(config) {
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
            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
                false,
                false,
                alice,
                payload.submitOrder
            );

            _benchmarkCallWithParams(
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
    ) internal prepareTest(config) {
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
            _benchmarkCallWithParams(
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
                address(contexts[0].fulfiller),
                address(seaport),
                address(contexts[0].flashloanOfferer),
                address(contexts[0].adapter),
                address(contexts[0].sidecar),
                new Flashloan[](0),
                new TestItem721[](0)
            );

            _benchmarkCallWithParams(
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

            _benchmarkCallWithParams(
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
    {
        string memory testLabel = "(benchmark_MatchOrders_ABCA_Adapter)";

        _logNotSupported(config.name(), testLabel);
        return;

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

        //     _benchmarkCallWithParams(
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
        _;
    }

    function signDigest(address signer, bytes32 digest)
        external
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
    ) internal {
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

        uint256 gasUsed = gasDelta + _additionalGasFee(params.data);

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
