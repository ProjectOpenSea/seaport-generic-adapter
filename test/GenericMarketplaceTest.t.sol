// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import { StdCheats } from "forge-std/StdCheats.sol";

import { Vm } from "forge-std/Vm.sol";

import { ItemType } from "seaport-types/lib/ConsiderationEnums.sol";

import { SpentItem } from "seaport-types/lib/ConsiderationStructs.sol";

import { AdapterHelperLib, Approval } from "../src/lib/AdapterHelperLib.sol";

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

    TestItem721 standardERC721;

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

    // TODO: think about globally or at least in some cases changing the payload
    // to make the taker the sidecar to get around the taker == msg.sender
    // requirements.

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

    // function testSudoswap() external {
    //     benchmarkMarket(sudoswapConfig);
    // }

    function testZeroEx() external {
        benchmarkMarket(zeroExConfig);
    }

    // Blur doesn't let you use ETH if you're not the msg.sender.
    // function testBlur() external {
    //     benchmarkMarket(blurConfig);
    // }

    function benchmarkMarket(BaseMarketConfig config) public {
        beforeAllPrepareMarketplaceTest(config);
        benchmark_BuyOfferedERC1155WithERC20_ListOnChain(config);
        benchmark_BuyOfferedERC1155WithERC20(config);
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
        benchmark_BuyOfferedERC721WithERC20(config);
        benchmark_BuyOfferedERC721WithEther_ListOnChain(config);
        benchmark_BuyOfferedERC721WithEther_ListOnChain_Adapter(config);
        benchmark_BuyOfferedERC721WithEther(config);
        benchmark_BuyOfferedERC721WithEther_Adapter(config);
        benchmark_BuyOfferedERC721WithEtherFee_ListOnChain(config);
        benchmark_BuyOfferedERC721WithEtherFee_ListOnChain_Adapter(config);
        benchmark_BuyOfferedERC721WithEtherFee(config);
        benchmark_BuyOfferedERC721WithEtherFee_Adapter(config);
        benchmark_BuyOfferedERC721WithEtherFeeTwoRecipients_ListOnChain(config);
        benchmark_BuyOfferedERC721WithEtherFeeTwoRecipients_ListOnChain_Adapter(
            config
        );
        benchmark_BuyOfferedERC721WithEtherFeeTwoRecipients(config);
        benchmark_BuyOfferedERC721WithEtherFeeTwoRecipients_Adapter(config);
        benchmark_BuyOfferedERC721WithWETH_ListOnChain(config);
        benchmark_BuyOfferedERC721WithWETH_ListOnChain_Adapter(config);
        benchmark_BuyOfferedERC721WithWETH(config);
        benchmark_BuyOfferedERC721WithWETH_Adapter(config);
        benchmark_BuyOfferedWETHWithERC721_ListOnChain(config);
        benchmark_BuyOfferedWETHWithERC721_ListOnChain_Adapter(config);
        benchmark_BuyOfferedWETHWithERC721(config);
        benchmark_BuyOfferedWETHWithERC721_Adapter(config);
        benchmark_BuyTenOfferedERC721WithErc20DistinctOrders_ListOnChain(config);
        // benchmark_BuyTenOfferedERC721WithErc20DistinctOrders_ListOnChain_Adapter(
        //     config
        // );
        benchmark_BuyTenOfferedERC721WithErc20DistinctOrders(config);
        // benchmark_BuyTenOfferedERC721WithErc20DistinctOrders_Adapter(config);
        benchmark_BuyTenOfferedERC721WithEther_ListOnChain(config);
        benchmark_BuyTenOfferedERC721WithEther_ListOnChain_Adapter(config);
        benchmark_BuyTenOfferedERC721WithEther(config);
        benchmark_BuyTenOfferedERC721WithEther_Adapter(config);
        benchmark_BuyTenOfferedERC721WithEtherDistinctOrders_ListOnChain(config);
        benchmark_BuyTenOfferedERC721WithEtherDistinctOrders_ListOnChain_Adapter(
            config
        );
        benchmark_BuyTenOfferedERC721WithEtherDistinctOrders(config);
        benchmark_BuyTenOfferedERC721WithEtherDistinctOrders_Adapter(config);
        benchmark_BuyTenOfferedERC721WithWETHDistinctOrders_ListOnChain(config);
        benchmark_BuyTenOfferedERC721WithWETHDistinctOrders_ListOnChain_Adapter(
            config
        );
        benchmark_BuyTenOfferedERC721WithWETHDistinctOrders(config);
        benchmark_BuyTenOfferedERC721WithWETHDistinctOrders_Adapter(config);
        benchmark_MatchOrders_ABCA(config);
        // benchmark_MatchOrders_ABCA_Adapter(config);
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

        vm.deal(address(flashloanOfferer), type(uint128).max);

        standardERC721 = TestItem721(address(test721_1), 1);

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

        // Do any final setup within config
        config.beforeAllPrepareMarketplace(alice, bob);
    }

    /*//////////////////////////////////////////////////////////////
                        Tests
    //////////////////////////////////////////////////////////////*/

    function benchmark_BuyOfferedERC721WithEther_ListOnChain(
        BaseMarketConfig config
    ) internal prepareTest(config) {
        string memory testLabel = "(ERC721 -> ETH List-On-Chain)";
        test721_1.mint(alice, 1);
        try config.getPayload_BuyOfferedERC721WithEther(
            TestOrderContext(
                true, false, alice, bob, flashloanOfferer, adapter, sidecar
            ), // TODO: come back and add a test for the wrapped version specifically
            TestItem721(address(test721_1), 1),
            100
        ) returns (TestOrderPayload memory payload) {
            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
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
        string memory testLabel = "(ERC721 -> ETH List-On-Chain)";
        test721_1.mint(alice, 1);

        TestOrderContext memory context = TestOrderContext(
            true, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        // LR and X2Y2 require that the msg.sender is also the taker.
        if (
            keccak256(bytes(config.name()))
                == keccak256(bytes(looksRareConfig.name()))
                || keccak256(bytes(config.name()))
                    == keccak256(bytes(x2y2Config.name()))
            // Not sure why sudo isn't working. Probably needs to be loaded up
            // with a deeper pool?
            || keccak256(bytes(config.name()))
                == keccak256(bytes(sudoswapConfig.name()))
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
                alice,
                payload.submitOrder
            );

            // Allow the market to escrow after listing
            assert(
                test721_1.ownerOf(1) == alice
                    || test721_1.ownerOf(1) == config.market()
            );

            payload.executeOrder = AdapterHelperLib
                .createSeaportWrappedTestCallParameters(
                payload.executeOrder,
                address(context.fulfiller),
                address(seaport),
                address(context.flashloanOfferer),
                address(context.adapter),
                address(context.sidecar),
                standardERC721
            );

            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill Through Adapter")),
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
        string memory testLabel = "(ERC721 -> ETH)";
        test721_1.mint(alice, 1);
        try config.getPayload_BuyOfferedERC721WithEther(
            TestOrderContext(
                false, false, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            TestItem721(address(test721_1), 1),
            100
        ) returns (TestOrderPayload memory payload) {
            assertEq(test721_1.ownerOf(1), alice);

            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill, w/ Sig")),
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
        string memory testLabel = "(ERC721 -> ETH)";
        test721_1.mint(alice, 1);

        TestOrderContext memory context = TestOrderContext(
            false, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        // LR and X2Y2 require that the msg.sender is also the taker.
        if (
            keccak256(bytes(config.name()))
                == keccak256(bytes(looksRareConfig.name()))
                || keccak256(bytes(config.name()))
                    == keccak256(bytes(x2y2Config.name()))
            // Not sure why sudo isn't working.
            || keccak256(bytes(config.name()))
                == keccak256(bytes(sudoswapConfig.name()))
        ) {
            _logNotSupported(config.name(), testLabel);
            return;
        }

        try config.getPayload_BuyOfferedERC721WithEther(
            context, standardERC721, 100
        ) returns (TestOrderPayload memory payload) {
            assertEq(test721_1.ownerOf(1), alice);

            payload.executeOrder = AdapterHelperLib
                .createSeaportWrappedTestCallParameters(
                payload.executeOrder,
                address(context.fulfiller),
                address(seaport),
                address(context.flashloanOfferer),
                address(context.adapter),
                address(context.sidecar),
                standardERC721
            );

            _benchmarkCallWithParams(
                config.name(),
                string(
                    abi.encodePacked(
                        testLabel, " Fulfill, w/ Sig Through Adapter"
                    )
                ),
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
        string memory testLabel = "(ERC1155 -> ETH List-On-Chain)";
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
                alice,
                payload.submitOrder
            );

            assertEq(test1155_1.balanceOf(alice, 1), 1);
            assertEq(test1155_1.balanceOf(bob, 1), 0);

            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill")),
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
        string memory testLabel = "(ERC1155 -> ETH List-On-Chain)";
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
                alice,
                payload.submitOrder
            );

            assertEq(test1155_1.balanceOf(alice, 1), 1);
            assertEq(test1155_1.balanceOf(bob, 1), 0);

            payload.executeOrder = AdapterHelperLib
                .createSeaportWrappedTestCallParameters(
                payload.executeOrder,
                address(context.fulfiller),
                address(seaport),
                address(context.flashloanOfferer),
                address(context.adapter),
                address(context.sidecar),
                item
            );

            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill Through Adapter")),
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
        string memory testLabel = "(ERC1155 -> ETH)";
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
        string memory testLabel = "(ERC1155 -> ETH)";
        test1155_1.mint(alice, 1, 1);

        TestOrderContext memory context = TestOrderContext(
            false, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        TestItem1155 memory item = TestItem1155(address(test1155_1), 1, 1);

        // LR and X2Y2 require that the msg.sender is also the taker.
        if (
            keccak256(bytes(config.name()))
                == keccak256(bytes(looksRareConfig.name()))
                || keccak256(bytes(config.name()))
                    == keccak256(bytes(x2y2Config.name()))
        ) {
            _logNotSupported(config.name(), testLabel);
            return;
        }

        try config.getPayload_BuyOfferedERC1155WithEther(context, item, 100)
        returns (TestOrderPayload memory payload) {
            assertEq(test1155_1.balanceOf(alice, 1), 1);

            payload.executeOrder = AdapterHelperLib
                .createSeaportWrappedTestCallParameters(
                payload.executeOrder,
                address(context.fulfiller),
                address(seaport),
                address(context.flashloanOfferer),
                address(context.adapter),
                address(context.sidecar),
                item
            );

            _benchmarkCallWithParams(
                config.name(),
                string(
                    abi.encodePacked(
                        testLabel, " Fulfill, w/ Sig Through Adapter"
                    )
                ),
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
        string memory testLabel = "(ERC721 -> ERC20 List-On-Chain)";
        test721_1.mint(alice, 1);
        token1.mint(bob, 100);
        try config.getPayload_BuyOfferedERC721WithERC20(
            TestOrderContext(
                true, false, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            TestItem721(address(test721_1), 1),
            TestItem20(address(token1), 100)
        ) returns (TestOrderPayload memory payload) {
            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
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
        string memory testLabel = "(ERC721 -> ERC20 List-On-Chain)";
        test721_1.mint(alice, 1);
        token1.mint(bob, 100);
        try config.getPayload_BuyOfferedERC721WithERC20(
            TestOrderContext(
                true, true, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            TestItem721(address(test721_1), 1),
            TestItem20(address(token1), 100)
        ) returns (TestOrderPayload memory payload) {
            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
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
                string(abi.encodePacked(testLabel, " Fulfill Through Adapter")),
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
        string memory testLabel = "(ERC721 -> ERC20)";
        test721_1.mint(alice, 1);
        token1.mint(bob, 100);
        try config.getPayload_BuyOfferedERC721WithERC20(
            TestOrderContext(
                false, false, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            TestItem721(address(test721_1), 1),
            TestItem20(address(token1), 100)
        ) returns (TestOrderPayload memory payload) {
            assertEq(test721_1.ownerOf(1), alice);
            assertEq(token1.balanceOf(alice), 0);
            assertEq(token1.balanceOf(bob), 100);

            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill, w/ Sig")),
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

    // TODO: Come back and think.
    function benchmark_BuyOfferedERC721WithERC20_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) {
        string memory testLabel = "(ERC721 -> ERC20)";
        test721_1.mint(alice, 1);
        token1.mint(bob, 100);
        try config.getPayload_BuyOfferedERC721WithERC20(
            TestOrderContext(
                false, true, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            TestItem721(address(test721_1), 1),
            TestItem20(address(token1), 100)
        ) returns (TestOrderPayload memory payload) {
            assertEq(test721_1.ownerOf(1), alice);
            assertEq(token1.balanceOf(alice), 0);
            assertEq(token1.balanceOf(bob), 100);

            _benchmarkCallWithParams(
                config.name(),
                string(
                    abi.encodePacked(
                        testLabel, " Fulfill, w/ Sig Through Adapter"
                    )
                ),
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
        string memory testLabel = "(ERC721 -> WETH List-On-Chain)";
        test721_1.mint(alice, 1);
        hevm.deal(bob, 100);
        hevm.prank(bob);
        weth.deposit{ value: 100 }();
        try config.getPayload_BuyOfferedERC721WithERC20(
            TestOrderContext(
                true, false, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            TestItem721(address(test721_1), 1),
            TestItem20(address(weth), 100)
        ) returns (TestOrderPayload memory payload) {
            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
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

    // TODO: Think about this. First WETH case.
    // TODO: Also remember to pull out the WETH approvals and NFT approvals to
    //       get a better gas reading.
    // TODO: after establishing marketplace coverage, think about doing
    //       more permutations with flahsloans.
    // TODO: after all that, start working on fulfilling multiple orders in a
    //       single transaction.
    function benchmark_BuyOfferedERC721WithWETH_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) {
        string memory testLabel = "(ERC721 -> WETH List-On-Chain)";
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

            // payload.executeOrder = AdapterHelperLib
            //     .createSeaportWrappedTestCallParameters(
            //     payload.executeOrder,
            //     address(context.fulfiller),
            //     address(seaport),
            //     address(context.flashloanOfferer),
            //     address(context.adapter),
            //     address(context.sidecar),
            //
            //     item
            // );

            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill Through Adapter")),
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
        string memory testLabel = "(ERC721 -> WETH)";
        test721_1.mint(alice, 1);
        hevm.deal(bob, 100);
        hevm.prank(bob);
        weth.deposit{ value: 100 }();

        try config.getPayload_BuyOfferedERC721WithWETH(
            TestOrderContext(
                false, false, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            TestItem721(address(test721_1), 1),
            TestItem20(address(weth), 100)
        ) returns (TestOrderPayload memory payload) {
            assertEq(test721_1.ownerOf(1), alice);
            assertEq(weth.balanceOf(alice), 0);
            assertEq(weth.balanceOf(bob), 100);

            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill, w/ Sig")),
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
        string memory testLabel = "(ERC721 -> WETH)";
        test721_1.mint(alice, 1);
        hevm.deal(bob, 100);
        hevm.prank(bob);
        weth.deposit{ value: 100 }();

        try config.getPayload_BuyOfferedERC721WithWETH(
            TestOrderContext(
                false, true, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            TestItem721(address(test721_1), 1),
            TestItem20(address(weth), 100)
        ) returns (TestOrderPayload memory payload) {
            assertEq(test721_1.ownerOf(1), alice);
            assertEq(weth.balanceOf(alice), 0);
            assertEq(weth.balanceOf(bob), 100);

            _benchmarkCallWithParams(
                config.name(),
                string(
                    abi.encodePacked(
                        testLabel, " Fulfill, w/ Sig Through Adapter"
                    )
                ),
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
        string memory testLabel = "(ERC1155 -> ERC20 List-On-Chain)";
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
                alice,
                payload.submitOrder
            );

            assertEq(test1155_1.balanceOf(alice, 1), 1);
            assertEq(token1.balanceOf(alice), 0);
            assertEq(token1.balanceOf(bob), 100);

            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill")),
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
        string memory testLabel = "(ERC1155 -> ERC20 List-On-Chain)";
        test1155_1.mint(alice, 1, 1);
        token1.mint(bob, 100);
        try config.getPayload_BuyOfferedERC1155WithERC20(
            TestOrderContext(
                true, true, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            TestItem1155(address(test1155_1), 1, 1),
            TestItem20(address(token1), 100)
        ) returns (TestOrderPayload memory payload) {
            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
                alice,
                payload.submitOrder
            );

            assertEq(test1155_1.balanceOf(alice, 1), 1);
            assertEq(token1.balanceOf(alice), 0);
            assertEq(token1.balanceOf(bob), 100);

            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill Through Adapter")),
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
    {
        string memory testLabel = "(ERC1155 -> ERC20)";
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
        string memory testLabel = "(ERC1155 -> ERC20)";
        test1155_1.mint(alice, 1, 1);
        token1.mint(bob, 100);
        try config.getPayload_BuyOfferedERC1155WithERC20(
            TestOrderContext(
                false, true, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            TestItem1155(address(test1155_1), 1, 1),
            TestItem20(address(token1), 100)
        ) returns (TestOrderPayload memory payload) {
            assertEq(test1155_1.balanceOf(alice, 1), 1);
            assertEq(token1.balanceOf(alice), 0);
            assertEq(token1.balanceOf(bob), 100);

            _benchmarkCallWithParams(
                config.name(),
                string(
                    abi.encodePacked(
                        testLabel, " Fulfill w/ Sig Through Adapter"
                    )
                ),
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
    ) internal prepareTest(config) {
        string memory testLabel = "(ERC20 -> ERC721 List-On-Chain)";
        token1.mint(alice, 100);
        test721_1.mint(bob, 1);
        try config.getPayload_BuyOfferedERC20WithERC721(
            TestOrderContext(
                true, false, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            TestItem20(address(token1), 100),
            TestItem721(address(test721_1), 1)
        ) returns (TestOrderPayload memory payload) {
            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
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
        string memory testLabel = "(ERC20 -> ERC721 List-On-Chain)";
        token1.mint(alice, 100);
        test721_1.mint(bob, 1);
        try config.getPayload_BuyOfferedERC20WithERC721(
            TestOrderContext(
                true, true, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            TestItem20(address(token1), 100),
            TestItem721(address(test721_1), 1)
        ) returns (TestOrderPayload memory payload) {
            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
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
                string(abi.encodePacked(testLabel, " Fulfill Through Adapter")),
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
    {
        string memory testLabel = "(ERC20 -> ERC721)";
        token1.mint(alice, 100);
        test721_1.mint(bob, 1);
        try config.getPayload_BuyOfferedERC20WithERC721(
            TestOrderContext(
                false, false, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            TestItem20(address(token1), 100),
            TestItem721(address(test721_1), 1)
        ) returns (TestOrderPayload memory payload) {
            assertEq(test721_1.ownerOf(1), bob);
            assertEq(token1.balanceOf(alice), 100);
            assertEq(token1.balanceOf(bob), 0);

            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill w/ Sig")),
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
        string memory testLabel = "(ERC20 -> ERC721)";
        token1.mint(alice, 100);
        test721_1.mint(bob, 1);
        try config.getPayload_BuyOfferedERC20WithERC721(
            TestOrderContext(
                false, true, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            TestItem20(address(token1), 100),
            TestItem721(address(test721_1), 1)
        ) returns (TestOrderPayload memory payload) {
            assertEq(test721_1.ownerOf(1), bob);
            assertEq(token1.balanceOf(alice), 100);
            assertEq(token1.balanceOf(bob), 0);

            _benchmarkCallWithParams(
                config.name(),
                string(
                    abi.encodePacked(
                        testLabel, " Fulfill w/ Sig Through Adapter"
                    )
                ),
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
    ) internal prepareTest(config) {
        string memory testLabel = "(WETH -> ERC721 List-On-Chain)";
        hevm.deal(alice, 100);
        hevm.prank(alice);
        weth.deposit{ value: 100 }();
        test721_1.mint(bob, 1);
        try config.getPayload_BuyOfferedWETHWithERC721(
            TestOrderContext(
                true, false, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            TestItem20(address(weth), 100),
            TestItem721(address(test721_1), 1)
        ) returns (TestOrderPayload memory payload) {
            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
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
        string memory testLabel = "(WETH -> ERC721 List-On-Chain)";
        hevm.deal(alice, 100);
        hevm.prank(alice);
        weth.deposit{ value: 100 }();
        test721_1.mint(bob, 1);
        try config.getPayload_BuyOfferedWETHWithERC721(
            TestOrderContext(
                true, true, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            TestItem20(address(weth), 100),
            TestItem721(address(test721_1), 1)
        ) returns (TestOrderPayload memory payload) {
            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
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
                string(abi.encodePacked(testLabel, " Fulfill Through Adapter")),
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
        string memory testLabel = "(WETH -> ERC721)";
        hevm.deal(alice, 100);
        hevm.prank(alice);
        weth.deposit{ value: 100 }();
        test721_1.mint(bob, 1);
        try config.getPayload_BuyOfferedWETHWithERC721(
            TestOrderContext(
                false, false, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            TestItem20(address(weth), 100),
            TestItem721(address(test721_1), 1)
        ) returns (TestOrderPayload memory payload) {
            assertEq(test721_1.ownerOf(1), bob);
            assertEq(weth.balanceOf(alice), 100);
            assertEq(weth.balanceOf(bob), 0);

            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill w/ Sig")),
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
        string memory testLabel = "(WETH -> ERC721)";
        hevm.deal(alice, 100);
        hevm.prank(alice);
        weth.deposit{ value: 100 }();
        test721_1.mint(bob, 1);
        try config.getPayload_BuyOfferedWETHWithERC721(
            TestOrderContext(
                false, true, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            TestItem20(address(weth), 100),
            TestItem721(address(test721_1), 1)
        ) returns (TestOrderPayload memory payload) {
            assertEq(test721_1.ownerOf(1), bob);
            assertEq(weth.balanceOf(alice), 100);
            assertEq(weth.balanceOf(bob), 0);

            _benchmarkCallWithParams(
                config.name(),
                string(
                    abi.encodePacked(
                        testLabel, " Fulfill w/ Sig Through Adapter"
                    )
                ),
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
        string memory testLabel = "(ERC20 -> ERC1155 List-On-Chain)";
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
                alice,
                payload.submitOrder
            );

            assertEq(test1155_1.balanceOf(bob, 1), 1);
            assertEq(token1.balanceOf(alice), 100);
            assertEq(token1.balanceOf(bob), 0);

            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill")),
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
        string memory testLabel = "(ERC20 -> ERC1155 List-On-Chain)";
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
            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
                alice,
                payload.submitOrder
            );

            assertEq(test1155_1.balanceOf(bob, 1), 1);
            assertEq(token1.balanceOf(alice), 100);
            assertEq(token1.balanceOf(bob), 0);

            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill Through Adapter")),
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
    {
        string memory testLabel = "(ERC20 -> ERC1155)";
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
        string memory testLabel = "(ERC20 -> ERC1155)";
        TestOrderContext memory context = TestOrderContext(
            false, true, alice, bob, flashloanOfferer, adapter, sidecar
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
                string(
                    abi.encodePacked(
                        testLabel, " Fulfill w/ Sig Through Adapter"
                    )
                ),
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
    ) internal prepareTest(config) {
        string memory testLabel = "(ERC721 -> ERC1155 List-On-Chain)";
        TestOrderContext memory context = TestOrderContext(
            true, false, alice, bob, flashloanOfferer, adapter, sidecar
        );
        test721_1.mint(alice, 1);
        test1155_1.mint(bob, 1, 1);
        try config.getPayload_BuyOfferedERC721WithERC1155(
            context,
            TestItem721(address(test721_1), 1),
            TestItem1155(address(test1155_1), 1, 1)
        ) returns (TestOrderPayload memory payload) {
            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
                alice,
                payload.submitOrder
            );

            assertEq(test721_1.ownerOf(1), alice);
            assertEq(test1155_1.balanceOf(bob, 1), 1);

            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill")),
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
        string memory testLabel = "(ERC721 -> ERC1155 List-On-Chain)";
        TestOrderContext memory context = TestOrderContext(
            true, true, alice, bob, flashloanOfferer, adapter, sidecar
        );
        test721_1.mint(alice, 1);
        test1155_1.mint(bob, 1, 1);
        try config.getPayload_BuyOfferedERC721WithERC1155(
            context,
            TestItem721(address(test721_1), 1),
            TestItem1155(address(test1155_1), 1, 1)
        ) returns (TestOrderPayload memory payload) {
            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
                alice,
                payload.submitOrder
            );

            assertEq(test721_1.ownerOf(1), alice);
            assertEq(test1155_1.balanceOf(bob, 1), 1);

            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill Through Adapter")),
                bob,
                payload.executeOrder
            );

            assertEq(test721_1.ownerOf(1), bob);
            assertEq(test1155_1.balanceOf(alice, 1), 1);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function benchmark_BuyOfferedERC721WithERC1155(BaseMarketConfig config)
        internal
        prepareTest(config)
    {
        string memory testLabel = "(ERC721 -> ERC1155)";
        TestOrderContext memory context = TestOrderContext(
            false, false, alice, bob, flashloanOfferer, adapter, sidecar
        );
        test721_1.mint(alice, 1);
        test1155_1.mint(bob, 1, 1);
        try config.getPayload_BuyOfferedERC721WithERC1155(
            context,
            TestItem721(address(test721_1), 1),
            TestItem1155(address(test1155_1), 1, 1)
        ) returns (TestOrderPayload memory payload) {
            assertEq(test721_1.ownerOf(1), alice);
            assertEq(test1155_1.balanceOf(bob, 1), 1);

            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill w/ Sig")),
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
        string memory testLabel = "(ERC721 -> ERC1155)";
        TestOrderContext memory context = TestOrderContext(
            false, true, alice, bob, flashloanOfferer, adapter, sidecar
        );
        test721_1.mint(alice, 1);
        test1155_1.mint(bob, 1, 1);
        try config.getPayload_BuyOfferedERC721WithERC1155(
            context,
            TestItem721(address(test721_1), 1),
            TestItem1155(address(test1155_1), 1, 1)
        ) returns (TestOrderPayload memory payload) {
            assertEq(test721_1.ownerOf(1), alice);
            assertEq(test1155_1.balanceOf(bob, 1), 1);

            _benchmarkCallWithParams(
                config.name(),
                string(
                    abi.encodePacked(
                        testLabel, " Fulfill w/ Sig Through Adapter"
                    )
                ),
                bob,
                payload.executeOrder
            );

            assertEq(test721_1.ownerOf(1), bob);
            assertEq(test1155_1.balanceOf(alice, 1), 1);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function benchmark_BuyOfferedERC1155WithERC721_ListOnChain(
        BaseMarketConfig config
    ) internal prepareTest(config) {
        string memory testLabel = "(ERC1155 -> ERC721 List-On-Chain)";
        TestOrderContext memory context = TestOrderContext(
            true, false, alice, bob, flashloanOfferer, adapter, sidecar
        );
        test1155_1.mint(alice, 1, 1);
        test721_1.mint(bob, 1);
        try config.getPayload_BuyOfferedERC1155WithERC721(
            context,
            TestItem1155(address(test1155_1), 1, 1),
            TestItem721(address(test721_1), 1)
        ) returns (TestOrderPayload memory payload) {
            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
                alice,
                payload.submitOrder
            );

            assertEq(test721_1.ownerOf(1), bob);
            assertEq(test1155_1.balanceOf(alice, 1), 1);

            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill")),
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
        string memory testLabel = "(ERC1155 -> ERC721 List-On-Chain)";
        TestOrderContext memory context = TestOrderContext(
            true, true, alice, bob, flashloanOfferer, adapter, sidecar
        );
        test1155_1.mint(alice, 1, 1);
        test721_1.mint(bob, 1);
        try config.getPayload_BuyOfferedERC1155WithERC721(
            context,
            TestItem1155(address(test1155_1), 1, 1),
            TestItem721(address(test721_1), 1)
        ) returns (TestOrderPayload memory payload) {
            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
                alice,
                payload.submitOrder
            );

            assertEq(test721_1.ownerOf(1), bob);
            assertEq(test1155_1.balanceOf(alice, 1), 1);

            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill Through Adapter")),
                bob,
                payload.executeOrder
            );

            assertEq(test721_1.ownerOf(1), alice);
            assertEq(test1155_1.balanceOf(bob, 1), 1);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function benchmark_BuyOfferedERC1155WithERC721(BaseMarketConfig config)
        internal
        prepareTest(config)
    {
        string memory testLabel = "(ERC1155 -> ERC721)";
        TestOrderContext memory context = TestOrderContext(
            false, false, alice, bob, flashloanOfferer, adapter, sidecar
        );
        test1155_1.mint(alice, 1, 1);
        test721_1.mint(bob, 1);
        try config.getPayload_BuyOfferedERC1155WithERC721(
            context,
            TestItem1155(address(test1155_1), 1, 1),
            TestItem721(address(test721_1), 1)
        ) returns (TestOrderPayload memory payload) {
            assertEq(test721_1.ownerOf(1), bob);
            assertEq(test1155_1.balanceOf(alice, 1), 1);

            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill w/ Sig")),
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
        string memory testLabel = "(ERC1155 -> ERC721)";
        TestOrderContext memory context = TestOrderContext(
            false, true, alice, bob, flashloanOfferer, adapter, sidecar
        );
        test1155_1.mint(alice, 1, 1);
        test721_1.mint(bob, 1);
        try config.getPayload_BuyOfferedERC1155WithERC721(
            context,
            TestItem1155(address(test1155_1), 1, 1),
            TestItem721(address(test721_1), 1)
        ) returns (TestOrderPayload memory payload) {
            assertEq(test721_1.ownerOf(1), bob);
            assertEq(test1155_1.balanceOf(alice, 1), 1);

            _benchmarkCallWithParams(
                config.name(),
                string(
                    abi.encodePacked(
                        testLabel, " Fulfill w/ Sig Through Adapter"
                    )
                ),
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
            "(ERC721 -> ETH One-Fee-Recipient List-On-Chain)";
        test721_1.mint(alice, 1);
        try config.getPayload_BuyOfferedERC721WithEtherOneFeeRecipient(
            TestOrderContext(
                true, false, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            TestItem721(address(test721_1), 1),
            500, // increased so that the fee recipient recieves 1%
            feeReciever1,
            5
        ) returns (TestOrderPayload memory payload) {
            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
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
            "(ERC721 -> ETH One-Fee-Recipient List-On-Chain)";
        test721_1.mint(alice, 1);

        // LR and X2Y2 require that the msg.sender is also the taker.
        if (
            keccak256(bytes(config.name()))
                == keccak256(bytes(looksRareConfig.name()))
                || keccak256(bytes(config.name()))
                    == keccak256(bytes(x2y2Config.name()))
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
                alice,
                payload.submitOrder
            );

            // Allow the market to escrow after listing
            assert(
                test721_1.ownerOf(1) == alice
                    || test721_1.ownerOf(1) == config.market()
            );
            assertEq(feeReciever1.balance, 0);

            payload.executeOrder = AdapterHelperLib
                .createSeaportWrappedTestCallParameters(
                payload.executeOrder,
                address(context.fulfiller),
                address(seaport),
                address(context.flashloanOfferer),
                address(context.adapter),
                address(context.sidecar),
                standardERC721
            );

            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill Through Adapter")),
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
        string memory testLabel = "(ERC721 -> ETH One-Fee-Recipient)";
        test721_1.mint(alice, 1);
        try config.getPayload_BuyOfferedERC721WithEtherOneFeeRecipient(
            TestOrderContext(
                false, false, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            TestItem721(address(test721_1), 1),
            100,
            feeReciever1,
            5
        ) returns (TestOrderPayload memory payload) {
            assertEq(test721_1.ownerOf(1), alice);
            assertEq(feeReciever1.balance, 0);

            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill w/ Sig")),
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
        string memory testLabel = "(ERC721 -> ETH One-Fee-Recipient)";
        test721_1.mint(alice, 1);

        TestOrderContext memory context = TestOrderContext(
            false, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        // LR and X2Y2 require that the msg.sender is also the taker.
        if (
            keccak256(bytes(config.name()))
                == keccak256(bytes(looksRareConfig.name()))
                || keccak256(bytes(config.name()))
                    == keccak256(bytes(x2y2Config.name()))
        ) {
            _logNotSupported(config.name(), testLabel);
            return;
        }

        try config.getPayload_BuyOfferedERC721WithEtherOneFeeRecipient(
            context, standardERC721, 100, feeReciever1, 5
        ) returns (TestOrderPayload memory payload) {
            assertEq(test721_1.ownerOf(1), alice);
            assertEq(feeReciever1.balance, 0);

            payload.executeOrder = AdapterHelperLib
                .createSeaportWrappedTestCallParameters(
                payload.executeOrder,
                address(context.fulfiller),
                address(seaport),
                address(context.flashloanOfferer),
                address(context.adapter),
                address(context.sidecar),
                standardERC721
            );

            _benchmarkCallWithParams(
                config.name(),
                string(
                    abi.encodePacked(
                        testLabel, " Fulfill w/ Sig Through Adapter"
                    )
                ),
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
            "(ERC721 -> ETH Two-Fee-Recipient List-On-Chain)";
        test721_1.mint(alice, 1);
        try config.getPayload_BuyOfferedERC721WithEtherTwoFeeRecipient(
            TestOrderContext(
                true, false, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            TestItem721(address(test721_1), 1),
            100,
            feeReciever1,
            5,
            feeReciever2,
            5
        ) returns (TestOrderPayload memory payload) {
            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
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
            "(ERC721 -> ETH Two-Fee-Recipient List-On-Chain)";
        test721_1.mint(alice, 1);

        TestOrderContext memory context = TestOrderContext(
            true, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        if (
            keccak256(bytes(config.name()))
                == keccak256(bytes(x2y2Config.name()))
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
                alice,
                payload.submitOrder
            );

            assert(
                test721_1.ownerOf(1) == alice
                    || test721_1.ownerOf(1) == config.market()
            );
            assertEq(feeReciever1.balance, 0);
            assertEq(feeReciever2.balance, 0);

            payload.executeOrder = AdapterHelperLib
                .createSeaportWrappedTestCallParameters(
                payload.executeOrder,
                address(context.fulfiller),
                address(seaport),
                address(context.flashloanOfferer),
                address(context.adapter),
                address(context.sidecar),
                standardERC721
            );

            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill Through Adapter")),
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
        string memory testLabel = "(ERC721 -> ETH Two-Fee-Recipient)";
        test721_1.mint(alice, 1);
        try config.getPayload_BuyOfferedERC721WithEtherTwoFeeRecipient(
            TestOrderContext(
                false, false, alice, bob, flashloanOfferer, adapter, sidecar
            ),
            TestItem721(address(test721_1), 1),
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
        string memory testLabel = "(ERC721 -> ETH Two-Fee-Recipient)";
        test721_1.mint(alice, 1);

        if (
            keccak256(bytes(config.name()))
                == keccak256(bytes(x2y2Config.name()))
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

            payload.executeOrder = AdapterHelperLib
                .createSeaportWrappedTestCallParameters(
                payload.executeOrder,
                address(context.fulfiller),
                address(seaport),
                address(context.flashloanOfferer),
                address(context.adapter),
                address(context.sidecar),
                standardERC721
            );

            _benchmarkCallWithParams(
                config.name(),
                string(
                    abi.encodePacked(
                        testLabel, " Fulfill w/ Sig Through Adapter"
                    )
                ),
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
        string memory testLabel = "(ERC721x10 -> ETH List-On-Chain)";

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
        string memory testLabel = "(ERC721x10 -> ETH List-On-Chain Adapter)";

        TestOrderContext memory context = TestOrderContext(
            true, true, alice, bob, flashloanOfferer, adapter, sidecar
        );

        TestItem721[] memory items = new TestItem721[](10);
        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
            items[i] = TestItem721(address(test721_1), i + 1);
        }

        if (
            keccak256(bytes(config.name()))
                == keccak256(bytes(x2y2Config.name()))
        ) {
            _logNotSupported(config.name(), testLabel);
            return;
        }

        try config.getPayload_BuyOfferedManyERC721WithEther(context, items, 100)
        returns (TestOrderPayload memory payload) {
            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
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

            payload.executeOrder = AdapterHelperLib
                .createSeaportWrappedTestCallParameters(
                payload.executeOrder,
                address(context.fulfiller),
                address(seaport),
                address(context.flashloanOfferer),
                address(context.adapter),
                address(context.sidecar),
                items
            );

            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill Through Adapter")),
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
        string memory testLabel = "(ERC721x10 -> ETH)";

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
        string memory testLabel = "(ERC721x10 -> ETH Adapter)";

        if (
            keccak256(bytes(config.name()))
                == keccak256(bytes(x2y2Config.name()))
        ) {
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

            payload.executeOrder = AdapterHelperLib
                .createSeaportWrappedTestCallParameters(
                payload.executeOrder,
                address(context.fulfiller),
                address(seaport),
                address(context.flashloanOfferer),
                address(context.adapter),
                address(context.sidecar),
                items
            );

            _benchmarkCallWithParams(
                config.name(),
                string(
                    abi.encodePacked(
                        testLabel, " Fulfill /w Sig Through Adapter"
                    )
                ),
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
        string memory testLabel = "(ERC721x10 -> ETH Distinct Orders)";

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

    // TODO: come back and clean this up. It's extra hacky.
    function benchmark_BuyTenOfferedERC721WithEtherDistinctOrders_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) {
        string memory testLabel = "(ERC721x10 -> ETH Distinct Orders Adapter)";

        if (
            keccak256(bytes(config.name()))
                == keccak256(bytes(x2y2Config.name()))
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

            payload.executeOrder = AdapterHelperLib
                .createSeaportWrappedTestCallParameters(
                payload.executeOrder,
                address(contexts[0].fulfiller),
                address(seaport),
                address(contexts[0].flashloanOfferer),
                address(contexts[0].adapter),
                address(contexts[0].sidecar),
                items
            );

            _benchmarkCallWithParams(
                config.name(),
                string(
                    abi.encodePacked(
                        testLabel, " Fulfill /w Sigs Through Adapter"
                    )
                ),
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
            "(ERC721x10 -> ETH Distinct Orders List-On-Chain)";

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
                alice,
                payload.submitOrder
            );

            // @dev checking ownership here (when nfts are escrowed in different contracts) is messy so we skip it for now

            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill")),
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
            "(ERC721x10 -> ETH Distinct Orders List-On-Chain Adapter)";

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
                items
            );

            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill Through Adapter")),
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
        string memory testLabel = "(ERC721x10 -> ERC20 Distinct Orders)";

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
        string memory testLabel = "(ERC721x10 -> ERC20 Distinct Orders Adapter)";

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

        try config.getPayload_BuyOfferedManyERC721WithErc20DistinctOrders(
            contexts, address(token1), nfts, erc20Amounts
        ) returns (TestOrderPayload memory payload) {
            for (uint256 i = 1; i <= 10; i++) {
                assertEq(test721_1.ownerOf(i), alice);
            }

            _benchmarkCallWithParams(
                config.name(),
                string(
                    abi.encodePacked(
                        testLabel, " Fulfill /w Sigs Through Adapter"
                    )
                ),
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

    function benchmark_BuyTenOfferedERC721WithErc20DistinctOrders_ListOnChain(
        BaseMarketConfig config
    ) internal prepareTest(config) {
        string memory testLabel =
            "(ERC721x10 -> ERC20 Distinct Orders List-On-Chain)";

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
                alice,
                payload.submitOrder
            );

            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill")),
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
            "(ERC721x10 -> ERC20 Distinct Orders List-On-Chain Adapter)";

        token1.mint(bob, 1045);
        TestOrderContext[] memory contexts = new TestOrderContext[](10);
        TestItem721[] memory nfts = new TestItem721[](10);
        uint256[] memory erc20Amounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
            nfts[i] = TestItem721(address(test721_1), i + 1);
            contexts[i] = TestOrderContext(
                true, true, alice, bob, flashloanOfferer, adapter, sidecar
            );
            erc20Amounts[i] = 100 + i;
        }

        try config.getPayload_BuyOfferedManyERC721WithErc20DistinctOrders(
            contexts, address(token1), nfts, erc20Amounts
        ) returns (TestOrderPayload memory payload) {
            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " List")),
                alice,
                payload.submitOrder
            );

            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill Through Adapter")),
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

    function benchmark_BuyTenOfferedERC721WithWETHDistinctOrders(
        BaseMarketConfig config
    ) internal prepareTest(config) {
        string memory testLabel = "(ERC721x10 -> WETH Distinct Orders)";

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
        string memory testLabel = "(ERC721x10 -> WETH Distinct Orders Adapter)";

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

            _benchmarkCallWithParams(
                config.name(),
                string(
                    abi.encodePacked(
                        testLabel, " Fulfill /w Sigs Through Adapter"
                    )
                ),
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
            "(ERC721x10 -> WETH Distinct Orders List-On-Chain)";

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
                alice,
                payload.submitOrder
            );

            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill")),
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
            "(ERC721x10 -> WETH Distinct Orders List-On-Chain Adapter)";

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
                alice,
                payload.submitOrder
            );

            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill Through Adapter")),
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
        string memory testLabel = "(ERC721 A -> B -> C -> A)";

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

        nfts[0] = TestItem721(address(test721_1), 1);
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
        string memory testLabel = "(ERC721 A -> B -> C -> A Adapter)";

        test721_1.mint(alice, 1);
        test721_1.mint(cal, 2);
        test721_1.mint(bob, 3);

        TestOrderContext[] memory contexts = new TestOrderContext[](3);
        TestItem721[] memory nfts = new TestItem721[](3);

        contexts[0] = TestOrderContext(
            false, true, alice, address(0), flashloanOfferer, adapter, sidecar
        );
        contexts[1] = TestOrderContext(
            false, true, cal, address(0), flashloanOfferer, adapter, sidecar
        );
        contexts[2] = TestOrderContext(
            false, true, bob, address(0), flashloanOfferer, adapter, sidecar
        );

        nfts[0] = TestItem721(address(test721_1), 1);
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
                string(abi.encodePacked(testLabel, " Fulfill Through Adapter")),
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
        emit log(
            string(
                abi.encodePacked("[", name, "] ", label, " -- NOT SUPPORTED")
            )
        );
    }

    function _benchmarkCallWithParams(
        string memory name,
        string memory label,
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
        emit log_named_uint(
            _formatLog(name, string(abi.encodePacked(label, " (direct)"))),
            gasDelta
        );
        emit log_named_uint(
            _formatLog(name, label), gasDelta + _additionalGasFee(params.data)
        );
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
        return sum - 2600; // Remove call opcode cost
    }
}
