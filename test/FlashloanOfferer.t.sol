// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ContractOffererInterface} from "seaport-types/interfaces/ContractOffererInterface.sol";

import {FlashloanOffererInterface} from "../src/interfaces/FlashloanOffererInterface.sol";

import {TestERC721} from "../src/contracts/test/TestERC721.sol";

import {TestERC1155} from "../src/contracts/test/TestERC1155.sol";

import {BaseOrderTest} from "./utils/BaseOrderTest.sol";

import {ReceivedItem, Schema, SpentItem} from "seaport-types/lib/ConsiderationStructs.sol";

import {ItemType} from "seaport-types/lib/ConsiderationEnums.sol";

contract FlashloanOffererTest is BaseOrderTest {
    struct Context {
        FlashloanOffererInterface flashloanOfferer;
        bool isReference;
    }

    FlashloanOffererInterface testFlashloanOfferer;
    FlashloanOffererInterface testFlashloanOffererReference;
    TestERC721 testERC721;
    TestERC1155 testERC1155;

    function setUp() public override {
        super.setUp();

        testFlashloanOfferer = FlashloanOffererInterface(
            deployCode("out/FlashloanOfferer.sol/FlashloanOfferer.json", abi.encode(address(consideration)))
        );

        testFlashloanOffererReference = FlashloanOffererInterface(
            deployCode(
                "out/ReferenceFlashloanOfferer.sol/ReferenceFlashloanOfferer.json", abi.encode(address(consideration))
            )
        );

        testERC721 = new TestERC721();
        testERC1155 = new TestERC1155();
    }

    function test(function(Context memory) external fn, Context memory context) internal {
        try fn(context) {
            fail("Stateless test function should have reverted with assertion failure status.");
        } catch (bytes memory reason) {
            assertPass(reason);
        }
    }

    function testFlashloanOffererReceive() public {
        test(this.execReceive, Context({flashloanOfferer: testFlashloanOfferer, isReference: false}));
        test(this.execReceive, Context({flashloanOfferer: testFlashloanOffererReference, isReference: true}));
    }

    function execReceive(Context memory context) external stateless {
        (bool success,) = address(context.flashloanOfferer).call{value: 1 ether}("");
        require(success);
        assertEq(address(context.flashloanOfferer).balance, 1 ether);

        testERC1155.mint(address(context.flashloanOfferer), 1, 1);
        testERC721.mint(address(this), 2);
        testERC721.safeTransferFrom(address(this), address(context.flashloanOfferer), 2);
    }

    function testSupportsInterface() public {
        test(this.execSupportsInterface, Context({flashloanOfferer: testFlashloanOfferer, isReference: false}));
        test(this.execSupportsInterface, Context({flashloanOfferer: testFlashloanOffererReference, isReference: true}));
    }

    function execSupportsInterface(Context memory context) external stateless {
        assertEq(context.flashloanOfferer.supportsInterface(type(ContractOffererInterface).interfaceId), true);
    }

    function testGetSeaportMetadata() public {
        test(this.execGetSeaportMetadata, Context({flashloanOfferer: testFlashloanOfferer, isReference: false}));
        test(this.execGetSeaportMetadata, Context({flashloanOfferer: testFlashloanOffererReference, isReference: true}));
    }

    function execGetSeaportMetadata(Context memory context) external stateless {
        (string memory name, Schema[] memory schemas) = context.flashloanOfferer.getSeaportMetadata();
        assertEq(name, "FlashloanOfferer");
        assertEq(schemas.length, 0);
    }

    function testGenerateOrderThresholdReverts() public {
        test(
            this.execGenerateOrderThresholdReverts,
            Context({flashloanOfferer: testFlashloanOfferer, isReference: false})
        );
        test(
            this.execGenerateOrderThresholdReverts,
            Context({flashloanOfferer: testFlashloanOffererReference, isReference: true})
        );
    }

    function execGenerateOrderThresholdReverts(Context memory context) external stateless {
        vm.expectRevert(abi.encodeWithSelector(FlashloanOffererInterface.InvalidTotalMaximumSpentItems.selector));
        context.flashloanOfferer.generateOrder(address(this), new SpentItem[](0), new SpentItem[](0), "");

        vm.expectRevert(abi.encodeWithSelector(FlashloanOffererInterface.InvalidTotalMaximumSpentItems.selector));
        context.flashloanOfferer.generateOrder(address(this), new SpentItem[](0), new SpentItem[](2), "");

        vm.expectRevert(abi.encodeWithSelector(FlashloanOffererInterface.InvalidTotalMinimumReceivedItems.selector));
        context.flashloanOfferer.generateOrder(address(this), new SpentItem[](2), new SpentItem[](1), "");

        vm.expectRevert(abi.encodeWithSelector(FlashloanOffererInterface.InvalidCaller.selector, address(this)));
        context.flashloanOfferer.generateOrder(
            address(this),
            new SpentItem[](0),
            new SpentItem[](1),
            abi.encodePacked(bytes32(0x0011111111111111111111111111111111111111111111111111111100000036))
        );

        vm.prank(address(consideration));
        vm.expectRevert(abi.encodeWithSelector(FlashloanOffererInterface.UnsupportedExtraDataVersion.selector, 255));
        context.flashloanOfferer.generateOrder(
            address(this),
            new SpentItem[](0),
            new SpentItem[](1),
            abi.encodePacked(
                bytes32(0xff11111111111111111111111111111111111111111111111111111100000001),
                bytes32(0x2222222222222222222222222222222222222222330000000000000000000000)
            )
        );

        // Triggered by contextLength == 0.
        vm.prank(address(consideration));
        vm.expectRevert(abi.encodeWithSelector(FlashloanOffererInterface.InvalidExtraDataEncoding.selector, 0));
        context.flashloanOfferer.generateOrder(
            address(this),
            new SpentItem[](0),
            new SpentItem[](1),
            abi.encodePacked(
                bytes32(0x0011111111111111111111111111111111111111111111111111111100000000),
                bytes32(0x2222222222222222222222222222222222222222330000000000000000000000)
            )
        );

        // Triggered by contextLength < 22 + flashloanDataLength.
        vm.prank(address(consideration));
        vm.expectRevert(abi.encodeWithSelector(FlashloanOffererInterface.InvalidExtraDataEncoding.selector, 0));
        context.flashloanOfferer.generateOrder(
            address(this),
            new SpentItem[](0),
            new SpentItem[](1),
            abi.encodePacked(
                bytes32(0x00111111111111111111111111111111111111111111111111111111000000ff),
                bytes32(0x2222222222222222222222222222222222222222ff0000000000000000000000)
            )
        );

        // BEGING DEPOSIT AND WITHDRAWAL THRESHOLD REVERT TESTING

        // Revert if minimumReceived item amount is greater than
        // maximumSpent, or if any of the following are not true:
        //  - one of the item types is 1 and the other is 0
        //  - one of the tokens is address(this) and the other is null
        //  - item type 1 has address(this) token and 0 is null token

        SpentItem[] memory minimumReceived = new SpentItem[](1);
        SpentItem[] memory maximumSpent = new SpentItem[](1);

        SpentItem memory spentItemMinReceived;
        SpentItem memory spentItemMaxSpent;

        spentItemMinReceived = SpentItem(ItemType.ERC20, address(context.flashloanOfferer), 0, 1 ether);
        spentItemMaxSpent = SpentItem(ItemType.NATIVE, address(0), 0, 2 ether);

        minimumReceived[0] = spentItemMinReceived;
        maximumSpent[0] = spentItemMaxSpent;

        // Make one that sneaks through to confirm that the test is valid.
        // InvalidExtraDataEncoding is downstream of the threshold checks at
        // issue here.
        vm.prank(address(consideration));
        vm.expectRevert(abi.encodeWithSelector(FlashloanOffererInterface.InvalidExtraDataEncoding.selector, 0));
        context.flashloanOfferer.generateOrder(
            address(this), minimumReceived, maximumSpent, abi.encodePacked(bytes32(0))
        );

        // Mess up the amount.
        spentItemMinReceived = SpentItem(ItemType.ERC20, address(context.flashloanOfferer), 0, 3 ether);
        minimumReceived[0] = spentItemMinReceived;

        vm.expectRevert(abi.encodeWithSelector(FlashloanOffererInterface.MinGreaterThanMax.selector));
        vm.prank(address(consideration));
        context.flashloanOfferer.generateOrder(
            address(this), minimumReceived, maximumSpent, abi.encodePacked(bytes32(0))
        );

        // Put back the amount but mess up the type.
        spentItemMinReceived = SpentItem(ItemType.NATIVE, address(0), 0, 1 ether);
        minimumReceived[0] = spentItemMinReceived;

        vm.expectRevert(abi.encodeWithSelector(FlashloanOffererInterface.SharedItemTypes.selector));
        vm.prank(address(consideration));
        context.flashloanOfferer.generateOrder(
            address(this), minimumReceived, maximumSpent, abi.encodePacked(bytes32(0))
        );

        // Put back the type but mess up the token.
        spentItemMinReceived = SpentItem(ItemType.ERC20, address(token1), 0, 1 ether);
        minimumReceived[0] = spentItemMinReceived;

        vm.expectRevert(abi.encodeWithSelector(FlashloanOffererInterface.UnacceptableTokenPairing.selector));
        vm.prank(address(consideration));
        context.flashloanOfferer.generateOrder(
            address(this), minimumReceived, maximumSpent, abi.encodePacked(bytes32(0))
        );

        // Mess up the token a different way.
        spentItemMinReceived = SpentItem(ItemType.ERC20, address(0), 0, 1 ether);
        minimumReceived[0] = spentItemMinReceived;

        vm.expectRevert(abi.encodeWithSelector(FlashloanOffererInterface.UnacceptableTokenPairing.selector));
        vm.prank(address(consideration));
        context.flashloanOfferer.generateOrder(
            address(this), minimumReceived, maximumSpent, abi.encodePacked(bytes32(0))
        );

        // Put the token back but jumble up types and addresses.
        spentItemMinReceived = SpentItem(ItemType.NATIVE, address(context.flashloanOfferer), 0, 1 ether);
        minimumReceived[0] = spentItemMinReceived;
        spentItemMaxSpent = SpentItem(ItemType.ERC20, address(context.flashloanOfferer), 0, 2 ether);
        maximumSpent[0] = spentItemMaxSpent;

        vm.expectRevert(abi.encodeWithSelector(FlashloanOffererInterface.MismatchedAddresses.selector));
        vm.prank(address(consideration));
        context.flashloanOfferer.generateOrder(
            address(this), minimumReceived, maximumSpent, abi.encodePacked(bytes32(0))
        );
    }
}
