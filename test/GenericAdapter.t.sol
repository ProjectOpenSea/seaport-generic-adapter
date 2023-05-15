// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ContractOffererInterface} from "seaport-types/interfaces/ContractOffererInterface.sol";

import {ReceivedItem, Schema, SpentItem} from "seaport-types/lib/ConsiderationStructs.sol";

import {ItemType} from "seaport-types/lib/ConsiderationEnums.sol";

import {SpentItemLib} from "seaport-sol/lib/SpentItemLib.sol";

import {GenericAdapterInterface} from "../src/interfaces/GenericAdapterInterface.sol";

import {FlashloanOffererInterface} from "../src/interfaces/FlashloanOffererInterface.sol";

import {GenericAdapter} from "../src/optimized/GenericAdapter.sol";

import {ReferenceGenericAdapter} from "../src/reference/ReferenceGenericAdapter.sol";

import {TestERC20} from "../src/contracts/test/TestERC20.sol";

import {TestERC20Revert} from "../src/contracts/test/TestERC20Revert.sol";

import {TestERC721} from "../src/contracts/test/TestERC721.sol";

import {TestERC721Revert} from "../src/contracts/test/TestERC721Revert.sol";

import {TestERC721} from "../src/contracts/test/TestERC721.sol";

import {TestERC1155} from "../src/contracts/test/TestERC1155.sol";

import {BaseOrderTest} from "./utils/BaseOrderTest.sol";

contract GenericAdapterTest is BaseOrderTest {
    using SpentItemLib for SpentItem;
    using SpentItemLib for SpentItem[];

    struct Context {
        GenericAdapterInterface adapter;
        FlashloanOffererInterface flashloanOfferer;
        bool isReference;
    }

    GenericAdapterInterface testAdapter;
    GenericAdapterInterface testAdapterReference;
    FlashloanOffererInterface testFlashloanOfferer;
    FlashloanOffererInterface testFlashloanOffererReference;
    TestERC721 testERC721;
    TestERC1155 testERC1155;
    bool rejectReceive;

    receive() external payable override {
        if (rejectReceive) {
            revert("rejectReceive");
        }
    }

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

        testAdapter = GenericAdapterInterface(
            deployCode(
                "out/GenericAdapter.sol/GenericAdapter.json",
                abi.encode(address(consideration), address(testFlashloanOfferer))
            )
        );
        testAdapterReference = GenericAdapterInterface(
            deployCode(
                "out/ReferenceGenericAdapter.sol/ReferenceGenericAdapter.json",
                abi.encode(address(consideration), address(testFlashloanOffererReference))
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

    function testReceive() public {
        test(
            this.execReceive,
            Context({adapter: testAdapter, flashloanOfferer: testFlashloanOfferer, isReference: false})
        );
        test(
            this.execReceive,
            Context({adapter: testAdapterReference, flashloanOfferer: testFlashloanOffererReference, isReference: true})
        );
    }

    function execReceive(Context memory context) external stateless {
        (bool success,) = address(context.adapter).call{value: 1 ether}("");
        require(success);
        assertEq(address(context.adapter).balance, 1 ether);

        testERC1155.mint(address(context.adapter), 1, 1);
        testERC721.mint(address(this), 1);
        testERC721.safeTransferFrom(address(this), address(context.adapter), 1);
    }

    function testSupportsInterface() public {
        test(
            this.execSupportsInterface,
            Context({adapter: testAdapter, flashloanOfferer: testFlashloanOfferer, isReference: false})
        );
        test(
            this.execSupportsInterface,
            Context({adapter: testAdapterReference, flashloanOfferer: testFlashloanOffererReference, isReference: true})
        );
    }

    function execSupportsInterface(Context memory context) external stateless {
        assertEq(context.adapter.supportsInterface(type(ContractOffererInterface).interfaceId), true);
    }

    function testGetSeaportMetadata() public {
        test(
            this.execGetSeaportMetadata,
            Context({adapter: testAdapter, flashloanOfferer: testFlashloanOfferer, isReference: false})
        );
        test(
            this.execGetSeaportMetadata,
            Context({adapter: testAdapterReference, flashloanOfferer: testFlashloanOffererReference, isReference: true})
        );
    }

    function execGetSeaportMetadata(Context memory context) external stateless {
        (string memory name, Schema[] memory schemas) = context.adapter.getSeaportMetadata();
        assertEq(name, "GenericAdapter");
        assertEq(schemas.length, 0);
    }

    function testCleanup() public {
        test(
            this.execCleanup,
            Context({adapter: testAdapter, flashloanOfferer: testFlashloanOfferer, isReference: false})
        );
        test(
            this.execCleanup,
            Context({adapter: testAdapterReference, flashloanOfferer: testFlashloanOffererReference, isReference: true})
        );
    }

    function execCleanup(Context memory context) external stateless {
        vm.expectRevert(abi.encodeWithSelector(GenericAdapterInterface.InvalidCaller.selector, address(this)));
        context.adapter.cleanup(address(this));

        // This is a no-op, but should not revert.
        vm.prank(address(context.flashloanOfferer));
        context.adapter.cleanup(address(this));

        // Send the adapter some native tokens.
        (bool success,) = address(context.adapter).call{value: 1 ether}("");
        require(success);
        assertEq(address(context.adapter).balance, 1 ether);

        // Sweep the native tokens to an arbitrary address.
        address arbitrary = address(0xdeafbeef);
        assertEq(arbitrary.balance, 0 ether);
        vm.prank(address(context.flashloanOfferer));
        context.adapter.cleanup(arbitrary);

        // The native tokens should have been swept.
        assertEq(arbitrary.balance, 1 ether);
        assertEq(address(context.adapter).balance, 0 ether);
    }

    function testGenerateOrderThresholdReverts() public {
        test(
            this.execGenerateOrderThresholdReverts,
            Context({adapter: testAdapter, flashloanOfferer: testFlashloanOfferer, isReference: false})
        );
        test(
            this.execGenerateOrderThresholdReverts,
            Context({adapter: testAdapterReference, flashloanOfferer: testFlashloanOffererReference, isReference: true})
        );
    }

    function execGenerateOrderThresholdReverts(Context memory context) external stateless {
        vm.expectRevert(abi.encodeWithSelector(GenericAdapterInterface.InvalidExtraDataEncoding.selector, 0));
        context.adapter.generateOrder(address(this), new SpentItem[](0), new SpentItem[](0), "");

        vm.expectRevert(abi.encodeWithSelector(GenericAdapterInterface.InvalidCaller.selector, address(this)));
        context.adapter.generateOrder(
            address(this), new SpentItem[](0), new SpentItem[](0), abi.encodePacked(bytes32(0), bytes32(0))
        );

        vm.expectRevert(abi.encodeWithSelector(GenericAdapterInterface.UnsupportedExtraDataVersion.selector, 0xff));
        vm.prank(address(consideration));
        context.adapter.generateOrder(
            address(this),
            new SpentItem[](0),
            new SpentItem[](0),
            abi.encodePacked(bytes32(0xff00000000000000000000000000000000000000000000000000000000000000), bytes32(0))
        );

        vm.expectRevert(abi.encodeWithSelector(GenericAdapterInterface.InvalidExtraDataEncoding.selector, 0));
        vm.prank(address(consideration));
        context.adapter.generateOrder(
            address(this), new SpentItem[](0), new SpentItem[](0), abi.encodePacked(bytes32(0), bytes32(0))
        );

        TestERC20Revert testERC20Revert = new TestERC20Revert();

        uint256 firstWord = 0x0011111111111111111111111111111111111111111111111111111100000036;
        address erc20Address = address(testERC20Revert);
        uint256 erc20AddressShifted = uint256(uint160(erc20Address)) << 80;
        uint256 secondWord;

        assembly {
            secondWord := or(shl(248, 0x01), erc20AddressShifted)
        }

        // Second word is something like this:
        // 0x01002a07706473244bc757e10f2a9e86fb532828afe300000000000000000000
        // The first byte is number of approvals (one), second is approval type
        // (0 for erc20), next 20 are addy, finalbytes are not used.

        if (context.isReference) {
            vm.expectRevert(abi.encodeWithSelector(GenericAdapterInterface.ApprovalFailed.selector, erc20Address));
        } else {
            vm.expectRevert(abi.encodeWithSignature("AlwaysRevert()"));
        }
        vm.prank(address(consideration));
        context.adapter.generateOrder(
            address(this),
            new SpentItem[](0),
            new SpentItem[](0),
            abi.encodePacked(
                // First byte is encoding. Last 4 are context length. 1s are
                // just disregarded, it seems.
                bytes32(firstWord),
                // First byte is the number of approvals, second is approval
                // type, next 20 are addy.
                bytes32(secondWord)
            )
        );

        (bool avoidWarning, bytes memory data) =
            address(testERC20Revert).call(abi.encodeWithSignature("setRevertSpectacularly(bool)", true));
        if (!avoidWarning || data.length != 0) {
            revert("Just trying to make the compiler happy");
        }
        vm.expectRevert(abi.encodeWithSelector(GenericAdapterInterface.ApprovalFailed.selector, erc20Address));

        vm.prank(address(consideration));
        context.adapter.generateOrder(
            address(this),
            new SpentItem[](0),
            new SpentItem[](0),
            abi.encodePacked(bytes32(firstWord), bytes32(secondWord))
        );

        TestERC721Revert testERC721Revert = new TestERC721Revert();

        address erc721Address = address(testERC721Revert);
        secondWord = uint256(uint160(erc721Address)) << 80;

        assembly {
            // Set the number of approvals.
            secondWord := or(shl(248, 0x01), secondWord)
            // Set the approval type.
            secondWord := or(shl(240, 0x01), secondWord)
        }

        if (context.isReference) {
            vm.expectRevert(abi.encodeWithSelector(GenericAdapterInterface.ApprovalFailed.selector, erc721Address));
        } else {
            vm.expectRevert(abi.encodeWithSignature("AlwaysRevert()"));
        }
        vm.prank(address(consideration));
        context.adapter.generateOrder(
            address(this),
            new SpentItem[](0),
            new SpentItem[](0),
            abi.encodePacked(bytes32(firstWord), bytes32(secondWord))
        );

        (avoidWarning, data) =
            address(testERC721Revert).call(abi.encodeWithSignature("setRevertSpectacularly(bool)", true));

        vm.expectRevert(abi.encodeWithSelector(GenericAdapterInterface.ApprovalFailed.selector, erc721Address));
        vm.prank(address(consideration));
        context.adapter.generateOrder(
            address(this),
            new SpentItem[](0),
            new SpentItem[](0),
            abi.encodePacked(bytes32(firstWord), bytes32(secondWord))
        );
    }

    function testApprovals() public {
        test(
            this.execApprovals,
            Context({adapter: testAdapter, flashloanOfferer: testFlashloanOfferer, isReference: false})
        );
        test(
            this.execApprovals,
            Context({adapter: testAdapterReference, flashloanOfferer: testFlashloanOffererReference, isReference: true})
        );
    }

    function execApprovals(Context memory context) external stateless {
        TestERC20 testERC20 = new TestERC20();
        TestERC721 testERC721 = new TestERC721();

        uint256 firstWord = 0x0011111111111111111111111111111111111111111111111111111100000036;
        address erc20Address = address(testERC20);
        uint256 erc20AddressShifted = uint256(uint160(erc20Address)) << 80;
        uint256 secondWord;

        assembly {
            secondWord := or(shl(248, 0x01), erc20AddressShifted)
        }

        vm.prank(address(consideration));
        context.adapter.generateOrder(
            address(this),
            new SpentItem[](0),
            new SpentItem[](0),
            abi.encodePacked(bytes32(firstWord), bytes32(secondWord))
        );

        assertEq(testERC20.allowance(address(context.adapter), address(consideration)), type(uint256).max);

        address erc721Address = address(testERC721);
        secondWord = uint256(uint160(erc721Address)) << 80;

        assembly {
            secondWord := or(shl(248, 0x01), secondWord)
            secondWord := or(shl(240, 0x01), secondWord)
        }

        vm.prank(address(consideration));
        context.adapter.generateOrder(
            address(this),
            new SpentItem[](0),
            new SpentItem[](0),
            abi.encodePacked(bytes32(firstWord), bytes32(secondWord))
        );

        assertTrue(testERC721.isApprovedForAll(address(context.adapter), address(consideration)));
    }

    function testTransfersToSideCar() public {
        test(
            this.execTransfersToSideCar,
            Context({adapter: testAdapter, flashloanOfferer: testFlashloanOfferer, isReference: false})
        );
        test(
            this.execTransfersToSideCar,
            Context({adapter: testAdapterReference, flashloanOfferer: testFlashloanOffererReference, isReference: true})
        );
    }

    function execTransfersToSideCar(Context memory context) external stateless {
        // TODO: add native.
        TestERC20 testERC20 = new TestERC20();
        TestERC721 testERC721 = new TestERC721();
        TestERC1155 testERC1155 = new TestERC1155();

        SpentItem[] memory spentItems = new SpentItem[](3);

        SpentItem memory spentItemERC20 = SpentItem(ItemType.ERC20, address(testERC20), 0, 1);
        SpentItem memory spentItemERC721 = SpentItem(ItemType.ERC721, address(testERC721), 1, 1);
        SpentItem memory spentItemERC1155 = SpentItem(ItemType.ERC1155, address(testERC1155), 2, 1);

        spentItems[0] = spentItemERC20;
        spentItems[1] = spentItemERC721;
        spentItems[2] = spentItemERC1155;

        // TODO: Update the size once the approvals and Calls are added.
        uint256 firstWord = 0x0011111111111111111111111111111111111111111111111111111100000060;
        uint256 secondWord;
        uint256 thirdWord;

        // Add the ERC20 address to the second word.
        address erc20Address = address(testERC20);
        uint256 erc20AddressShifted = uint256(uint160(erc20Address)) << 80;

        address erc721Address = address(testERC721);
        address erc1155Address = address(testERC1155);

        assembly {
            // Insert the number of approvals into the second word. Becomes:
            // 0x0300e54a55121a47451c5727adbaf9b9fc1643477e2500000000000000000000
            secondWord := or(shl(248, 0x03), erc20AddressShifted)
            // Insert the approval type for the second item into the second word
            // Becomes:
            // 0x0300e54a55121a47451c5727adbaf9b9fc1643477e2501000000000000000000
            secondWord := or(shl(72, 0x01), secondWord)
            // Insert the first 9 bytes of the ERC721 address into the second
            // word.  Becomes:
            // 0x0300e54a55121a47451c5727adbaf9b9fc1643477e250194771550282853f6e0
            secondWord := or(shr(88, erc721Address), secondWord)

            // Insert the remaining 11 bytes of the ERC721 address into the third
            // word. Becomes:
            // 0x124c302f7de1cf50aa45ca000000000000000000000000000000000000000000
            thirdWord := shl(168, erc721Address)
            // Insert the approval type for the third item into the third word.
            // Becomes:
            // 0x124c302f7de1cf50aa45ca010000000000000000000000000000000000000000
            thirdWord := or(shl(160, 0x01), thirdWord)
            // Insert the ERC1155 address into the third word. Becomes:
            // 0x124c302f7de1cf50aa45ca018227724c33c1748a42d1c1cd06e21ab8deb6eb0a
            thirdWord := or(erc1155Address, thirdWord)
        }

        emit log_named_bytes32("firstWord ", bytes32(firstWord));
        emit log_named_bytes32("secondWord", bytes32(secondWord));
        emit log_named_bytes32("thirdWord ", bytes32(thirdWord));

        if (context.isReference) {
            emit log_named_address("reference", address(context.adapter));
        } else {
            emit log_named_address("optimized", address(context.adapter));
        }

        // TODO: set approvals.
        // TODO: add calls.

        vm.prank(address(consideration));
        context.adapter.generateOrder(
            address(this), new SpentItem[](0), spentItems, abi.encodePacked(bytes32(firstWord), bytes32(secondWord), bytes32(thirdWord))
        );
    }
}
