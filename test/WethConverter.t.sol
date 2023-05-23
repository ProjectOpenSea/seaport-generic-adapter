// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ContractOffererInterface} from "seaport-types/interfaces/ContractOffererInterface.sol";

import {WethConverter} from "../src/optimized/WethConverter.sol";

import {TestERC721} from "../src/contracts/test/TestERC721.sol";

import {TestERC1155} from "../src/contracts/test/TestERC1155.sol";

import {BaseOrderTest} from "./utils/BaseOrderTest.sol";

import {ReceivedItem, Schema, SpentItem} from "seaport-types/lib/ConsiderationStructs.sol";

contract WethConverterTest is BaseOrderTest {
    struct Context {
        WethConverterInterface wethConverter;
        bool isReference;
    }

    address immutable WETH_CONTRACT_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    WethConverterInterface wethConverter;
    TestERC721 testERC721;
    TestERC1155 testERC1155;

    function setUp() public override {
        super.setUp();

        wethConverter = WethConverterInterface(
            deployCode("out/WethConverter.sol/WethConverter.json", abi.encode(address(consideration), WETH_CONTRACT_ADDRESS))
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

        // TODO: look into why the optimized version reverts tersely and whether
        // it's expected.
        // vm.prank(address(context.flashloanOfferer));
        // context.adapter.cleanup(address(this));
    }
}
