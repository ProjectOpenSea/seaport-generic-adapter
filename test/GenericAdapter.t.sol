// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ContractOffererInterface} from "seaport-types/interfaces/ContractOffererInterface.sol";

import {GenericAdapterInterface} from "../src/interfaces/GenericAdapterInterface.sol";

import {FlashloanOffererInterface} from "../src/interfaces/FlashloanOffererInterface.sol";

import {GenericAdapter} from "../src/optimized/GenericAdapter.sol";

import {ReferenceGenericAdapter} from "../src/reference/ReferenceGenericAdapter.sol";

import {TestERC20Revert} from "../src/contracts/test/TestERC20Revert.sol";

import {TestERC721} from "../src/contracts/test/TestERC721.sol";

import {TestERC1155} from "../src/contracts/test/TestERC1155.sol";

import {BaseOrderTest} from "./utils/BaseOrderTest.sol";

import {ReceivedItem, Schema, SpentItem} from "seaport-types/lib/ConsiderationStructs.sol";

contract GenericAdapterTest is BaseOrderTest {
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

    function testGenerateOrderReverts() public {
        test(
            this.execGenerateOrderReverts,
            Context({adapter: testAdapter, flashloanOfferer: testFlashloanOfferer, isReference: false})
        );
        test(
            this.execGenerateOrderReverts,
            Context({adapter: testAdapterReference, flashloanOfferer: testFlashloanOffererReference, isReference: true})
        );
    }

    function execGenerateOrderReverts(Context memory context) external stateless {
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
                bytes32(0x0011111111111111111111111111111111111111111111111111111100000036),
                // First byte is the number of approvals, second is approval
                // type, next 20 are addy.
                bytes32(secondWord)
            )
        );

        // TODO: Figure out why the optimized version isn't falling back on its
        // own revert when the token's revert is enormous.
        // address(testERC20Revert).call(abi.encodeWithSignature("setRevertSpectacularly(bool)", true));
        // vm.expectRevert(abi.encodeWithSelector(GenericAdapterInterface.ApprovalFailed.selector, erc20Address));

        // vm.prank(address(consideration));
        // context.adapter.generateOrder(
        //     address(this),
        //     new SpentItem[](0),
        //     new SpentItem[](0),
        //     abi.encodePacked(
        //         // First byte is encoding. Last 4 are context length. 1s are
        //         // just disregarded, it seems.
        //         bytes32(0x0011111111111111111111111111111111111111111111111111111100000036),
        //         // First byte is the number of approvals, second is approval
        //         // type, next 20 are addy.
        //         bytes32(secondWord)
        //     )
        // );
    }
}
