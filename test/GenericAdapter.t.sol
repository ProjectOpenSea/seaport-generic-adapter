// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Vm } from "forge-std/Vm.sol";

import { StdCheats } from "forge-std/StdCheats.sol";

import { WETH } from "solady/src/tokens/WETH.sol";

import { AdvancedOrderLib } from "seaport-sol/lib/AdvancedOrderLib.sol";

import { ConsiderationItemLib } from "seaport-sol/lib/ConsiderationItemLib.sol";

import { OfferItemLib } from "seaport-sol/lib/OfferItemLib.sol";

import { OrderParametersLib } from "seaport-sol/lib/OrderParametersLib.sol";

import { SpentItemLib } from "seaport-sol/lib/SpentItemLib.sol";

import { UnavailableReason } from "seaport-sol/SpaceEnums.sol";

import {
    AdvancedOrder,
    ConsiderationItem,
    CriteriaResolver,
    Fulfillment,
    FulfillmentComponent,
    OfferItem,
    OrderParameters,
    ReceivedItem,
    Schema,
    SpentItem
} from "seaport-types/lib/ConsiderationStructs.sol";

import { ItemType, OrderType } from "seaport-types/lib/ConsiderationEnums.sol";

import { ContractOffererInterface } from
    "seaport-types/interfaces/ContractOffererInterface.sol";

import { GenericAdapterInterface } from
    "../src/interfaces/GenericAdapterInterface.sol";

import { FlashloanOffererInterface } from
    "../src/interfaces/FlashloanOffererInterface.sol";

import { GenericAdapter } from "../src/optimized/GenericAdapter.sol";

import { ReferenceGenericAdapter } from
    "../src/reference/ReferenceGenericAdapter.sol";

import {
    Call,
    GenericAdapterSidecarInterface
} from "../src/interfaces/GenericAdapterSidecarInterface.sol";

import { TestERC20 } from "../src/contracts/test/TestERC20.sol";

import { TestERC20Revert } from "../src/contracts/test/TestERC20Revert.sol";

import { TestERC721 } from "../src/contracts/test/TestERC721.sol";

import { TestERC721Revert } from "../src/contracts/test/TestERC721Revert.sol";

import { TestERC721 } from "../src/contracts/test/TestERC721.sol";

import { TestERC1155 } from "../src/contracts/test/TestERC1155.sol";

import { BaseOrderTest } from "./utils/BaseOrderTest.sol";

import {
    AdapterHelperLib,
    Approval,
    Flashloan
} from "../src/lib/AdapterHelperLib.sol";

import "forge-std/console.sol";

interface IWETH {
    function deposit() external payable;

    function withdraw(uint256) external;

    function balanceOf(address) external view returns (uint256);

    function approve(address, uint256) external returns (bool);
}

contract GenericAdapterTest is BaseOrderTest {
    using AdvancedOrderLib for AdvancedOrder;
    using ConsiderationItemLib for ConsiderationItem;
    using ConsiderationItemLib for ConsiderationItem[];
    using OfferItemLib for OfferItem;
    using OfferItemLib for OfferItem[];
    using OrderParametersLib for OrderParameters;
    using SpentItemLib for SpentItem;
    using SpentItemLib for SpentItem[];

    struct FuzzInputs {
        uint256 one;
        uint256 two;
        uint256 three;
    }

    struct Context {
        GenericAdapterInterface adapter;
        FlashloanOffererInterface flashloanOfferer;
        GenericAdapterSidecarInterface sidecar;
        bool isReference;
        FuzzInputs inputs;
    }

    FuzzInputs emptyInputs;

    GenericAdapterInterface testAdapter;
    GenericAdapterInterface testAdapterReference;
    FlashloanOffererInterface testFlashloanOfferer;
    FlashloanOffererInterface testFlashloanOffererReference;
    GenericAdapterSidecarInterface testSidecar;
    GenericAdapterSidecarInterface testSidecarReference;
    TestERC721 testERC721;
    TestERC1155 testERC1155;
    Context optimizedContext;
    Context referenceContext;
    bool rejectReceive;
    bool erc20CallExecuted;
    bool erc721CallExecuted;
    bool erc1155CallExecuted;
    uint256 nativeAction;
    uint256 wrappedAction;

    WETH internal constant weth =
        WETH(payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));

    receive() external payable override {
        if (rejectReceive) {
            revert("rejectReceive");
        }
    }

    function setUp() public override {
        super.setUp();

        vm.chainId(1);

        testFlashloanOfferer = FlashloanOffererInterface(
            deployCode(
                "out/FlashloanOfferer.sol/FlashloanOfferer.json",
                abi.encode(address(consideration))
            )
        );

        testFlashloanOffererReference = FlashloanOffererInterface(
            deployCode(
                "out/ReferenceFlashloanOfferer.sol/ReferenceFlashloanOfferer.json",
                abi.encode(address(consideration))
            )
        );

        vm.recordLogs();

        testAdapter = GenericAdapterInterface(
            deployCode(
                "out/GenericAdapter.sol/GenericAdapter.json",
                abi.encode(
                    address(consideration), address(testFlashloanOfferer)
                )
            )
        );
        testAdapterReference = GenericAdapterInterface(
            deployCode(
                "out/ReferenceGenericAdapter.sol/ReferenceGenericAdapter.json",
                abi.encode(
                    address(consideration),
                    address(testFlashloanOffererReference)
                )
            )
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();

        testSidecar = GenericAdapterSidecarInterface(
            abi.decode(entries[0].data, (address))
        );
        testSidecarReference = GenericAdapterSidecarInterface(
            abi.decode(entries[2].data, (address))
        );

        testERC721 = new TestERC721();
        testERC1155 = new TestERC1155();

        ConsiderationItemLib.empty().withItemType(ItemType.NATIVE).withToken(
            address(0)
        ).withIdentifierOrCriteria(0).withStartAmount(3 ether).withEndAmount(
            3 ether
        ).withRecipient(address(0)).saveDefault("considerationItemNative");

        ConsiderationItemLib.empty().withItemType(ItemType.ERC20).withToken(
            address(weth)
        ).withIdentifierOrCriteria(0).withStartAmount(3 ether).withEndAmount(
            3 ether
        ).withRecipient(address(0)).saveDefault("considerationItemWrapped");

        OfferItemLib.empty().withItemType(ItemType.NATIVE).withToken(address(0))
            .withIdentifierOrCriteria(0).withStartAmount(3 ether).withEndAmount(
            3 ether
        ).saveDefault("offerItemNative");

        OrderParametersLib.empty().withOfferer(address(this)).withOrderType(
            OrderType.FULL_OPEN
        ).withStartTime(block.timestamp).withEndTime(block.timestamp + 100)
            .withConsideration(new ConsiderationItem[](0))
            .withTotalOriginalConsiderationItems(0).saveDefault(
            "baseOrderParameters"
        );

        optimizedContext = Context({
            adapter: testAdapter,
            flashloanOfferer: testFlashloanOfferer,
            sidecar: testSidecar,
            isReference: false,
            inputs: emptyInputs
        });

        referenceContext = Context({
            adapter: testAdapterReference,
            flashloanOfferer: testFlashloanOffererReference,
            sidecar: testSidecarReference,
            isReference: true,
            inputs: emptyInputs
        });
    }

    function test(function(Context memory) external fn, Context memory context)
        internal
    {
        try fn(context) {
            fail(
                "Stateless test function should have reverted with assertion failure status."
            );
        } catch (bytes memory reason) {
            assertPass(reason);
        }
    }

    function testReceive() public {
        test(this.execReceive, optimizedContext);
        test(this.execReceive, referenceContext);
    }

    function execReceive(Context memory context) external stateless {
        (bool success,) = address(context.adapter).call{ value: 1 ether }("");
        require(success);
        assertEq(address(context.adapter).balance, 1 ether);

        testERC1155.mint(address(context.adapter), 1, 1);
        testERC721.mint(address(this), 1);
        testERC721.safeTransferFrom(address(this), address(context.adapter), 1);
    }

    function testSupportsInterface() public {
        test(this.execSupportsInterface, optimizedContext);
        test(this.execSupportsInterface, referenceContext);
    }

    function execSupportsInterface(Context memory context) external stateless {
        assertEq(
            context.adapter.supportsInterface(
                type(ContractOffererInterface).interfaceId
            ),
            true
        );
    }

    function testGetSeaportMetadata() public {
        test(this.execGetSeaportMetadata, optimizedContext);
        test(this.execGetSeaportMetadata, referenceContext);
    }

    function execGetSeaportMetadata(Context memory context)
        external
        stateless
    {
        (string memory name, Schema[] memory schemas) =
            context.adapter.getSeaportMetadata();
        assertEq(name, "GenericAdapter");
        assertEq(schemas.length, 1);
        assertEq(schemas[0].id, 11);
    }

    function testCleanup() public {
        test(this.execCleanup, optimizedContext);
        test(this.execCleanup, referenceContext);
    }

    function execCleanup(Context memory context) external stateless {
        vm.expectRevert(
            abi.encodeWithSelector(
                GenericAdapterInterface.InvalidCaller.selector, address(this)
            )
        );
        context.adapter.cleanup(address(this));

        // This is a no-op, but should not revert.
        vm.prank(address(context.flashloanOfferer));
        context.adapter.cleanup(address(this));

        // Send the adapter some native tokens.
        (bool success,) = address(context.adapter).call{ value: 1 ether }("");
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
        test(this.execGenerateOrderThresholdReverts, optimizedContext);
        test(this.execGenerateOrderThresholdReverts, referenceContext);
    }

    function execGenerateOrderThresholdReverts(Context memory context)
        external
        stateless
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                GenericAdapterInterface.InvalidExtraDataEncoding.selector, 0
            )
        );
        context.adapter.generateOrder(
            address(this), new SpentItem[](0), new SpentItem[](0), ""
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                GenericAdapterInterface.InvalidCaller.selector, address(this)
            )
        );
        context.adapter.generateOrder(
            address(this),
            new SpentItem[](0),
            new SpentItem[](0),
            abi.encodePacked(bytes32(0), bytes32(0))
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                GenericAdapterInterface.UnsupportedExtraDataVersion.selector,
                0xff
            )
        );
        vm.prank(address(consideration));
        context.adapter.generateOrder(
            address(this),
            new SpentItem[](0),
            new SpentItem[](0),
            abi.encodePacked(
                bytes32(
                    0xff00000000000000000000000000000000000000000000000000000000000000
                ),
                bytes32(0)
            )
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                GenericAdapterInterface.InvalidExtraDataEncoding.selector, 0
            )
        );
        vm.prank(address(consideration));
        context.adapter.generateOrder(
            address(this),
            new SpentItem[](0),
            new SpentItem[](0),
            abi.encodePacked(bytes32(0), bytes32(0))
        );

        TestERC20Revert testERC20Revert = new TestERC20Revert();

        uint256 firstWord =
            0x0011111111111111111111111111111111111111111111111111111100000036;
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
            vm.expectRevert(
                abi.encodeWithSelector(
                    GenericAdapterInterface.ApprovalFailed.selector,
                    erc20Address
                )
            );
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

        (bool avoidWarning, bytes memory data) = address(testERC20Revert).call(
            abi.encodeWithSignature("setRevertSpectacularly(bool)", true)
        );
        if (!avoidWarning || data.length != 0) {
            revert("Just trying to make the compiler happy");
        }
        vm.expectRevert(
            abi.encodeWithSelector(
                GenericAdapterInterface.ApprovalFailed.selector, erc20Address
            )
        );

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
            vm.expectRevert(
                abi.encodeWithSelector(
                    GenericAdapterInterface.ApprovalFailed.selector,
                    erc721Address
                )
            );
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

        (avoidWarning, data) = address(testERC721Revert).call(
            abi.encodeWithSignature("setRevertSpectacularly(bool)", true)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                GenericAdapterInterface.ApprovalFailed.selector, erc721Address
            )
        );
        vm.prank(address(consideration));
        context.adapter.generateOrder(
            address(this),
            new SpentItem[](0),
            new SpentItem[](0),
            abi.encodePacked(bytes32(firstWord), bytes32(secondWord))
        );

        uint256 value = 1;

        SpentItem[] memory spentItems = new SpentItem[](1);

        SpentItem memory spentItemNative =
            SpentItem(ItemType.NATIVE, address(0), 0, value);

        spentItems[0] = spentItemNative;

        bytes memory extraData = AdapterHelperLib.createGenericAdapterContext(
            new Approval[](0), new Call[](0)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                GenericAdapterInterface.InsufficientFunds.selector, value, 0
            )
        );
        vm.prank(address(consideration));
        context.adapter.generateOrder(
            address(this), new SpentItem[](0), spentItems, extraData
        );
    }

    function testApprovals() public {
        test(this.execApprovals, optimizedContext);
        test(this.execApprovals, referenceContext);
    }

    function execApprovals(Context memory context) external stateless {
        TestERC20 testERC20 = new TestERC20();

        uint256 firstWord =
            0x0011111111111111111111111111111111111111111111111111111100000036;
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

        assertEq(
            testERC20.allowance(
                address(context.adapter), address(consideration)
            ),
            type(uint256).max
        );

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

        assertTrue(
            testERC721.isApprovedForAll(
                address(context.adapter), address(consideration)
            )
        );
    }

    function testTransfersToSidecarAndExecute() public {
        test(this.execTransfersToSidecarAndExecute, optimizedContext);
        test(this.execTransfersToSidecarAndExecute, referenceContext);
    }

    function execTransfersToSidecarAndExecute(Context memory context)
        external
        stateless
    {
        TestERC20 testERC20 = new TestERC20();
        SpentItem[] memory spentItems = new SpentItem[](3);

        {
            SpentItem memory spentItemERC20 =
                SpentItem(ItemType.ERC20, address(testERC20), 0, 1);
            SpentItem memory spentItemERC721 =
                SpentItem(ItemType.ERC721, address(testERC721), 1, 1);
            SpentItem memory spentItemERC1155 =
                SpentItem(ItemType.ERC1155, address(testERC1155), 1, 1);

            spentItems[0] = spentItemERC20;
            spentItems[1] = spentItemERC721;
            spentItems[2] = spentItemERC1155;
        }

        // Add the ERC20 address to the second word.
        address erc20Address = address(testERC20);
        address erc721Address = address(testERC721);
        address erc1155Address = address(testERC1155);

        // Left for reference of what it looks like to build manually.
        // uint256 firstWord =
        //     0x00111111111111111111111111111111111111111111111111111111000003B6;
        // uint256 secondWord;
        // uint256 thirdWord;
        // uint256 erc20AddressShifted = uint256(uint160(erc20Address)) << 80;
        //
        // assembly {
        //     // Insert the number of approvals into the second word. Becomes
        //     // something like:
        //     //
        // 0x0300e54a55121a47451c5727adbaf9b9fc1643477e2500000000000000000000
        //     secondWord := or(shl(248, 0x03), erc20AddressShifted)
        //     // Insert the approval type for the second item into the second
        // word
        //     // Becomes something like:
        //     //
        // 0x0300e54a55121a47451c5727adbaf9b9fc1643477e2501000000000000000000
        //     secondWord := or(shl(72, 0x01), secondWord)
        //     // Insert the first 9 bytes of the ERC721 address into the second
        //     // word.  Becomes something like:
        //     //
        // 0x0300e54a55121a47451c5727adbaf9b9fc1643477e250194771550282853f6e0
        //     secondWord := or(shr(88, erc721Address), secondWord)

        //     // Insert the remaining 11 bytes of the ERC721 address into the
        // third
        //     // word. Becomes something like:
        //     //
        // 0x124c302f7de1cf50aa45ca000000000000000000000000000000000000000000
        //     thirdWord := shl(168, erc721Address)
        //     // Insert the approval type for the third item into the third
        // word.
        //     // Becomes something like:
        //     //
        // 0x124c302f7de1cf50aa45ca010000000000000000000000000000000000000000
        //     thirdWord := or(shl(160, 0x01), thirdWord)
        //     // Insert the ERC1155 address into the third word. Becomes
        // something
        //     // like:
        //     //
        // 0x124c302f7de1cf50aa45ca018227724c33c1748a42d1c1cd06e21ab8deb6eb0a
        //     thirdWord := or(erc1155Address, thirdWord)
        // }

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
                address(this),
                false,
                0,
                abi.encodeWithSelector(this.toggleERC20Call.selector, true)
            );

            Call memory callERC721 = Call(
                address(this),
                false,
                0,
                abi.encodeWithSelector(this.toggleERC721Call.selector, true)
            );

            Call memory callERC1155 = Call(
                address(this),
                false,
                0,
                abi.encodeWithSelector(this.toggleERC1155Call.selector, true)
            );

            calls[0] = callERC20;
            calls[1] = callERC721;
            calls[2] = callERC1155;
        }

        Approval[] memory approvals = new Approval[](3);
        approvals[0] = Approval(erc20Address, ItemType.ERC20);
        approvals[1] = Approval(erc721Address, ItemType.ERC721);
        approvals[2] = Approval(erc1155Address, ItemType.ERC1155);

        bytes memory extraData =
            AdapterHelperLib.createGenericAdapterContext(approvals, calls);

        assertEq(
            testERC20.balanceOf(address(context.sidecar)),
            0,
            "sidecar should have no ERC20"
        );
        assertEq(testERC721.ownerOf(1), address(this), "this should own ERC721");
        assertEq(
            testERC1155.balanceOf(address(this), 1),
            1,
            "this should own ERC1155"
        );

        assertFalse(erc20CallExecuted, "erc20CallExecuted should be false");
        assertFalse(erc721CallExecuted, "erc721CallExecuted should be false");
        assertFalse(erc1155CallExecuted, "erc1155CallExecuted should be false");

        vm.prank(address(consideration));
        context.adapter.generateOrder(
            address(this), new SpentItem[](0), spentItems, extraData
        );

        assertEq(
            testERC20.balanceOf(address(context.sidecar)),
            1,
            "sidecar should have ERC20"
        );
        assertEq(
            testERC721.ownerOf(1),
            address(context.sidecar),
            "sidecar should own ERC721"
        );
        assertEq(
            testERC1155.balanceOf(address(context.sidecar), 1),
            1,
            "sidecar should own ERC1155"
        );

        assertTrue(erc20CallExecuted, "erc20CallExecuted should be true");
        assertTrue(erc721CallExecuted, "erc721CallExecuted should be true");
        assertTrue(erc1155CallExecuted, "erc1155CallExecuted should be true");
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
        test(this.execNativeCallAndExecute, optimizedContext);
        test(this.execNativeCallAndExecute, referenceContext);
    }

    function execNativeCallAndExecute(Context memory context)
        external
        stateless
    {
        SpentItem[] memory spentItems = new SpentItem[](3);

        {
            SpentItem memory spentItemNativeOne =
                SpentItem(ItemType.NATIVE, address(0), 0, 1 ether);

            spentItems[0] = spentItemNativeOne;
            spentItems[1] = spentItemNativeOne;
            spentItems[2] = spentItemNativeOne;
        }

        Call[] memory calls = new Call[](3);

        {
            Call memory callNative = Call(
                address(this),
                false,
                1 ether,
                abi.encodeWithSelector(
                    this.incrementNativeAction.selector, 1 ether
                )
            );

            calls[0] = callNative;
            calls[1] = callNative;
            calls[2] = callNative;
        }

        bytes memory extraData = AdapterHelperLib.createGenericAdapterContext(
            new Approval[](0), calls
        );

        assertEq(nativeAction, 0, "nativeAction should be 0");

        // For now, just assume that the flashloan offerer and the adapter are
        // sufficiently funded.
        vm.deal(address(context.flashloanOfferer), 4 ether);
        vm.deal(address(context.adapter), 3 ether);

        vm.prank(address(consideration));
        context.adapter.generateOrder(
            address(this), new SpentItem[](0), spentItems, extraData
        );

        assertEq(nativeAction, 3 ether, "nativeAction should be 3 ether");
    }

    function testSeaportWrappedCallAndExecute() public {
        test(this.execSeaportWrappedCallAndExecute, optimizedContext);
        test(this.execSeaportWrappedCallAndExecute, referenceContext);
    }

    function execSeaportWrappedCallAndExecute(Context memory context)
        external
        stateless
    {
        // SET UP THE FLASHLOAN ORDER HERE.

        // To request a flashloan from the flashloan offerer, its
        // generateOrder function needs to be called with a
        // zero length minimumReceived array and a maximumSpent
        // array with a single item, which generateOrder will
        // eventually return as the consideration. The flashloan
        // details go in the extraData field of the order.
        //
        // To do this, this contract needs to call Seaport's
        // fulfillAdvancedOrder (or some other function) with an
        // advanced order that has a zero length offer and a
        // consideration array with a single item, which must have
        // an amount greater than or equal to the flashloan value
        // requested.

        // Create an order.
        AdvancedOrder memory flashloanOrder =
            AdvancedOrderLib.empty().withNumerator(1).withDenominator(1);

        // Create the consideration array.
        ConsiderationItem[] memory considerationArray =
            new ConsiderationItem[](1);
        considerationArray[0] =
            ConsiderationItemLib.fromDefault("considerationItemNative");

        // Create the parameters for the order.
        OrderParameters memory orderParameters;
        {
            orderParameters = OrderParametersLib.fromDefault(
                "baseOrderParameters"
            ).withOfferer(address(context.flashloanOfferer)).withOrderType(
                OrderType.CONTRACT
            ).withOffer(new OfferItem[](0)).withConsideration(
                considerationArray
            ).withTotalOriginalConsiderationItems(1);

            flashloanOrder.withParameters(orderParameters);
        }

        // This is just an example of manually constructing the extraData for a
        // flashloan. In practice, the extraData should be constructed by the
        // helper function.

        // Create the value that will populate the extraData field.
        // When the flashloan offerer receives the call to
        // generateOrder, it will decode the extraData field into
        // instructions for handling the flashloan.

        // The first byte is the SIP encoding (0). The 1s are just
        // placeholders. They're ignored by the flashloan offerer.
        // The 4 bytes of 0s at the end will eventually contain the
        // size of the extraData field.
        uint256 firstWord =
            0x0011111111111111111111111111111111111111111111111111111100000000;
        // Set the cleanup recipient in the first 20 bytes of the
        // second word.
        uint256 secondWord = uint256(uint160(address(this))) << 96;
        // Since this contract [FOR NOW] just wants to turn WETH
        // into ETH, there will only be one chunk of flashloan data.
        // Add a 0x01 byte to the second word to indicate one
        // flashloan.
        secondWord = secondWord | (1 << 88);
        // Add the amount for the flashloan to the second word.
        secondWord = secondWord | 3 ether;

        // Add the shouldCallback flag to the start of the third
        // word.
        uint256 thirdWord = 1 << 248;
        // Add the recipient to the third word.
        thirdWord =
            thirdWord | (uint256(uint160(address(context.adapter))) << 88);

        // Now, the three words that will make up the extradata
        // field are ready. Here's what they look like:
        //
        // 0x0011111111111111111111111111111111111111111111111111111100000000
        // (below, `a` is the cleanup recipient, `c` is the number
        // of flashloans, and `b` is the flashloan amount requested)
        // 0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaccbbbbbbbbbbbbbbbbbbbbbb
        // e.g.
        // 0x886d6d1eb8d415b00052828cd6d5b321f072073d0100000029a2241af62c0000
        // (below, `c` is the shouldCallback flag, `f` is the
        // flashloan recipient, which is this address, and `e` is
        // empty)
        // 0xccffffffffffffffffffffffffffffffffffffffffeeeeeeeeeeeeeeeeeeeeee
        // e.g.
        // 0x01886d6d1eb8d415b00052828cd6d5b321f072073d0000000000000000000000
        //
        // So, at this point, the last 4 bytes of the first word can
        // be replaced with the size of the extraData field.
        // The size of the extraData field is:
        // 1 byte for the SIP encoding
        // 27 bytes for the empty bytes
        // 4 bytes for the context length
        // 20 bytes for the cleanup recipient
        // 1 byte for the number of flashloans
        // 11 bytes for the flashloan amount
        // 1 byte for the shouldCallback flag
        // 20 bytes for the flashloan recipient
        // For a total or 85 bytes.

        // Set the size of the extraData field in the first word.
        firstWord = firstWord | 85;
        // 0x0011111111111111111111111111111111111111111111111111111100000055

        bytes memory extraData = abi.encodePacked(
            bytes32(firstWord), bytes32(secondWord), bytes32(thirdWord)
        );

        {
            // Add it all to the order.
            flashloanOrder.withExtraData(extraData);
        }

        AdvancedOrder[] memory orders = new AdvancedOrder[](3);
        orders[0] = flashloanOrder;

        // SET UP THE GENERIC ADAPTER ORDER HERE.
        // Create an order.
        AdvancedOrder memory order =
            AdvancedOrderLib.empty().withNumerator(1).withDenominator(1);

        considerationArray = new ConsiderationItem[](3);

        {
            ConsiderationItem memory considerationItem = ConsiderationItemLib
                .fromDefault("considerationItemNative").withAmount(1 ether);
            considerationArray[0] = considerationItem;
            considerationArray[1] = considerationItem;
            considerationArray[2] = considerationItem;
        }

        // Create the parameters for the order.
        {
            orderParameters = OrderParametersLib.fromDefault(
                "baseOrderParameters"
            ).withOfferer(address(context.adapter)).withOrderType(
                OrderType.CONTRACT
            ).withOffer(new OfferItem[](0));
            orderParameters =
                orderParameters.withConsideration(considerationArray);
            orderParameters =
                orderParameters.withTotalOriginalConsiderationItems(3);

            order = order.withParameters(orderParameters);
        }

        {
            Call[] memory calls = new Call[](3);
            Call memory callNative = Call(
                address(this),
                false,
                1 ether,
                abi.encodeWithSelector(
                    this.incrementNativeAction.selector, 1 ether
                )
            );

            calls[0] = callNative;
            calls[1] = callNative;
            calls[2] = callNative;

            extraData = AdapterHelperLib.createGenericAdapterContext(
                new Approval[](0), calls
            );
        }

        order = order.withExtraData(extraData);
        orders[1] = order;

        // SET UP THE MIRROR ORDER HERE.
        // This is just a dummy order to make the flashloan offerer's
        // consideration requirement happy.
        {
            order = AdvancedOrderLib.empty().withNumerator(1).withDenominator(1);
            // Create the parameters for the order.
            {
                OfferItem[] memory offerItems = new OfferItem[](1);
                offerItems[0] = OfferItemLib.fromDefault("offerItemNative");

                orderParameters = OrderParametersLib.fromDefault(
                    "baseOrderParameters"
                ).withOffer(offerItems);

                order = order.withParameters(orderParameters);
                orders[2] = order;
            }
        }

        assertEq(nativeAction, 0, "nativeAction should be 0");

        // For now, just assume that the flashloan offerer is well stocked with
        // native tokens.
        vm.deal(address(context.flashloanOfferer), 4 ether);

        Fulfillment[] memory fulfillments = new Fulfillment[](2);
        {
            FulfillmentComponent[] memory offerComponentsFlashloan =
                new FulfillmentComponent[](1);
            FulfillmentComponent[] memory considerationComponentsFlashloan =
                new FulfillmentComponent[](1);
            FulfillmentComponent[] memory offerComponentsMirror =
                new FulfillmentComponent[](1);
            FulfillmentComponent[] memory considerationComponentsMirror =
                new FulfillmentComponent[](1);

            // Flashloan order, native consideration.
            offerComponentsFlashloan[0] = FulfillmentComponent(0, 0);
            // Mirror order, native offer
            considerationComponentsFlashloan[0] = FulfillmentComponent(2, 0);
            // Mirror order, native offer.
            offerComponentsMirror[0] = FulfillmentComponent(2, 0);
            // Mirror order, native consideration.
            considerationComponentsMirror[0] = FulfillmentComponent(0, 0);

            fulfillments[0] = Fulfillment(
                offerComponentsFlashloan, considerationComponentsFlashloan
            );
            fulfillments[1] = Fulfillment(
                offerComponentsMirror, considerationComponentsMirror
            );
        }

        consideration.matchAdvancedOrders{ value: 3 ether }(
            orders, new CriteriaResolver[](0), fulfillments, address(0)
        );

        assertEq(nativeAction, 3 ether, "nativeAction should be 3 ether");
    }

    function testSeaportWrappedWethManipulation() public {
        test(this.execSeaportWrappedWethManipulation, optimizedContext);
        test(this.execSeaportWrappedWethManipulation, referenceContext);
    }

    function execSeaportWrappedWethManipulation(Context memory context)
        external
        stateless
    {
        ConsiderationItem[] memory considerationArray =
            new ConsiderationItem[](1);
        OrderParameters memory orderParameters;
        AdvancedOrder memory order;
        AdvancedOrder[] memory orders = new AdvancedOrder[](3);

        // This tests flashloaning starting with native tokens and then playing
        // with WETH in the Calls.

        order = AdvancedOrderLib.empty().withNumerator(1).withDenominator(1);

        considerationArray[0] =
            ConsiderationItemLib.fromDefault("considerationItemNative");

        {
            orderParameters = OrderParametersLib.fromDefault(
                "baseOrderParameters"
            ).withOfferer(address(context.flashloanOfferer)).withOrderType(
                OrderType.CONTRACT
            ).withOffer(new OfferItem[](0)).withConsideration(
                considerationArray
            ).withTotalOriginalConsiderationItems(1);

            order.withParameters(orderParameters);
        }

        Flashloan memory flashloan = Flashloan(
            3 ether, ItemType.NATIVE, address(0), true, address(context.adapter)
        );
        Flashloan[] memory flashloans = new Flashloan[](1);
        flashloans[0] = flashloan;

        bytes memory extraData =
            AdapterHelperLib.createFlashloanContext(address(this), flashloans);

        // Add it to the order.
        order.withExtraData(extraData);
        orders[0] = order;

        order = AdvancedOrderLib.empty().withNumerator(1).withDenominator(1);

        considerationArray[0] =
            ConsiderationItemLib.fromDefault("considerationItemNative");

        {
            orderParameters = OrderParametersLib.fromDefault(
                "baseOrderParameters"
            ).withOfferer(address(context.adapter));
            orderParameters = orderParameters.withOrderType(OrderType.CONTRACT);
            orderParameters = orderParameters.withOffer(new OfferItem[](0))
                .withConsideration(considerationArray)
                .withTotalOriginalConsiderationItems(1);

            order = order.withParameters(orderParameters);
        }

        {
            Call[] memory calls = new Call[](6);

            Call memory callDepositWETH = Call(
                address(weth),
                false,
                1 ether,
                abi.encodeWithSelector(IWETH.deposit.selector)
            );

            Call memory callWrappedAction = Call(
                address(this),
                false,
                0,
                abi.encodeWithSelector(
                    this.incrementWrappedAction.selector, 1 ether
                )
            );

            Call memory callNativeAction = Call(
                address(this),
                false,
                1 ether,
                abi.encodeWithSelector(
                    this.incrementNativeAction.selector, 1 ether
                )
            );

            Call memory callWithdrawWETH = Call(
                address(weth),
                false,
                0,
                abi.encodeWithSelector(IWETH.withdraw.selector, 1 ether)
            );

            calls[0] = callDepositWETH;
            calls[1] = callWrappedAction;
            calls[2] = callNativeAction;
            calls[3] = callNativeAction;
            calls[4] = callWithdrawWETH;
            calls[5] = callNativeAction;

            extraData = AdapterHelperLib.createGenericAdapterContext(
                new Approval[](0), calls
            );
        }

        order = order.withExtraData(extraData);
        orders[1] = order;

        {
            AdvancedOrder memory mirrorOrder =
                AdvancedOrderLib.empty().withNumerator(1).withDenominator(1);

            OfferItem[] memory offerItems = new OfferItem[](1);
            offerItems[0] = OfferItemLib.fromDefault("offerItemNative");

            orderParameters = OrderParametersLib.empty().withOfferer(
                address(this)
            ).withOrderType(OrderType.FULL_OPEN).withStartTime(block.timestamp)
                .withEndTime(block.timestamp + 100).withOffer(offerItems)
                .withConsideration(new ConsiderationItem[](0))
                .withTotalOriginalConsiderationItems(0);

            mirrorOrder = mirrorOrder.withParameters(orderParameters);
            orders[2] = mirrorOrder;
        }

        assertEq(nativeAction, 0, "nativeAction should be 0");
        vm.deal(address(context.flashloanOfferer), 4 ether);

        Fulfillment[] memory fulfillments = new Fulfillment[](2);
        {
            FulfillmentComponent[] memory offerComponentsFlashloan =
                new FulfillmentComponent[](1);
            FulfillmentComponent[] memory considerationComponentsFlashloan =
                new FulfillmentComponent[](1);
            FulfillmentComponent[] memory offerComponentsMirror =
                new FulfillmentComponent[](1);
            FulfillmentComponent[] memory considerationComponentsMirror =
                new FulfillmentComponent[](1);

            offerComponentsFlashloan[0] = FulfillmentComponent(0, 0);
            considerationComponentsFlashloan[0] = FulfillmentComponent(2, 0);
            offerComponentsMirror[0] = FulfillmentComponent(2, 0);
            considerationComponentsMirror[0] = FulfillmentComponent(0, 0);

            fulfillments[0] = Fulfillment(
                offerComponentsFlashloan, considerationComponentsFlashloan
            );
            fulfillments[1] = Fulfillment(
                offerComponentsMirror, considerationComponentsMirror
            );
        }

        uint256 thisBalanceBefore = address(this).balance;

        consideration.matchAdvancedOrders{ value: 3 ether }(
            orders, new CriteriaResolver[](0), fulfillments, address(0)
        );

        uint256 thisBalanceAfter = address(this).balance;

        assertEq(nativeAction, 3 ether, "nativeAction should be 3 ether");

        // This tests flashloaning starting with wrapped tokens and then playing
        // with WETH in the Calls.

        StdCheats.deal(address(weth), address(this), 4 ether);
        weth.approve(address(consideration), 4 ether);

        order = AdvancedOrderLib.empty().withNumerator(1).withDenominator(1);

        considerationArray[0] =
            ConsiderationItemLib.fromDefault("considerationItemWrapped");

        {
            orderParameters = OrderParametersLib.fromDefault(
                "baseOrderParameters"
            ).withOfferer(address(context.flashloanOfferer));
            orderParameters = orderParameters.withOrderType(OrderType.CONTRACT);
            orderParameters = orderParameters.withOffer(new OfferItem[](0));
            orderParameters =
                orderParameters.withConsideration(considerationArray);
            orderParameters =
                orderParameters.withTotalOriginalConsiderationItems(1);

            order.withParameters(orderParameters);
        }

        flashloan = Flashloan(
            3 ether,
            ItemType.ERC20,
            address(weth),
            true,
            address(context.adapter)
        );
        flashloans = new Flashloan[](1);
        flashloans[0] = flashloan;

        extraData =
            AdapterHelperLib.createFlashloanContext(address(this), flashloans);

        // Add it all to the order.
        order.withExtraData(extraData);
        orders[0] = order;

        order = AdvancedOrderLib.empty().withNumerator(1).withDenominator(1);

        considerationArray[0] =
            ConsiderationItemLib.fromDefault("considerationItemWrapped");

        {
            orderParameters = OrderParametersLib.fromDefault(
                "baseOrderParameters"
            ).withOfferer(address(context.adapter)).withOrderType(
                OrderType.CONTRACT
            );
            orderParameters = orderParameters.withOffer(new OfferItem[](0))
                .withConsideration(considerationArray)
                .withTotalOriginalConsiderationItems(1);

            order = order.withParameters(orderParameters);
        }

        // The second order is the same as in the call above. Skipped here.

        {
            order = AdvancedOrderLib.empty().withNumerator(1).withDenominator(1);

            OfferItem[] memory offerItems = new OfferItem[](1);
            OfferItem memory offerItem =
                OfferItemLib.fromDefault("offerItemNative");
            offerItem = offerItem.withItemType(ItemType.ERC20);
            offerItem = offerItem.withToken(address(weth));
            offerItems[0] = offerItem;

            orderParameters = OrderParametersLib.empty().withOfferer(
                address(this)
            ).withOrderType(OrderType.FULL_OPEN).withStartTime(block.timestamp)
                .withEndTime(block.timestamp + 100).withOffer(offerItems)
                .withConsideration(new ConsiderationItem[](0))
                .withTotalOriginalConsiderationItems(0);

            order = order.withParameters(orderParameters);
            orders[2] = order;
        }

        thisBalanceBefore = address(this).balance;

        consideration.matchAdvancedOrders(
            orders, new CriteriaResolver[](0), fulfillments, address(0)
        );

        thisBalanceAfter = address(this).balance;

        assertEq(
            thisBalanceAfter - thisBalanceBefore,
            3 ether,
            "this should gain 3 ether"
        );

        assertEq(nativeAction, 6 ether, "total nativeAction should be 6 ether");
    }

    function incrementNativeAction(uint256 amount) external payable {
        assertGt(
            msg.value,
            amount - 0.001 ether,
            "msg.value should be roughly equal to amount"
        );
        assertLt(
            msg.value,
            amount + 0.001 ether,
            "msg.value should be roughly equal to amount"
        );
        nativeAction += msg.value;
    }

    function incrementWrappedAction(uint256 amount) external {
        assertEq(weth.balanceOf(msg.sender), amount);
        wrappedAction += amount;
    }
}
