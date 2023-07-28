// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import { StdCheats } from "forge-std/StdCheats.sol";

import { Vm } from "forge-std/Vm.sol";

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

import { BlurV2Config } from "../src/marketplaces/blur-2.0/BlurV2Config.sol";

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
    Call,
    Item20,
    Item721,
    Item1155,
    OrderContext
} from "../src/lib/AdapterHelperLib.sol";

import { BaseMarketplaceTest } from "./utils/BaseMarketplaceTest.sol";

import { ConsiderationTypeHashes } from
    "../src/marketplaces/seaport-1.5/lib/ConsiderationTypeHashes.sol";

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

    function testBlur() external virtual {
        benchmarkMarket(blurConfig);
    }

    function testBlurV2() external virtual {
        benchmarkMarket(blurV2Config);
    }

    function testFoundation() external virtual {
        benchmarkMarket(foundationConfig);
    }

    function testLooksRare() external virtual {
        benchmarkMarket(looksRareConfig);
    }

    function testLooksRareV2() external virtual {
        benchmarkMarket(looksRareV2Config);
    }

    // Seaport doesn't get tested directly, since there's no need to route
    // through the adapter for native Seaport orders. Also it's impossible bc
    // of the prohibition on reentrant calls.
    // function testSeaportOnePointFour() external {
    //     benchmarkMarket(seaportOnePointFiveConfig);
    // }

    function testSudoswap() external virtual {
        benchmarkMarket(sudoswapConfig);
    }

    function testX2Y2() external virtual {
        benchmarkMarket(x2y2Config);
    }

    function testZeroEx() external virtual {
        benchmarkMarket(zeroExConfig);
    }

    function benchmarkMarket(BaseMarketConfig config) public {
        // This is kind of a weird spot for this setup, but the benchmarking
        // repo that this is cribbed from relies on recording logs to wipe them
        // out between function calls. So it's important to be careful where
        // you record logs, because it seems that they collide.
        _doSetup();
        _setAdapterSpecificApprovals();

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
        if (_isSudo(config)) {
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
        if (_isSudo(config)) {
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

        buyOfferedERC721WithBETH(config);
        buyOfferedERC721WithBETH_Adapter(config);

        buyOfferedERC721WithWETH_ListOnChain(config);
        buyOfferedERC721WithWETH_ListOnChain_Adapter(config);

        buyOfferedWETHWithERC721_ListOnChain(config);
        buyOfferedWETHWithERC721_ListOnChain_Adapter(config);

        buyOfferedWETHWithERC721(config);
        buyOfferedWETHWithERC721_Adapter(config);

        buyOfferedBETHWithERC721(config);
        buyOfferedBETHWithERC721_Adapter(config);

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
            OrderContext(true, false, stdCastOfCharacters), standardERC721, 100
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

        OrderContext memory context =
            OrderContext(true, true, stdCastOfCharacters);

        bool transfersToSpecifiedTaker = _isSudo(config);

        // This causes the adapter to be set as the token recipient.
        if (transfersToSpecifiedTaker) {
            context.castOfCharacters.fulfiller = adapter;
        }

        try config.getPayload_BuyOfferedERC721WithEther(
            context, standardERC721, 100
        ) returns (TestOrderPayload memory payload) {
            context.castOfCharacters.fulfiller = bob;

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
            OrderContext(false, false, stdCastOfCharacters), standardERC721, 100
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
        ) returns (TestOrderPayload memory payload) {
            context.castOfCharacters.fulfiller = bob;

            assertEq(test721_1.ownerOf(1), alice);

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
            OrderContext(true, false, stdCastOfCharacters), standardERC1155, 100
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

        OrderContext memory context =
            OrderContext(true, true, stdCastOfCharacters);

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
            OrderContext(false, false, stdCastOfCharacters),
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
        ) returns (TestOrderPayload memory payload) {
            context.castOfCharacters.fulfiller = bob;
            assertEq(test1155_1.balanceOf(alice, 1), 1);

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
            OrderContext(true, false, stdCastOfCharacters),
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

        test721_1.mint(alice, 1);
        test20.mint(bob, 100);

        try config.getPayload_BuyOfferedERC721WithERC20(
            context, standardERC721, standardERC20
        ) returns (TestOrderPayload memory payload) {
            context.castOfCharacters.fulfiller = bob;
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
            OrderContext(false, false, stdCastOfCharacters),
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

        OrderContext memory context =
            OrderContext(false, true, stdCastOfCharacters);

        bool requiresTakerIsSender =
            _isLooksRare(config) || _isLooksRareV2(config) || _isX2y2(config);

        if (requiresTakerIsSender) {
            context.castOfCharacters.fulfiller = sidecar;
        }

        test721_1.mint(alice, 1);
        test20.mint(bob, 100);
        try config.getPayload_BuyOfferedERC721WithERC20(
            context, standardERC721, standardERC20
        ) returns (TestOrderPayload memory payload) {
            // Put the context back.
            context.castOfCharacters.fulfiller = bob;

            assertEq(test721_1.ownerOf(1), alice);
            assertEq(test20.balanceOf(alice), 0);
            assertEq(test20.balanceOf(bob), 100);

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
            OrderContext(true, false, stdCastOfCharacters),
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

        OrderContext memory context =
            OrderContext(false, true, stdCastOfCharacters);

        bool requiresTakerIsSender = _isBlur(config) || _isLooksRare(config)
            || _isLooksRareV2(config) || _isX2y2(config);

        if (requiresTakerIsSender) {
            context.castOfCharacters.fulfiller = sidecar;
        }

        try config.getPayload_BuyOfferedERC721WithWETH(
            context, standardERC721, standardWeth
        ) returns (TestOrderPayload memory payload) {
            // Put the context back.
            context.castOfCharacters.fulfiller = bob;

            assertEq(test721_1.ownerOf(1), alice);
            assertEq(weth.balanceOf(alice), 0);
            assertEq(weth.balanceOf(bob), 100);

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

    function buyOfferedERC721WithBETH(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(buyOfferedERC721WithBETH)";
        test721_1.mint(alice, 1);
        hevm.deal(alice, 0);
        hevm.deal(bob, 100);
        hevm.prank(bob);
        beth.deposit{ value: 100 }();

        OrderContext memory context =
            OrderContext(false, false, stdCastOfCharacters);

        try config.getPayload_BuyOfferedERC721WithBETH(
            context, Item721(address(test721_1), 1), Item20(address(beth), 100)
        ) returns (TestOrderPayload memory payload) {
            assertEq(test721_1.ownerOf(1), alice);
            assertEq(beth.balanceOf(alice), 0);
            assertEq(alice.balance, 0);
            assertEq(beth.balanceOf(bob), 100);

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill, w/ Sig")),
                true,
                false,
                bob,
                payload.executeOrder
            );

            assertEq(test721_1.ownerOf(1), bob);
            assertEq(alice.balance, 100, "Alice did not get paid native tokens");
            assertEq(beth.balanceOf(alice), 0, "Alice did not get paid BETH");
            assertEq(beth.balanceOf(bob), 0);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyOfferedERC721WithBETH_Adapter(BaseMarketConfig config)
        internal
        prepareTest(config)
        returns (uint256 gasUsed)
    {
        string memory testLabel = "(buyOfferedERC721WithBETH_Adapter)";
        test721_1.mint(alice, 1);
        hevm.deal(alice, 0);
        hevm.deal(bob, 100);
        // Bob doesn't deposit BETH for this, he sends native tokens, gets a
        // flashloan, which goes from adapter to sidecar to BETH's deposit
        // function, and then the sidecar uses the BETH to fulfill the listing.
        // hevm.prank(bob);
        // beth.deposit{ value: 100 }();

        OrderContext memory context =
            OrderContext(false, true, stdCastOfCharacters);

        bool requiresTakerIsSender = _isBlur(config) || _isBlurV2(config);

        if (requiresTakerIsSender) {
            context.castOfCharacters.fulfiller = sidecar;
        }

        try config.getPayload_BuyOfferedERC721WithBETH(
            context, Item721(address(test721_1), 1), Item20(address(beth), 100)
        ) returns (TestOrderPayload memory payload) {
            context.castOfCharacters.fulfiller = bob;
            assertEq(test721_1.ownerOf(1), alice);
            assertEq(beth.balanceOf(alice), 0);
            assertEq(alice.balance, 0);
            assertEq(beth.balanceOf(bob), 0);
            assertEq(bob.balance, 100);

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

            gasUsed = _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill, w/ Sig*")),
                true,
                true,
                bob,
                payload.executeOrder
            );

            assertEq(test721_1.ownerOf(1), bob);
            assertEq(alice.balance, 100);
            assertEq(beth.balanceOf(bob), 0);
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
        ) returns (TestOrderPayload memory payload) {
            context.castOfCharacters.fulfiller = bob;

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
            OrderContext(false, false, stdCastOfCharacters),
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
            OrderContext(true, false, stdCastOfCharacters),
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

        OrderContext memory context =
            OrderContext(true, true, stdCastOfCharacters);

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
            OrderContext(false, false, stdCastOfCharacters),
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

        OrderContext memory context =
            OrderContext(false, true, stdCastOfCharacters);

        bool requiresTakerIsSender =
            _isLooksRare(config) || _isLooksRareV2(config);

        if (requiresTakerIsSender) {
            context.castOfCharacters.fulfiller = sidecar;
        }

        test1155_1.mint(alice, 1, 1);
        test20.mint(bob, 100);
        try config.getPayload_BuyOfferedERC1155WithERC20(
            context, standardERC1155, standardERC20
        ) returns (TestOrderPayload memory payload) {
            // Put the context back.
            context.castOfCharacters.fulfiller = bob;

            assertEq(test1155_1.balanceOf(alice, 1), 1);
            assertEq(test20.balanceOf(alice), 0);
            assertEq(test20.balanceOf(bob), 100);

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
            OrderContext(true, false, stdCastOfCharacters),
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

        test20.mint(alice, 100);
        test721_1.mint(bob, 1);
        try config.getPayload_BuyOfferedERC20WithERC721(
            context, standardERC20, standardERC721
        ) returns (TestOrderPayload memory payload) {
            context.castOfCharacters.fulfiller = bob;
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
            OrderContext(false, false, stdCastOfCharacters),
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

        OrderContext memory context =
            OrderContext(false, true, stdCastOfCharacters);

        bool requiresTakerIsSender =
            _isLooksRare(config) || _isLooksRareV2(config) || _isX2y2(config);

        if (requiresTakerIsSender) {
            context.castOfCharacters.fulfiller = sidecar;
        }

        test20.mint(alice, 100);
        test721_1.mint(bob, 1);
        try config.getPayload_BuyOfferedERC20WithERC721(
            context, standardERC20, standardERC721
        ) returns (TestOrderPayload memory payload) {
            // Put the context back.
            context.castOfCharacters.fulfiller = bob;

            assertEq(test721_1.ownerOf(1), bob);
            assertEq(test20.balanceOf(alice), 100);
            assertEq(test20.balanceOf(bob), 0);

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
            OrderContext(true, false, stdCastOfCharacters),
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

        OrderContext memory context =
            OrderContext(true, true, stdCastOfCharacters);

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

            // Look into why test20 requires an explicit approval lol.
            vm.prank(sidecar);
            weth.approve(sidecar, 100);

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
            OrderContext(false, false, stdCastOfCharacters),
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

        OrderContext memory context =
            OrderContext(false, true, stdCastOfCharacters);

        bool requiresTakerIsSender = _isBlur(config) || _isLooksRare(config)
            || _isLooksRareV2(config) || _isX2y2(config);

        if (requiresTakerIsSender) {
            context.castOfCharacters.fulfiller = sidecar;
        }

        hevm.deal(alice, 100);
        hevm.prank(alice);
        weth.deposit{ value: 100 }();
        test721_1.mint(bob, 1);
        try config.getPayload_BuyOfferedWETHWithERC721(
            context, standardWeth, standardERC721
        ) returns (TestOrderPayload memory payload) {
            context.castOfCharacters.fulfiller = bob;

            assertEq(test721_1.ownerOf(1), bob);
            assertEq(weth.balanceOf(alice), 100);
            assertEq(weth.balanceOf(bob), 0);

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

    function buyOfferedBETHWithERC721(BaseMarketConfig config)
        internal
        prepareTest(config)
    {
        string memory testLabel = "(buyOfferedBETHWithERC721)";
        hevm.deal(alice, 100);
        hevm.prank(alice);
        beth.deposit{ value: 100 }();
        test721_1.mint(bob, 1);
        try config.getPayload_BuyOfferedBETHWithERC721(
            OrderContext(false, false, stdCastOfCharacters),
            Item20(address(beth), 100),
            Item721(address(test721_1), 1)
        ) returns (TestOrderPayload memory payload) {
            assertEq(test721_1.ownerOf(1), bob);
            assertEq(beth.balanceOf(alice), 100);
            assertEq(beth.balanceOf(bob), 0);

            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill w/ Sig")),
                true,
                false,
                bob,
                payload.executeOrder
            );

            assertEq(test721_1.ownerOf(1), alice);
            assertEq(beth.balanceOf(alice), 0);
            assertEq(beth.balanceOf(bob), 100);
        } catch {
            _logNotSupported(config.name(), testLabel);
        }
    }

    function buyOfferedBETHWithERC721_Adapter(BaseMarketConfig config)
        internal
        prepareTest(config)
    {
        string memory testLabel = "(buyOfferedBETHWithERC721_Adapter)";
        hevm.deal(alice, 100);
        hevm.prank(alice);
        beth.deposit{ value: 100 }();
        test721_1.mint(bob, 1);
        hevm.deal(bob, 0);

        OrderContext memory context =
            OrderContext(false, true, stdCastOfCharacters);

        bool requiresTakerIsSender = _isBlurV2(config);

        if (requiresTakerIsSender) {
            context.castOfCharacters.fulfiller = sidecar;
        }

        try config.getPayload_BuyOfferedBETHWithERC721(
            context, Item20(address(beth), 100), Item721(address(test721_1), 1)
        ) returns (TestOrderPayload memory payload) {
            assertEq(test721_1.ownerOf(1), bob);
            assertEq(beth.balanceOf(alice), 100);
            assertEq(beth.balanceOf(bob), 0);
            assertEq(bob.balance, 0);

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

            _benchmarkCallWithParams(
                config.name(),
                string(abi.encodePacked(testLabel, " Fulfill w/ Sig*")),
                true,
                true,
                bob,
                payload.executeOrder
            );

            assertEq(test721_1.ownerOf(1), alice);
            assertEq(beth.balanceOf(alice), 0);
            assertEq(bob.balance, 100);
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
        OrderContext memory context =
            OrderContext(true, false, stdCastOfCharacters);
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

        OrderContext memory context =
            OrderContext(true, true, stdCastOfCharacters);
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
        OrderContext memory context =
            OrderContext(false, false, stdCastOfCharacters);
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

        OrderContext memory context =
            OrderContext(false, true, stdCastOfCharacters);

        bool requiresTakerIsSender =
            _isLooksRare(config) || _isLooksRareV2(config);

        // Cheat the context for LR.
        if (requiresTakerIsSender) {
            context.castOfCharacters.fulfiller = sidecar;
        }

        test20.mint(alice, 100);
        test1155_1.mint(bob, 1, 1);
        try config.getPayload_BuyOfferedERC20WithERC1155(
            context, standardERC20, standardERC1155
        ) returns (TestOrderPayload memory payload) {
            // Put the context back.
            context.castOfCharacters.fulfiller = bob;

            assertEq(test1155_1.balanceOf(bob, 1), 1);
            assertEq(test20.balanceOf(alice), 100);
            assertEq(test20.balanceOf(bob), 0);

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
        OrderContext memory context =
            OrderContext(true, false, stdCastOfCharacters);
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

        // OrderContext memory context = OrderContext(
        //     true, true, stdCastOfCharacters
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
        OrderContext memory context =
            OrderContext(false, false, stdCastOfCharacters);
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

        // OrderContext memory context = OrderContext(
        //     false, true, stdCastOfCharacters
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
        OrderContext memory context =
            OrderContext(true, false, stdCastOfCharacters);
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

        // OrderContext memory context = OrderContext(
        //     true, true, stdCastOfCharacters
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
        OrderContext memory context =
            OrderContext(false, false, stdCastOfCharacters);
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

        // OrderContext memory context = OrderContext(
        //     false, true, stdCastOfCharacters
        // );
        // test1155_1.mint(alice, 1, 1);
        // test721_1.mint(bob, 1);

        // try config.getPayload_BuyOfferedERC1155WithERC721(
        //     context, standardERC1155, standardERC721
        // ) returns (TestOrderPayload memory payload) {
        //     assertEq(test721_1.ownerOf(1), bob);
        //     assertEq(test1155_1.balanceOf(alice, 1), 1);

        //     payload.executeOrder = AdapterHelperLib
        //         .createSeaportWrappedCallParameters(
        //         payload.executeOrder,
        //         address(context.castOfCharacters.fulfiller),
        //         seaportAddress,
        //         address(context.flashloanOfferer),
        //         address(context.castOfCharacters.adapter),
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
            OrderContext(true, false, stdCastOfCharacters),
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

        OrderContext memory context =
            OrderContext(true, true, stdCastOfCharacters);

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
            OrderContext(false, false, stdCastOfCharacters),
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

        OrderContext memory context =
            OrderContext(false, true, stdCastOfCharacters);

        bool requiresTakerIsSender = _isX2y2(config);

        if (requiresTakerIsSender) {
            context.castOfCharacters.fulfiller = sidecar;
        }

        try config.getPayload_BuyOfferedERC721WithEtherOneFeeRecipient(
            context, standardERC721, 100, feeReciever1, 5
        ) returns (TestOrderPayload memory payload) {
            context.castOfCharacters.fulfiller = bob;
            assertEq(test721_1.ownerOf(1), alice);
            assertEq(feeReciever1.balance, 0);

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
            OrderContext(true, false, stdCastOfCharacters),
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

        OrderContext memory context =
            OrderContext(true, true, stdCastOfCharacters);

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
            OrderContext(false, false, stdCastOfCharacters),
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

        OrderContext memory context =
            OrderContext(false, true, stdCastOfCharacters);

        bool requiresTakerIsSender = _isX2y2(config);

        if (requiresTakerIsSender) {
            context.castOfCharacters.fulfiller = sidecar;
        }

        try config.getPayload_BuyOfferedERC721WithEtherTwoFeeRecipient(
            context, standardERC721, 100, feeReciever1, 5, feeReciever2, 5
        ) returns (TestOrderPayload memory payload) {
            context.castOfCharacters.fulfiller = bob;
            assertEq(test721_1.ownerOf(1), alice);
            assertEq(feeReciever1.balance, 0);
            assertEq(feeReciever2.balance, 0);

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

        Item721[] memory nfts = new Item721[](10);
        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
            nfts[i] = Item721(_test721Address, i + 1);
        }

        try config.getPayload_BuyOfferedManyERC721WithEther(
            OrderContext(true, false, stdCastOfCharacters), nfts, 100
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

        OrderContext memory context =
            OrderContext(true, true, stdCastOfCharacters);

        bool transfersToSpecifiedTaker = _isSudo(config);

        if (transfersToSpecifiedTaker) {
            context.castOfCharacters.fulfiller = adapter;
        }

        Item721[] memory nfts = new Item721[](10);
        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
            nfts[i] = Item721(_test721Address, i + 1);
        }

        try config.getPayload_BuyOfferedManyERC721WithEther(context, nfts, 100)
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

        Item721[] memory nfts = new Item721[](10);
        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
            nfts[i] = Item721(_test721Address, i + 1);
        }

        try config.getPayload_BuyOfferedManyERC721WithEther(
            OrderContext(false, false, stdCastOfCharacters), nfts, 100
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

        OrderContext memory context =
            OrderContext(false, true, stdCastOfCharacters);

        bool requiresTakerIsSender =
            _isBlurV2(config) || _isX2y2(config) || _isLooksRareV2(config);

        if (requiresTakerIsSender) {
            context.castOfCharacters.fulfiller = sidecar;
        }

        Item721[] memory nfts = new Item721[](10);
        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
            nfts[i] = Item721(_test721Address, i + 1);
        }

        try config.getPayload_BuyOfferedManyERC721WithEther(context, nfts, 100)
        returns (TestOrderPayload memory payload) {
            context.castOfCharacters.fulfiller = bob;

            for (uint256 i = 0; i < 10; i++) {
                assertEq(test721_1.ownerOf(i + 1), alice);
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

        OrderContext[] memory contexts = new OrderContext[](10);
        Item721[] memory nfts = new Item721[](10);
        uint256[] memory ethAmounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
            nfts[i] = Item721(_test721Address, i + 1);
            contexts[i] = OrderContext(false, false, stdCastOfCharacters);
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

        bool requiresTakerIsSender = _isBlur(config) || _isBlurV2(config)
            || _isLooksRareV2(config) || _isX2y2(config);

        OrderContext[] memory contexts = new OrderContext[](10);
        Item721[] memory nfts = new Item721[](10);
        uint256[] memory ethAmounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
            nfts[i] = Item721(_test721Address, i + 1);
            contexts[i] = OrderContext(false, true, stdCastOfCharacters);

            contexts[i].castOfCharacters.fulfiller =
                requiresTakerIsSender ? sidecar : bob;
            ethAmounts[i] = 100 + i;
        }

        try config.getPayload_BuyOfferedManyERC721WithEtherDistinctOrders(
            contexts, nfts, ethAmounts
        ) returns (TestOrderPayload memory payload) {
            for (uint256 i = 0; i < 10; i++) {
                contexts[i].castOfCharacters.fulfiller = bob;
            }

            for (uint256 i = 1; i <= 10; i++) {
                assertEq(test721_1.ownerOf(i), alice);
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

        OrderContext[] memory contexts = new OrderContext[](10);
        Item721[] memory nfts = new Item721[](10);
        uint256[] memory ethAmounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
            nfts[i] = Item721(_test721Address, i + 1);
            contexts[i] = OrderContext(true, false, stdCastOfCharacters);
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

            // @dev checking ownership here (when nfts are escrowed in different
            // contracts) is messy so we skip it for now

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

        bool transfersToSpecifiedTaker = _isSudo(config);

        OrderContext[] memory contexts = new OrderContext[](10);
        Item721[] memory nfts = new Item721[](10);
        uint256[] memory ethAmounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
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
        ) returns (TestOrderPayload memory payload) {
            for (uint256 i = 0; i < 10; i++) {
                contexts[i].castOfCharacters.fulfiller = bob;
            }

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
        OrderContext[] memory contexts = new OrderContext[](10);
        Item721[] memory nfts = new Item721[](10);
        uint256[] memory erc20Amounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
            nfts[i] = Item721(_test721Address, i + 1);
            contexts[i] = OrderContext(false, false, stdCastOfCharacters);
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
        OrderContext[] memory contexts = new OrderContext[](10);
        Item721[] memory nfts = new Item721[](10);
        uint256[] memory erc20Amounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
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
        ) returns (TestOrderPayload memory payload) {
            for (uint256 i = 0; i < contexts.length; i++) {
                contexts[i].castOfCharacters.fulfiller = bob;
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
        OrderContext[] memory contexts = new OrderContext[](10);
        Item721[] memory nfts = new Item721[](10);
        uint256[] memory erc20Amounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
            nfts[i] = Item721(_test721Address, i + 1);
            contexts[i] = OrderContext(true, false, stdCastOfCharacters);
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
            test721_1.mint(alice, i + 1);
            nfts[i] = Item721(_test721Address, i + 1);
            contexts[i] = OrderContext(true, true, stdCastOfCharacters);
            erc20Amounts[i] = 100 + i;
        }

        try config.getPayload_BuyOfferedManyERC721WithErc20DistinctOrders(
            contexts, _test20Address, nfts, erc20Amounts
        ) returns (TestOrderPayload memory payload) {
            for (uint256 i = 0; i < contexts.length; i++) {
                contexts[i].castOfCharacters.fulfiller = bob;
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
        OrderContext[] memory contexts = new OrderContext[](10);
        Item721[] memory nfts = new Item721[](10);
        uint256[] memory wethAmounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
            nfts[i] = Item721(_test721Address, i + 1);
            contexts[i] = OrderContext(false, false, stdCastOfCharacters);
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

    function buyTenOfferedERC721WithWETHDistinctOrders_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(buyTenOfferedERC721WithWETHDistinctOrders_Adapter)";

        hevm.deal(bob, 1045);
        hevm.prank(bob);
        weth.deposit{ value: 1045 }();
        OrderContext[] memory contexts = new OrderContext[](10);
        Item721[] memory nfts = new Item721[](10);
        uint256[] memory wethAmounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
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
        ) returns (TestOrderPayload memory payload) {
            for (uint256 i = 0; i < contexts.length; i++) {
                contexts[i].castOfCharacters.fulfiller = bob;
            }

            for (uint256 i = 1; i <= 10; i++) {
                assertEq(test721_1.ownerOf(i), alice);
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
        OrderContext[] memory contexts = new OrderContext[](10);
        Item721[] memory nfts = new Item721[](10);
        uint256[] memory wethAmounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
            nfts[i] = Item721(_test721Address, i + 1);
            contexts[i] = OrderContext(true, false, stdCastOfCharacters);
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

    // This is a no-op for now.
    function buyTenOfferedERC721WithWETHDistinctOrders_ListOnChain_Adapter(
        BaseMarketConfig config
    ) internal prepareTest(config) returns (uint256 gasUsed) {
        string memory testLabel =
            "(buyTenOfferedERC721WithWETHDistinctOrders_ListOnChain_Adapter)";

        hevm.deal(bob, 1045);
        hevm.prank(bob);
        weth.deposit{ value: 1045 }();
        OrderContext[] memory contexts = new OrderContext[](10);
        Item721[] memory nfts = new Item721[](10);
        uint256[] memory wethAmounts = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            test721_1.mint(alice, i + 1);
            nfts[i] = Item721(_test721Address, i + 1);
            contexts[i] = OrderContext(true, true, stdCastOfCharacters);
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
                .createSeaportWrappedCallParameters(
                stdCastOfCharacters,
                new OfferItem[](0), // TODO: add boilerplate for conditionality
                considerationArray,
                new ItemTransfer[](0)
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

        // OrderContext[] memory contexts = new OrderContext[](3);
        // Item721[] memory nfts = new Item721[](3);

        // contexts[0] = OrderContext(
        //     false, true, alice, address(0), flashloanOfferer, adapter,
        // sidecar
        // );
        // contexts[1] = OrderContext(
        //     false, true, cal, address(0), flashloanOfferer, adapter, sidecar
        // );
        // contexts[2] = OrderContext(
        //     false, true, bob, address(0), flashloanOfferer, adapter, sidecar
        // );

        // nfts[0] = standardERC721;
        // nfts[1] = standardERC721Two;
        // nfts[2] = Item721(_test721Address, 3);

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

        vm.startPrank(sidecar);
        test20.approve(sidecar, type(uint256).max);
        weth.approve(sidecar, type(uint256).max);
        vm.stopPrank();
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

        standardWeth = Item20(wethAddress, 100);
        standardERC20 = Item20(_test20Address, 100);
        standardERC721 = Item721(_test721Address, 1);
        standardERC721Two = Item721(_test721Address, 2);
        standardERC1155 = Item1155(_test1155Address, 1, 1);

        standardWethTransfer = ItemTransfer({
            from: sidecar,
            to: adapter,
            token: standardWeth.token,
            identifier: 0,
            amount: standardWeth.amount,
            itemType: ItemType.ERC20
        });
        standard20Transfer = ItemTransfer({
            from: sidecar,
            to: adapter,
            token: standardERC20.token,
            identifier: 0,
            amount: standardERC20.amount,
            itemType: ItemType.ERC20
        });
        standard721Transfer = ItemTransfer({
            from: sidecar,
            to: adapter,
            token: standardERC721.token,
            identifier: standardERC721.identifier,
            amount: 1,
            itemType: ItemType.ERC721
        });
        standard1155Transfer = ItemTransfer({
            from: sidecar,
            to: adapter,
            token: standardERC1155.token,
            identifier: standardERC1155.identifier,
            amount: 1,
            itemType: ItemType.ERC1155
        });

        vm.deal(flashloanOfferer, type(uint128).max);

        stdCastOfCharacters = CastOfCharacters({
            offerer: alice,
            fulfiller: bob,
            seaport: seaportAddress,
            flashloanOfferer: flashloanOfferer,
            adapter: adapter,
            sidecar: sidecar
        });

        OfferItem memory standardNativeOffer = OfferItemLib.empty().withItemType(
            ItemType.NATIVE
        ).withToken(address(0)).withIdentifierOrCriteria(0).withStartAmount(100)
            .withEndAmount(100).saveDefault("standardNativeOfferItem");
        ConsiderationItem memory standardNativeConsideration =
        ConsiderationItemLib.empty().withItemType(ItemType.NATIVE).withToken(
            address(0)
        ).withIdentifierOrCriteria(0).withStartAmount(100).withEndAmount(100)
            .withRecipient(address(0)).saveDefault(
            "standardNativeConsiderationItem"
        );

        OfferItem memory standardWethOffer = OfferItemLib.empty().withItemType(
            ItemType.ERC20
        ).withToken(wethAddress).withIdentifierOrCriteria(0).withStartAmount(
            100
        ).withEndAmount(100).saveDefault("standardWethOfferItem");
        ConsiderationItem memory standardWethConsideration =
        ConsiderationItemLib.empty().withItemType(ItemType.ERC20).withToken(
            wethAddress
        ).withIdentifierOrCriteria(0).withStartAmount(100).withEndAmount(100)
            .withRecipient(address(0)).saveDefault("standardWethConsiderationItem");

        OfferItem memory standardERC20Offer = OfferItemLib.empty().withItemType(
            ItemType.ERC20
        ).withToken(_test20Address).withIdentifierOrCriteria(0).withStartAmount(
            100
        ).withEndAmount(100).saveDefault("standardERC20OfferItem");
        ConsiderationItem memory standardERC20Consideration =
        ConsiderationItemLib.empty().withItemType(ItemType.ERC20).withToken(
            _test20Address
        ).withIdentifierOrCriteria(0).withStartAmount(100).withEndAmount(100)
            .withRecipient(address(0)).saveDefault("standardERC20ConsiderationItem");

        OfferItem memory standardERC721Offer = OfferItemLib.empty().withItemType(
            ItemType.ERC721
        ).withToken(_test721Address).withIdentifierOrCriteria(1).withStartAmount(
            1
        ).withEndAmount(1).saveDefault("standardERC721OfferItem");
        ConsiderationItem memory standardERC721Consideration =
        ConsiderationItemLib.empty().withItemType(ItemType.ERC721).withToken(
            _test721Address
        ).withIdentifierOrCriteria(1).withStartAmount(1).withEndAmount(1)
            .withRecipient(address(0)).saveDefault("standard721ConsiderationItem");

        OfferItem memory standardERC1155Offer = OfferItemLib.empty()
            .withItemType(ItemType.ERC1155).withToken(_test1155Address)
            .withIdentifierOrCriteria(1).withStartAmount(1).withEndAmount(1)
            .saveDefault("standard1155OfferItem");

        ConsiderationItem memory standardERC1155Consideration =
        ConsiderationItemLib.empty().withItemType(ItemType.ERC1155).withToken(
            _test1155Address
        ).withIdentifierOrCriteria(1).withStartAmount(1).withEndAmount(1)
            .withRecipient(address(0)).saveDefault("standard1155ConsiderationItem");

        OfferItem[] memory adapterOrderOffer = new OfferItem[](1);
        ConsiderationItem[] memory adapterOrderConsideration =
            new ConsiderationItem[](1);

        adapterOrderOffer[0] = standardNativeOffer;
        adapterOrderOffer.saveDefaultMany("standardNativeOfferArray");
        adapterOrderConsideration[0] = standardNativeConsideration;
        adapterOrderConsideration.saveDefaultMany(
            "standardNativeConsiderationArray"
        );

        adapterOrderOffer[0] = standardWethOffer;
        adapterOrderOffer.saveDefaultMany("standardWethOfferArray");
        adapterOrderConsideration[0] = standardWethConsideration;
        adapterOrderConsideration.saveDefaultMany(
            "standardWethConsiderationArray"
        );

        adapterOrderOffer[0] = standardERC20Offer;
        adapterOrderOffer.saveDefaultMany("standardERC20OfferArray");
        adapterOrderConsideration[0] = standardERC20Consideration;
        adapterOrderConsideration.saveDefaultMany(
            "standardERC20ConsiderationArray"
        );

        adapterOrderOffer[0] = standardERC721Offer;
        adapterOrderOffer.saveDefaultMany("standardERC721OfferArray");
        adapterOrderConsideration[0] = standardERC721Consideration;
        adapterOrderConsideration.saveDefaultMany(
            "standardERC721ConsiderationArray"
        );

        adapterOrderOffer[0] = standardERC1155Offer;
        adapterOrderOffer.saveDefaultMany("standardERC1155OfferArray");
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
            stdCastOfCharacters, erc20Addresses, erc721Addresses
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
        Call memory params
    ) internal returns (uint256 gasUsed) {
        hevm.startPrank(sender);
        uint256 gasDelta;
        bool success;
        assembly {
            let to := mload(params)
            let value := mload(add(params, 0x40))
            let data := mload(add(params, 0x60))
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

        gasUsed = gasDelta + _additionalGasFee(params.callData);

        if (shouldLog) {
            emit log_named_uint(_formatLog(name, label), gasUsed);

            // After the && is just safety.
            if (shouldLogGasDelta && gasUsed > costOfLastCall) {
                emit log_named_uint("gas delta", gasUsed - costOfLastCall);
                // Separate a matched pair visually.
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
