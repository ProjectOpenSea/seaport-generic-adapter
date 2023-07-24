// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { WETH } from "solady/src/tokens/WETH.sol";

import { AdvancedOrderLib } from "seaport-sol/lib/AdvancedOrderLib.sol";

import { ConsiderationItemLib } from "seaport-sol/lib/ConsiderationItemLib.sol";

import { OrderParametersLib } from "seaport-sol/lib/OrderParametersLib.sol";

import {
    AdvancedOrder,
    ConsiderationItem,
    CriteriaResolver,
    OfferItem,
    OrderParameters
} from "seaport-types/lib/ConsiderationStructs.sol";

import { ContractOffererInterface } from
    "seaport-types/interfaces/ContractOffererInterface.sol";

import { ItemType, OrderType } from "seaport-types/lib/ConsiderationEnums.sol";

import { FlashloanOffererInterface } from
    "../src/interfaces/FlashloanOffererInterface.sol";

import { TestERC721 } from "../src/contracts/test/TestERC721.sol";

import { TestERC1155 } from "../src/contracts/test/TestERC1155.sol";

import { BaseOrderTest } from "./utils/BaseOrderTest.sol";

import { Schema, SpentItem } from "seaport-types/lib/ConsiderationStructs.sol";

import { AdapterHelperLib, Flashloan } from "../src/lib/AdapterHelperLib.sol";

contract FlashloanOffererTest is BaseOrderTest {
    using AdvancedOrderLib for AdvancedOrder;
    using ConsiderationItemLib for ConsiderationItem;
    using OrderParametersLib for OrderParameters;

    struct Context {
        FlashloanOffererInterface flashloanOfferer;
        bool isReference;
    }

    FlashloanOffererInterface testFlashloanOfferer;
    FlashloanOffererInterface testFlashloanOffererReference;
    TestERC721 testERC721;
    TestERC1155 testERC1155;

    WETH internal constant weth =
        WETH(payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));

    uint256 public flashloanValueReceived;

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

        testERC721 = new TestERC721();
        testERC1155 = new TestERC1155();
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

    function testFlashloanOffererReceive() public {
        test(
            this.execReceive,
            Context({
                flashloanOfferer: testFlashloanOfferer,
                isReference: false
            })
        );
        test(
            this.execReceive,
            Context({
                flashloanOfferer: testFlashloanOffererReference,
                isReference: true
            })
        );
    }

    function execReceive(Context memory context) external stateless {
        (bool success,) =
            address(context.flashloanOfferer).call{ value: 1 ether }("");
        require(success);
        assertEq(address(context.flashloanOfferer).balance, 1 ether);

        testERC1155.mint(address(context.flashloanOfferer), 1, 1);
        testERC721.mint(address(this), 2);
        testERC721.safeTransferFrom(
            address(this), address(context.flashloanOfferer), 2
        );
    }

    function testSupportsInterface() public {
        test(
            this.execSupportsInterface,
            Context({
                flashloanOfferer: testFlashloanOfferer,
                isReference: false
            })
        );
        test(
            this.execSupportsInterface,
            Context({
                flashloanOfferer: testFlashloanOffererReference,
                isReference: true
            })
        );
    }

    function execSupportsInterface(Context memory context) external stateless {
        assertEq(
            context.flashloanOfferer.supportsInterface(
                type(ContractOffererInterface).interfaceId
            ),
            true
        );
    }

    function testGetSeaportMetadata() public {
        test(
            this.execGetSeaportMetadata,
            Context({
                flashloanOfferer: testFlashloanOfferer,
                isReference: false
            })
        );
        test(
            this.execGetSeaportMetadata,
            Context({
                flashloanOfferer: testFlashloanOffererReference,
                isReference: true
            })
        );
    }

    function execGetSeaportMetadata(Context memory context)
        external
        stateless
    {
        (string memory name, Schema[] memory schemas) =
            context.flashloanOfferer.getSeaportMetadata();
        assertEq(name, "FlashloanOfferer");
        assertEq(schemas.length, 1);
        assertEq(schemas[0].id, 12);
    }

    function testGenerateOrderThresholdReverts() public {
        test(
            this.execGenerateOrderThresholdReverts,
            Context({
                flashloanOfferer: testFlashloanOfferer,
                isReference: false
            })
        );
        test(
            this.execGenerateOrderThresholdReverts,
            Context({
                flashloanOfferer: testFlashloanOffererReference,
                isReference: true
            })
        );
    }

    function execGenerateOrderThresholdReverts(Context memory context)
        external
        stateless
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                FlashloanOffererInterface.InvalidTotalMaximumSpentItems.selector
            )
        );
        context.flashloanOfferer.generateOrder(
            address(this), new SpentItem[](0), new SpentItem[](0), ""
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                FlashloanOffererInterface.InvalidTotalMaximumSpentItems.selector
            )
        );
        context.flashloanOfferer.generateOrder(
            address(this), new SpentItem[](0), new SpentItem[](2), ""
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                FlashloanOffererInterface
                    .InvalidTotalMinimumReceivedItems
                    .selector
            )
        );
        context.flashloanOfferer.generateOrder(
            address(this), new SpentItem[](2), new SpentItem[](1), ""
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                FlashloanOffererInterface.InvalidCaller.selector, address(this)
            )
        );
        context.flashloanOfferer.generateOrder(
            address(this),
            new SpentItem[](0),
            new SpentItem[](1),
            abi.encodePacked(
                bytes32(
                    0x0011111111111111111111111111111111111111111111111111111100000036
                )
            )
        );

        vm.prank(address(consideration));
        vm.expectRevert(
            abi.encodeWithSelector(
                FlashloanOffererInterface.UnsupportedExtraDataVersion.selector,
                255
            )
        );
        context.flashloanOfferer.generateOrder(
            address(this),
            new SpentItem[](0),
            new SpentItem[](1),
            abi.encodePacked(
                bytes32(
                    0xff11111111111111111111111111111111111111111111111111111100000001
                ),
                bytes32(
                    0x2222222222222222222222222222222222222222330000000000000000000000
                )
            )
        );

        // Triggered by contextLength == 0.
        vm.prank(address(consideration));
        vm.expectRevert(
            abi.encodeWithSelector(
                FlashloanOffererInterface.InvalidExtraDataEncoding.selector, 0
            )
        );
        context.flashloanOfferer.generateOrder(
            address(this),
            new SpentItem[](0),
            new SpentItem[](1),
            abi.encodePacked(
                bytes32(
                    0x0011111111111111111111111111111111111111111111111111111100000000
                ),
                bytes32(
                    0x2222222222222222222222222222222222222222330000000000000000000000
                )
            )
        );

        // Triggered by contextLength < 22 + flashloanDataLength.
        vm.prank(address(consideration));
        vm.expectRevert(
            abi.encodeWithSelector(
                FlashloanOffererInterface.InvalidExtraDataEncoding.selector, 0
            )
        );
        context.flashloanOfferer.generateOrder(
            address(this),
            new SpentItem[](0),
            new SpentItem[](1),
            abi.encodePacked(
                bytes32(
                    0x00111111111111111111111111111111111111111111111111111111000000ff
                ),
                bytes32(
                    0x2222222222222222222222222222222222222222ff0000000000000000000000
                )
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

        spentItemMinReceived = SpentItem(
            ItemType.ERC20, address(context.flashloanOfferer), 0, 1 ether
        );
        spentItemMaxSpent = SpentItem(ItemType.NATIVE, address(0), 0, 2 ether);

        minimumReceived[0] = spentItemMinReceived;
        maximumSpent[0] = spentItemMaxSpent;

        // Make one that sneaks through to confirm that the tests are valid.
        vm.prank(address(consideration));
        context.flashloanOfferer.generateOrder(
            address(this), minimumReceived, maximumSpent, bytes("")
        );

        // Test the InvalidCaller that lies on the process deposit or withdrawal
        // path.
        vm.expectRevert(
            abi.encodeWithSelector(
                FlashloanOffererInterface.InvalidCaller.selector, address(this)
            )
        );
        context.flashloanOfferer.generateOrder(
            address(this), minimumReceived, maximumSpent, bytes("")
        );

        // Test the InvalidExtraDataEncoding that lies on the process deposit or
        // withdrawal path.
        vm.prank(address(consideration));
        vm.expectRevert(
            abi.encodeWithSelector(
                FlashloanOffererInterface.InvalidExtraDataEncoding.selector, 0
            )
        );
        context.flashloanOfferer.generateOrder(
            address(this),
            minimumReceived,
            maximumSpent,
            abi.encodePacked(bytes32(0))
        );

        // Mess up the amount.
        spentItemMinReceived = SpentItem(
            ItemType.ERC20, address(context.flashloanOfferer), 0, 3 ether
        );
        minimumReceived[0] = spentItemMinReceived;

        vm.expectRevert(
            abi.encodeWithSelector(
                FlashloanOffererInterface.MinGreaterThanMax.selector
            )
        );
        vm.prank(address(consideration));
        context.flashloanOfferer.generateOrder(
            address(this), minimumReceived, maximumSpent, bytes("")
        );

        // Put back the amount but mess up the type.
        spentItemMinReceived =
            SpentItem(ItemType.NATIVE, address(0), 0, 1 ether);
        minimumReceived[0] = spentItemMinReceived;

        vm.expectRevert(
            abi.encodeWithSelector(
                FlashloanOffererInterface.SharedItemTypes.selector
            )
        );
        vm.prank(address(consideration));
        context.flashloanOfferer.generateOrder(
            address(this), minimumReceived, maximumSpent, bytes("")
        );

        // Put back the type but mess up the token.
        spentItemMinReceived =
            SpentItem(ItemType.ERC20, address(test20), 0, 1 ether);
        minimumReceived[0] = spentItemMinReceived;

        vm.expectRevert(
            abi.encodeWithSelector(
                FlashloanOffererInterface.UnacceptableTokenPairing.selector
            )
        );
        vm.prank(address(consideration));
        context.flashloanOfferer.generateOrder(
            address(this), minimumReceived, maximumSpent, bytes("")
        );

        // Mess up the token a different way.
        spentItemMinReceived = SpentItem(ItemType.ERC20, address(0), 0, 1 ether);
        minimumReceived[0] = spentItemMinReceived;

        vm.expectRevert(
            abi.encodeWithSelector(
                FlashloanOffererInterface.UnacceptableTokenPairing.selector
            )
        );
        vm.prank(address(consideration));
        context.flashloanOfferer.generateOrder(
            address(this), minimumReceived, maximumSpent, bytes("")
        );

        // Put the token back but jumble up types and addresses.
        spentItemMinReceived = SpentItem(
            ItemType.NATIVE, address(context.flashloanOfferer), 0, 1 ether
        );
        minimumReceived[0] = spentItemMinReceived;
        spentItemMaxSpent = SpentItem(
            ItemType.ERC20, address(context.flashloanOfferer), 0, 2 ether
        );
        maximumSpent[0] = spentItemMaxSpent;

        vm.expectRevert(
            abi.encodeWithSelector(
                FlashloanOffererInterface.MismatchedAddresses.selector
            )
        );
        vm.prank(address(consideration));
        context.flashloanOfferer.generateOrder(
            address(this), minimumReceived, maximumSpent, bytes("")
        );
    }

    function testDepositAndWithdrawFunctionality() public {
        test(
            this.execDepositAndWithdrawFunctionality,
            Context({
                flashloanOfferer: testFlashloanOfferer,
                isReference: false
            })
        );
        test(
            this.execDepositAndWithdrawFunctionality,
            Context({
                flashloanOfferer: testFlashloanOffererReference,
                isReference: true
            })
        );
    }

    function execDepositAndWithdrawFunctionality(Context memory context)
        external
        stateless
    {
        // maximumSpent length must always be one.
        // One minimumReceived item indicates a deposit or withdrawal.
        // If the item has this contract as its token, process as a deposit.

        SpentItem[] memory minimumReceived = new SpentItem[](1);
        SpentItem[] memory maximumSpent = new SpentItem[](1);

        SpentItem memory spentItemMinReceived;
        SpentItem memory spentItemMaxSpent;

        // This says, "I'm depositing 1 ether"
        spentItemMinReceived = SpentItem(
            ItemType.ERC20, address(context.flashloanOfferer), 0, 1 ether
        );
        // This needs to be higher than or equal to the deposit.
        spentItemMaxSpent = SpentItem(ItemType.NATIVE, address(0), 0, 1 ether);

        minimumReceived[0] = spentItemMinReceived;
        maximumSpent[0] = spentItemMaxSpent;

        vm.prank(address(consideration));
        context.flashloanOfferer.generateOrder(
            address(this), minimumReceived, maximumSpent, bytes("")
        );

        assertEq(context.flashloanOfferer.getBalance(address(this)), 1 ether);

        // This says, "I'm withdrawing 1 ether"
        spentItemMinReceived =
            SpentItem(ItemType.NATIVE, address(0), 0, 1 ether);
        // This needs to be higher than or equal to the deposit.
        spentItemMaxSpent = SpentItem(
            ItemType.ERC20, address(context.flashloanOfferer), 0, 1 ether
        );

        minimumReceived[0] = spentItemMinReceived;
        maximumSpent[0] = spentItemMaxSpent;

        vm.prank(address(consideration));
        context.flashloanOfferer.generateOrder(
            address(this), minimumReceived, maximumSpent, bytes("")
        );

        assertEq(context.flashloanOfferer.getBalance(address(this)), 0 ether);
    }

    function testProvideFlashloanFunctionalityNativeConsideration() public {
        test(
            this.execProvideFlashloanFunctionalityNativeConsideration,
            Context({
                flashloanOfferer: testFlashloanOfferer,
                isReference: false
            })
        );
        test(
            this.execProvideFlashloanFunctionalityNativeConsideration,
            Context({
                flashloanOfferer: testFlashloanOffererReference,
                isReference: true
            })
        );
    }

    function execProvideFlashloanFunctionalityNativeConsideration(
        Context memory context
    ) external stateless {
        // [version, 1 byte][ignored 27 bytes][context arg length 4 bytes]
        // [cleanupRecipient, 20 bytes][totalFlashloans, 1 byte]
        // [flashloanData...]
        //
        // 0x00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee11111111
        // aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaccffffffffffffffffffffff...

        // flashloan data goes: [amount, 11 bytes], [shouldcallback, 1 byte],
        // [recipient, 20 bytes]

        uint256 flashloanValueRequested = 0x3333333333333333333333;

        SpentItem[] memory maximumSpent = new SpentItem[](1);
        SpentItem memory spentItemMaxSpent =
            SpentItem(ItemType.NATIVE, address(0), 0, flashloanValueRequested);
        maximumSpent[0] = spentItemMaxSpent;

        Flashloan memory flashloan = Flashloan(
            uint88(flashloanValueRequested),
            ItemType.NATIVE,
            true,
            address(this)
        );
        Flashloan[] memory flashloans = new Flashloan[](1);
        flashloans[0] = flashloan;

        bytes memory extraData =
            AdapterHelperLib.createFlashloanContext(address(this), flashloans);

        // For now, just assume that the flashloan offerer is sufficiently
        // funded.
        vm.deal(address(context.flashloanOfferer), 0x4444444444444444444444444);

        uint256 receipientBalanceBefore = address(this).balance;
        uint256 senderBalanceBefore = address(context.flashloanOfferer).balance;

        vm.prank(address(consideration));
        context.flashloanOfferer.generateOrder(
            address(this), new SpentItem[](0), maximumSpent, extraData
        );

        uint256 receipientBalanceAfter = address(this).balance;
        uint256 senderBalanceAfter = address(context.flashloanOfferer).balance;

        assertEq(
            receipientBalanceAfter,
            receipientBalanceBefore + flashloanValueRequested,
            "recipient balance incorrect"
        );

        assertEq(
            senderBalanceAfter,
            senderBalanceBefore - flashloanValueRequested,
            "sender balance incorrect"
        );

        assertEq(flashloanValueRequested, flashloanValueReceived);
    }

    function testProvideFlashloanFunctionalityWrappedConsideration() public {
        test(
            this.execProvideFlashloanFunctionalityWrappedConsideration,
            Context({
                flashloanOfferer: testFlashloanOfferer,
                isReference: false
            })
        );
        test(
            this.execProvideFlashloanFunctionalityWrappedConsideration,
            Context({
                flashloanOfferer: testFlashloanOffererReference,
                isReference: true
            })
        );
    }

    function execProvideFlashloanFunctionalityWrappedConsideration(
        Context memory context
    ) external stateless {
        // [version, 1 byte][ignored 27 bytes][context arg length 4 bytes]
        // [cleanupRecipient, 20 bytes][totalFlashloans, 1 byte]
        // [flashloanData...]
        //
        // 0x00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee11111111
        // aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaccffffffffffffffffffffff...

        // flashloan data goes: [amount, 11 bytes], [shouldcallback, 1 byte],
        // [recipient, 20 bytes]

        uint256 flashloanValueRequested = 0x3333333333333333333333;

        SpentItem[] memory maximumSpent = new SpentItem[](1);
        SpentItem memory spentItemMaxSpent =
            SpentItem(ItemType.ERC20, address(weth), 0, flashloanValueRequested);
        maximumSpent[0] = spentItemMaxSpent;

        Flashloan memory flashloan = Flashloan(
            uint88(flashloanValueRequested), ItemType.ERC20, true, address(this)
        );
        Flashloan[] memory flashloans = new Flashloan[](1);
        flashloans[0] = flashloan;

        bytes memory extraData =
            AdapterHelperLib.createFlashloanContext(address(this), flashloans);

        // For now, just assume that the flashloan offerer is sufficiently
        // funded.
        vm.deal(address(context.flashloanOfferer), 0x4444444444444444444444444);

        uint256 receipientBalanceBefore = address(this).balance;
        uint256 senderBalanceBefore = address(context.flashloanOfferer).balance;

        vm.prank(address(consideration));
        context.flashloanOfferer.generateOrder(
            address(this), new SpentItem[](0), maximumSpent, extraData
        );

        uint256 receipientBalanceAfter = address(this).balance;
        uint256 senderBalanceAfter = address(context.flashloanOfferer).balance;

        assertEq(
            receipientBalanceAfter,
            receipientBalanceBefore + flashloanValueRequested,
            "recipient balance incorrect"
        );

        assertEq(
            senderBalanceAfter,
            senderBalanceBefore - flashloanValueRequested,
            "sender balance incorrect"
        );

        assertEq(flashloanValueRequested, flashloanValueReceived);
    }

    function testRejectFlashloanFunctionality() public {
        test(
            this.execRejectFlashloanFunctionality,
            Context({
                flashloanOfferer: testFlashloanOfferer,
                isReference: false
            })
        );
        test(
            this.execRejectFlashloanFunctionality,
            Context({
                flashloanOfferer: testFlashloanOffererReference,
                isReference: true
            })
        );
    }

    function execRejectFlashloanFunctionality(Context memory context)
        external
        stateless
    {
        uint256 flashloanValueRequested = 0xffff;

        SpentItem[] memory maximumSpent = new SpentItem[](1);

        // This is an impermissible shitcoin.
        SpentItem memory spentItemMaxSpent = SpentItem(
            ItemType.ERC20, address(test20), 0, flashloanValueRequested
        );
        maximumSpent[0] = spentItemMaxSpent;

        Flashloan memory flashloan = Flashloan(
            uint88(flashloanValueRequested),
            ItemType.NATIVE,
            true,
            address(this)
        );
        Flashloan[] memory flashloans = new Flashloan[](1);
        flashloans[0] = flashloan;

        bytes memory extraData =
            AdapterHelperLib.createFlashloanContext(address(this), flashloans);

        vm.prank(address(consideration));
        vm.expectRevert(
            abi.encodeWithSelector(
                FlashloanOffererInterface.InvalidMaximumSpentItem.selector,
                spentItemMaxSpent
            )
        );
        context.flashloanOfferer.generateOrder(
            address(this), new SpentItem[](0), maximumSpent, extraData
        );

        // This is an impermissible shitcoin.
        spentItemMaxSpent = SpentItem(
            ItemType.ERC1155, address(weth), 0, flashloanValueRequested
        );
        maximumSpent[0] = spentItemMaxSpent;

        flashloan = Flashloan(
            uint88(flashloanValueRequested),
            ItemType.NATIVE,
            true,
            address(this)
        );
        flashloans = new Flashloan[](1);
        flashloans[0] = flashloan;

        extraData =
            AdapterHelperLib.createFlashloanContext(address(this), flashloans);

        vm.prank(address(consideration));
        vm.expectRevert(
            abi.encodeWithSelector(
                FlashloanOffererInterface.InvalidMaximumSpentItem.selector,
                spentItemMaxSpent
            )
        );
        context.flashloanOfferer.generateOrder(
            address(this), new SpentItem[](0), maximumSpent, extraData
        );
    }

    function testSeaportWrappedFlashloanFunctionality() public {
        test(
            this.execSeaportWrappedFlashloanFunctionality,
            Context({
                flashloanOfferer: testFlashloanOfferer,
                isReference: false
            })
        );
        test(
            this.execSeaportWrappedFlashloanFunctionality,
            Context({
                flashloanOfferer: testFlashloanOffererReference,
                isReference: true
            })
        );
    }

    function execSeaportWrappedFlashloanFunctionality(Context memory context)
        external
        stateless
    {
        // Create an order.
        AdvancedOrder memory order;
        {
            order = AdvancedOrderLib.empty().withNumerator(1).withDenominator(1);
        }

        // Create the offer and consideration.
        uint256 flashloanValueRequested = 0x3333333333333333333333;

        ConsiderationItem[] memory considerationArray =
            new ConsiderationItem[](1);
        {
            ConsiderationItem memory considerationItem =
                ConsiderationItemLib.empty();
            considerationItem = considerationItem.withItemType(ItemType.NATIVE);
            considerationItem = considerationItem.withToken(address(0));
            considerationItem = considerationItem.withIdentifierOrCriteria(0);
            considerationItem =
                considerationItem.withStartAmount(flashloanValueRequested);
            considerationItem =
                considerationItem.withEndAmount(flashloanValueRequested);
            considerationItem = considerationItem.withRecipient(address(0));
            considerationArray[0] = considerationItem;
        }

        // Create the parameters for the order.
        OrderParameters memory orderParameters;
        {
            orderParameters = OrderParametersLib.empty();
            orderParameters =
                orderParameters.withOfferer(address(context.flashloanOfferer));
            orderParameters = orderParameters.withOrderType(OrderType.CONTRACT);
            orderParameters = orderParameters.withStartTime(block.timestamp);
            orderParameters = orderParameters.withEndTime(block.timestamp + 100);
            orderParameters = orderParameters.withOffer(new OfferItem[](0));
            orderParameters =
                orderParameters.withConsideration(considerationArray);
            orderParameters =
                orderParameters.withTotalOriginalConsiderationItems(1);
        }

        Flashloan memory flashloan = Flashloan(
            uint88(flashloanValueRequested),
            ItemType.NATIVE,
            true,
            address(this)
        );
        Flashloan[] memory flashloans = new Flashloan[](1);
        flashloans[0] = flashloan;

        bytes memory extraData =
            AdapterHelperLib.createFlashloanContext(address(this), flashloans);

        {
            // Add it all to the order.
            order.withParameters(orderParameters).withExtraData(extraData);
        }

        // For now, just assume that the flashloan offerer is sufficiently
        // funded.
        vm.deal(address(context.flashloanOfferer), 0x4444444444444444444444444);

        // Call Seaport with the order.
        consideration.fulfillAdvancedOrder{ value: flashloanValueRequested }(
            order, new CriteriaResolver[](0), bytes32(0), address(this)
        );

        // Check that the order was executed.
    }

    receive() external payable override {
        flashloanValueReceived += msg.value;
    }

    /**
     * @dev Allow for the flashloan offerer to retrieve native tokens that may
     *      have been left over on this contract, especially in the case where
     *      the request to generate the order fails and the order is skipped. As
     *      the flashloan offerer has already sent native tokens to the adapter
     *      beforehand, those native tokens will otherwise be stuck in the
     *      adapter for the duration of the fulfillment, and therefore at risk
     *      of being taken by another caller in a subsequent fulfillment.
     *
     *      NOTE: This is present to allow for this test contract to go through
     *            the full flashloan lifcycle.  The comment above is left for
     *            reference.
     */
    function cleanup(address /* recipient */ )
        external
        payable
        returns (bytes4)
    {
        return this.cleanup.selector;
    }
}
