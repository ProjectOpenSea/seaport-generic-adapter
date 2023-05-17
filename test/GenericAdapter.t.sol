// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Vm} from "forge-std/Vm.sol";

import {ContractOffererInterface} from "seaport-types/interfaces/ContractOffererInterface.sol";

import {ReceivedItem, Schema, SpentItem} from "seaport-types/lib/ConsiderationStructs.sol";

import {ItemType} from "seaport-types/lib/ConsiderationEnums.sol";

import {SpentItemLib} from "seaport-sol/lib/SpentItemLib.sol";

import {GenericAdapterInterface} from "../src/interfaces/GenericAdapterInterface.sol";

import {FlashloanOffererInterface} from "../src/interfaces/FlashloanOffererInterface.sol";

import {GenericAdapter} from "../src/optimized/GenericAdapter.sol";

import {ReferenceGenericAdapter} from "../src/reference/ReferenceGenericAdapter.sol";

import {Call, GenericAdapterSidecarInterface} from "../src/interfaces/GenericAdapterSidecarInterface.sol";

import {TestERC20} from "../src/contracts/test/TestERC20.sol";

import {TestERC20Revert} from "../src/contracts/test/TestERC20Revert.sol";

import {TestERC721} from "../src/contracts/test/TestERC721.sol";

import {TestERC721Revert} from "../src/contracts/test/TestERC721Revert.sol";

import {TestERC721} from "../src/contracts/test/TestERC721.sol";

import {TestERC1155} from "../src/contracts/test/TestERC1155.sol";

import {BaseOrderTest} from "./utils/BaseOrderTest.sol";

import "forge-std/console.sol";

contract GenericAdapterTest is BaseOrderTest {
    using SpentItemLib for SpentItem;
    using SpentItemLib for SpentItem[];

    struct Context {
        GenericAdapterInterface adapter;
        FlashloanOffererInterface flashloanOfferer;
        GenericAdapterSidecarInterface sidecar;
        bool isReference;
    }

    GenericAdapterInterface testAdapter;
    GenericAdapterInterface testAdapterReference;
    FlashloanOffererInterface testFlashloanOfferer;
    FlashloanOffererInterface testFlashloanOffererReference;
    GenericAdapterSidecarInterface testSidecar;
    GenericAdapterSidecarInterface testSidecarReference;
    TestERC721 testERC721;
    TestERC1155 testERC1155;
    bool rejectReceive;
    bool erc20CallExecuted;
    bool erc721CallExecuted;
    bool erc1155CallExecuted;
    uint256 nativeAction;

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

        vm.recordLogs();

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

        Vm.Log[] memory entries = vm.getRecordedLogs();

        testSidecar = GenericAdapterSidecarInterface(abi.decode(entries[0].data, (address)));
        testSidecarReference = GenericAdapterSidecarInterface(abi.decode(entries[1].data, (address)));

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
            Context({
                adapter: testAdapter,
                flashloanOfferer: testFlashloanOfferer,
                sidecar: testSidecar,
                isReference: false
            })
        );
        test(
            this.execReceive,
            Context({
                adapter: testAdapterReference,
                flashloanOfferer: testFlashloanOffererReference,
                sidecar: testSidecarReference,
                isReference: true
            })
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
            Context({
                adapter: testAdapter,
                flashloanOfferer: testFlashloanOfferer,
                sidecar: testSidecar,
                isReference: false
            })
        );
        test(
            this.execSupportsInterface,
            Context({
                adapter: testAdapterReference,
                flashloanOfferer: testFlashloanOffererReference,
                sidecar: testSidecarReference,
                isReference: true
            })
        );
    }

    function execSupportsInterface(Context memory context) external stateless {
        assertEq(context.adapter.supportsInterface(type(ContractOffererInterface).interfaceId), true);
    }

    function testGetSeaportMetadata() public {
        test(
            this.execGetSeaportMetadata,
            Context({
                adapter: testAdapter,
                flashloanOfferer: testFlashloanOfferer,
                sidecar: testSidecar,
                isReference: false
            })
        );
        test(
            this.execGetSeaportMetadata,
            Context({
                adapter: testAdapterReference,
                flashloanOfferer: testFlashloanOffererReference,
                sidecar: testSidecarReference,
                isReference: true
            })
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
            Context({
                adapter: testAdapter,
                flashloanOfferer: testFlashloanOfferer,
                sidecar: testSidecar,
                isReference: false
            })
        );
        test(
            this.execCleanup,
            Context({
                adapter: testAdapterReference,
                flashloanOfferer: testFlashloanOffererReference,
                sidecar: testSidecarReference,
                isReference: true
            })
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
            Context({
                adapter: testAdapter,
                flashloanOfferer: testFlashloanOfferer,
                sidecar: testSidecar,
                isReference: false
            })
        );
        test(
            this.execGenerateOrderThresholdReverts,
            Context({
                adapter: testAdapterReference,
                flashloanOfferer: testFlashloanOffererReference,
                sidecar: testSidecarReference,
                isReference: true
            })
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
            Context({
                adapter: testAdapter,
                flashloanOfferer: testFlashloanOfferer,
                sidecar: testSidecar,
                isReference: false
            })
        );
        test(
            this.execApprovals,
            Context({
                adapter: testAdapterReference,
                flashloanOfferer: testFlashloanOffererReference,
                sidecar: testSidecarReference,
                isReference: true
            })
        );
    }

    function execApprovals(Context memory context) external stateless {
        TestERC20 testERC20 = new TestERC20();

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

    function testTransfersToSidecarAndExecute() public {
        test(
            this.execTransfersToSidecarAndExecute,
            Context({
                adapter: testAdapter,
                flashloanOfferer: testFlashloanOfferer,
                sidecar: testSidecar,
                isReference: false
            })
        );
        test(
            this.execTransfersToSidecarAndExecute,
            Context({
                adapter: testAdapterReference,
                flashloanOfferer: testFlashloanOffererReference,
                sidecar: testSidecarReference,
                isReference: true
            })
        );
    }

    function execTransfersToSidecarAndExecute(Context memory context) external stateless {
        // TODO: add native.
        TestERC20 testERC20 = new TestERC20();

        SpentItem[] memory spentItems = new SpentItem[](3);

        {
            SpentItem memory spentItemERC20 = SpentItem(ItemType.ERC20, address(testERC20), 0, 1);
            SpentItem memory spentItemERC721 = SpentItem(ItemType.ERC721, address(testERC721), 1, 1);
            SpentItem memory spentItemERC1155 = SpentItem(ItemType.ERC1155, address(testERC1155), 1, 1);

            spentItems[0] = spentItemERC20;
            spentItems[1] = spentItemERC721;
            spentItems[2] = spentItemERC1155;
        }

        uint256 firstWord = 0x00111111111111111111111111111111111111111111111111111111000003B6; // ...060 before
        uint256 secondWord;
        uint256 thirdWord;

        // Add the ERC20 address to the second word.
        address erc20Address = address(testERC20);
        uint256 erc20AddressShifted = uint256(uint160(erc20Address)) << 80;

        address erc721Address = address(testERC721);
        address erc1155Address = address(testERC1155);

        assembly {
            // Insert the number of approvals into the second word. Becomes
            // something like:
            // 0x0300e54a55121a47451c5727adbaf9b9fc1643477e2500000000000000000000
            secondWord := or(shl(248, 0x03), erc20AddressShifted)
            // Insert the approval type for the second item into the second word
            // Becomes something like:
            // 0x0300e54a55121a47451c5727adbaf9b9fc1643477e2501000000000000000000
            secondWord := or(shl(72, 0x01), secondWord)
            // Insert the first 9 bytes of the ERC721 address into the second
            // word.  Becomes something like:
            // 0x0300e54a55121a47451c5727adbaf9b9fc1643477e250194771550282853f6e0
            secondWord := or(shr(88, erc721Address), secondWord)

            // Insert the remaining 11 bytes of the ERC721 address into the third
            // word. Becomes something like:
            // 0x124c302f7de1cf50aa45ca000000000000000000000000000000000000000000
            thirdWord := shl(168, erc721Address)
            // Insert the approval type for the third item into the third word.
            // Becomes something like:
            // 0x124c302f7de1cf50aa45ca010000000000000000000000000000000000000000
            thirdWord := or(shl(160, 0x01), thirdWord)
            // Insert the ERC1155 address into the third word. Becomes something
            // like:
            // 0x124c302f7de1cf50aa45ca018227724c33c1748a42d1c1cd06e21ab8deb6eb0a
            thirdWord := or(erc1155Address, thirdWord)
        }

        testERC20.approve(address(context.adapter), type(uint256).max);
        testERC20.mint(address(this), 1);
        testERC721.setApprovalForAll(address(context.adapter), true);
        testERC721.mint(address(this), 1);
        testERC1155.setApprovalForAll(address(context.adapter), true);
        testERC1155.mint(address(this), 1, 1);

        // TODO: Test that a mix of failing and succeeding calls works as
        // expected given a mix of `allowFailure` bools.

        Call[] memory calls = new Call[](3);

        {
            Call memory callERC20 = Call(
                address(this), // TODO: put in some marketplace addy here.
                false,
                0, // TODO: Native and flashloan offerer stuff.
                abi.encodeWithSelector(this.toggleERC20Call.selector, true)
            );

            Call memory callERC721 = Call(
                address(this), // TODO: put in some marketplace addy here.
                false,
                0, // TODO: Native and flashloan offerer stuff.
                abi.encodeWithSelector(this.toggleERC721Call.selector, true)
            );

            Call memory callERC1155 = Call(
                address(this), // TODO: put in some marketplace addy here.
                false,
                0, // TODO: Native and flashloan offerer stuff.
                abi.encodeWithSelector(this.toggleERC1155Call.selector, true)
            );

            calls[0] = callERC20;
            calls[1] = callERC721;
            calls[2] = callERC1155;
        }

        bytes memory contextArg;

        {
            bytes memory contextArgApprovalPortion =
                abi.encode(bytes32(firstWord), bytes32(secondWord), bytes32(thirdWord));

            bytes memory contextArgCalldataPortion = abi.encode(calls);

            contextArg = abi.encodePacked(contextArgApprovalPortion, contextArgCalldataPortion);
        }

        assertEq(testERC20.balanceOf(address(context.sidecar)), 0, "sidecar should have no ERC20");
        assertEq(testERC721.ownerOf(1), address(this), "this should own ERC721");
        assertEq(testERC1155.balanceOf(address(this), 1), 1, "this should own ERC1155");

        assertFalse(erc20CallExecuted, "erc20CallExecuted should be false");
        assertFalse(erc721CallExecuted, "erc721CallExecuted should be false");
        assertFalse(erc1155CallExecuted, "erc1155CallExecuted should be false");

        vm.prank(address(consideration));
        context.adapter.generateOrder(address(this), new SpentItem[](0), spentItems, contextArg);

        assertEq(testERC20.balanceOf(address(context.sidecar)), 1, "sidecar should have ERC20");
        assertEq(testERC721.ownerOf(1), address(context.sidecar), "sidecar should own ERC721");
        assertEq(testERC1155.balanceOf(address(context.sidecar), 1), 1, "sidecar should own ERC1155");

        assertTrue(erc20CallExecuted, "erc20CallExecuted should be true");
        assertTrue(erc721CallExecuted, "erc721CallExecuted should be true");
        assertTrue(erc1155CallExecuted, "erc1155CallExecuted should be true");

        // TODO: test that the sidecar can actually transfer the items.
        // TODO: test that the sidecar doesn't need another approval after the
        //       approval is done the first time.
    }

    function toggleERC20Call(bool called) external {
        erc20CallExecuted = called;
    }

    function toggleERC721Call(bool called) external {
        erc721CallExecuted = called;
    }

    function toggleERC1155Call(bool called) external {
        erc1155CallExecuted = called;
    }

    function testNativeCallAndExecute() public {
        test(
            this.execNativeCallAndExecute,
            Context({
                adapter: testAdapter,
                flashloanOfferer: testFlashloanOfferer,
                sidecar: testSidecar,
                isReference: false
            })
        );
        test(
            this.execNativeCallAndExecute,
            Context({
                adapter: testAdapterReference,
                flashloanOfferer: testFlashloanOffererReference,
                sidecar: testSidecarReference,
                isReference: true
            })
        );
    }

    function execNativeCallAndExecute(Context memory context) external stateless {
        SpentItem[] memory spentItems = new SpentItem[](3);

        {
            SpentItem memory spentItemNativeOne = SpentItem(ItemType.NATIVE, address(0), 0, 1 ether);

            spentItems[0] = spentItemNativeOne;
            spentItems[1] = spentItemNativeOne;
            spentItems[2] = spentItemNativeOne;
        }

        // One bytes of SIP encoding, a bunch of empty space, 4 bytes of context length.
        uint256 firstWord = 0x0022222222222222222222222222222222222222222222222222222200000340;

        Call[] memory calls = new Call[](3);

        {
            Call memory callNative = Call(
                address(this), false, 1 ether, abi.encodeWithSelector(this.incrementNativeAction.selector, 1 ether)
            );

            calls[0] = callNative;
            calls[1] = callNative;
            calls[2] = callNative;
        }

        bytes memory contextArgCalldataPortion = abi.encode(calls);

        bytes memory contextArg;

        contextArg = abi.encodePacked(firstWord, bytes1(0), contextArgCalldataPortion);

        assertEq(nativeAction, 0, "nativeAction should be 0");

        vm.deal(address(context.adapter), 3 ether);

        vm.prank(address(consideration));
        context.adapter.generateOrder(address(this), new SpentItem[](0), spentItems, contextArg);

        assertEq(nativeAction, 3 ether, "nativeAction should be 3 ether");
    }

    function incrementNativeAction(uint256 amount) external payable {
        assertGt(msg.value, amount - 0.001 ether, "msg.value should be roughly equal to amount");
        assertLt(msg.value, amount + 0.001 ether, "msg.value should be roughly equal to amount");
        nativeAction += msg.value;
    }
}

// TODO: Stub out some marketplace contracts and start making calls to them.
