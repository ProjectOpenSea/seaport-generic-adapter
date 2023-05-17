// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ContractOffererInterface} from "seaport-types/interfaces/ContractOffererInterface.sol";

import {ItemType} from "seaport-types/lib/ConsiderationEnums.sol";

import {ReceivedItem, Schema, SpentItem} from "seaport-types/lib/ConsiderationStructs.sol";

import "forge-std/console.sol";

/**
 * @title FlashloanOfferer
 * @author 0age
 * @notice FlashloanOfferer is a proof of concept for a flashloan contract
 *         offerer. It will send native tokens to each specified recipient in
 *         the given amount when generating an order, and can optionally trigger
 *         callbacks for those recipients when ratifying the order after it has
 *         executed. It will aggregate all provided native tokens and return a
 *         single maximumSpent item with itself as the recipient for the total
 *         amount of aggregated native tokens.
 */
contract FlashloanOfferer is ContractOffererInterface {
    address private immutable _SEAPORT;

    mapping(address => uint256) public balanceOf;

    error InvalidCaller(address caller);
    error InvalidTotalMaximumSpentItems();
    error InsufficientMaximumSpentAmount();
    error InvalidItems();
    error InvalidTotalMinimumReceivedItems();
    error UnsupportedExtraDataVersion(uint8 version);
    error InvalidExtraDataEncoding(uint8 version);
    error CallFailed(); // 0x3204506f
    error NotImplemented();

    error MinGreaterThanMax(); // 0xc9b4d6ba
    error SharedItemTypes(); // 0xc25bddad
    error UnacceptableTokenPairing(); // 0xdd55e6a8
    error MismatchedAddresses(); // 0x67306d70

    constructor(address seaport) {
        _SEAPORT = seaport;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == type(ContractOffererInterface).interfaceId;
    }

    /**
     * @dev Enable accepting ERC721 tokens via safeTransfer.
     */
    function onERC721Received(address, address, uint256, bytes calldata) external payable returns (bytes4) {
        assembly {
            mstore(0, 0x150b7a02)
            return(0x1c, 0x20)
        }
    }

    /**
     * @dev Enable accepting ERC1155 tokens via safeTransfer.
     */
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external payable returns (bytes4) {
        assembly {
            mstore(0, 0xf23a6e61)
            return(0x1c, 0x20)
        }
    }

    /**
     * @dev Generates an order with the specified minimum and maximum spent
     *      items, and optional context (supplied as extraData).
     *
     * @param fulfiller       The address of the fulfiller.
     * @param minimumReceived The minimum items that the caller must receive. If
     *                        empty, the caller is requisitioning a flashloan. A
     *                        single ERC20 item with this contract as the token
     *                        indicates a native token deposit and must have an
     *                        accompanying native token item as maximumSpent; a
     *                        single native item indicates a withdrawal and must
     *                        have an accompanying ERC20 item with this contract
     *                        as the token, where in both cases the amounts must
     *                        be equal.
     * @param maximumSpent    The maximum items the caller is willing to spend.
     *                        For flashloans, a single native token item must be
     *                        provided with amount not less than the sum of all
     *                        flashloaned amounts.
     * @param context         Additional context of the order when flashloaning:
     *                          - SIP encoding version (1 byte)
     *                          - 27 empty bytes
     *                          - context length (4 bytes)
     *                          - cleanupRecipient: arg for cleanup (20 bytes)
     *                          - totalRecipients: flashloans to send (1 byte)
     *                              - amount (11 bytes * totalRecipients)
     *                              - shouldCallback (1 byte * totalRecipients)
     *                              - recipient (20 bytes * totalRecipients)
     *
     * @return offer         A tuple containing the offer items.
     * @return consideration An array containing a single consideration item,
     *                       with this contract named as the recipient. The item
     *                       type and amount will depend on the type of order.
     */
    function generateOrder(
        address fulfiller,
        SpentItem[] calldata minimumReceived,
        SpentItem[] calldata maximumSpent,
        bytes calldata context // encoded based on the schemaID
    ) external override returns (SpentItem[] memory offer, ReceivedItem[] memory consideration) {
        if (maximumSpent.length != 1) {
            revert InvalidTotalMaximumSpentItems();
        }

        SpentItem calldata maximumSpentItem = maximumSpent[0];

        uint256 maximumSpentAmount;
        assembly {
            maximumSpentAmount := calldataload(add(maximumSpentItem, 0x60))
        }

        if (minimumReceived.length == 0) {
            // No minimumReceived items indicates to perform a flashloan.
            if (_processFlashloan(context) > maximumSpentAmount) {
                revert InsufficientMaximumSpentAmount();
            }
        } else if (minimumReceived.length == 1) {
            // One minimumReceived item indicates a deposit or withdrawal.
            SpentItem calldata minimumReceivedItem = minimumReceived[0];

            assembly {
                // Revert if minimumReceived item amount is greater than
                // maximumSpent, or if any of the following is not true:
                //  - one of the item types is 1 and the other is 0 (so, both item items same, revert)
                //  - one of the tokens is address(this) and the other is null (so, both same, revert or neither is this, revert) IS THIS REDUNDANT?
                //  - item type 1 has address(this) token and 0 is null token

                // TODO: look at how expensive it would be to swap these in for readbility.
                // let minimumReceivedItemType := and(calldataload(minimumReceivedItem), 0xff)
                // let maximumSpentItemType := and(calldataload(maximumSpentItem), 0xff)
                // let minimumReceivedToken := calldataload(add(minimumReceivedItem, 0x20))
                // let maximumSpentToken := calldataload(add(maximumSpentItem, 0x20))
                // let minimumReceivedAmount := calldataload(add(minimumReceivedItem, 0x60))

                // Ensure that minimumReceived item amount is less than or equal
                // to maximumSpent.
                let testErrorBuffer := gt(calldataload(add(minimumReceivedItem, 0x60)), maximumSpentAmount)

                // Ensure that the items don't share a type.
                testErrorBuffer :=
                    or(
                        testErrorBuffer,
                        shl(
                            1,
                            // returns 1 if both native or both ERC20. 0 otherwise.
                            iszero(
                                // returns 1 if one of each. 0 otherwise.
                                eq(
                                    // returns 0 if both native. 1 if one of
                                    // each. 2 if both ERC20.
                                    add(
                                        and(calldataload(minimumReceivedItem), 0xff),
                                        and(calldataload(maximumSpentItem), 0xff)
                                    ),
                                    0x01
                                )
                            )
                        )
                    )

                // Ensure that at one of the tokens is and ERC20 with
                // address(this).
                testErrorBuffer :=
                    or(
                        testErrorBuffer,
                        shl(
                            2,
                            // 1 if the ERC20 address is not this contract.
                            iszero(
                                // 1 if the ERC20 address is this contract.
                                eq(
                                    // Since it has to be a zero and a 1 for item types, this just
                                    // returns the non-null address token.
                                    add(
                                        // Token value if ERC20, 0 otherwise.
                                        mul(calldataload(minimumReceivedItem), calldataload(add(minimumReceivedItem, 0x20))),
                                        // Token value if ERC20, 0 otherwise.
                                        mul(calldataload(maximumSpentItem), calldataload(add(maximumSpentItem, 0x20)))
                                    ),
                                    address()
                                )
                            )
                        )
                    )

                // Ensure that exactly one of the items uses address(this).
                testErrorBuffer :=
                    or(
                        testErrorBuffer,
                        shl(
                            3,
                            iszero(
                                // 1 if one is native and the other is this address.
                                and(
                                    // 1 if either is native.
                                    iszero(
                                        // 0 if either is native.
                                        mul(
                                            calldataload(add(minimumReceivedItem, 0x20)),
                                            calldataload(add(maximumSpentItem, 0x20))
                                        )
                                    ),
                                    // 1 if the lone non-null address is this contract.
                                    iszero(
                                        // Returns either this address or 0.
                                        // Is only zero if the address from the `add` is
                                        // this address.
                                        xor(
                                            // Just returns the non-null address token.
                                            add(
                                                calldataload(add(minimumReceivedItem, 0x20)),
                                                calldataload(add(maximumSpentItem, 0x20))
                                            ),
                                            address()
                                        )
                                    )
                                )
                            )
                        )
                    )

                if testErrorBuffer {
                    if shl(255, testErrorBuffer) {
                        mstore(0, 0xc9b4d6ba)
                        revert(0x1c, 0x04)
                    }

                    if shl(254, testErrorBuffer) {
                        mstore(0, 0xc25bddad)
                        revert(0x1c, 0x04)
                    }

                    if shl(253, testErrorBuffer) {
                        mstore(0, 0xdd55e6a8)
                        revert(0x1c, 0x04)
                    }

                    if shl(252, testErrorBuffer) {
                        mstore(0, 0x67306d70)
                        revert(0x1c, 0x04)
                    }
                }
            }

            _processDepositOrWithdrawal(fulfiller, minimumReceivedItem, context);
        } else {
            revert InvalidTotalMinimumReceivedItems();
        }

        consideration = new ReceivedItem[](1);
        consideration[0] = _copySpentAsReceivedToSelf(maximumSpentItem);

        return (minimumReceived, consideration);
    }

    /**
     * @dev Enable accepting native tokens.
     */
    receive() external payable {}

    /**
     * @dev Ratifies an order with the specified offer, consideration, and
     *      optional context (supplied as extraData).
     *
     * @custom:param offer         The offer items.
     * @custom:param consideration The consideration items.
     * @custom:param context       Additional context of the order.
     * @custom:param orderHashes   The hashes to ratify.
     * @custom:param contractNonce The nonce of the contract.
     *
     * @return ratifyOrderMagicValue The magic value returned by the contract
     *                               offerer.
     */
    function ratifyOrder(
        SpentItem[] calldata, /* offer */
        ReceivedItem[] calldata, /* consideration */
        bytes calldata context, // encoded based on the schemaID
        bytes32[] calldata, /* orderHashes */
        uint256 /* contractNonce */
    ) external override returns (bytes4) {
        if (msg.sender != _SEAPORT) {
            revert InvalidCaller(msg.sender);
        }

        // If there is any context, trigger designated callbacks & provide data.
        assembly {
            // If context is present, look for flashloans with callback flags.
            if and(calldataload(context.offset), 0xfffffff) {
                let cleanupRecipient := calldataload(add(context.offset, 1))
                let flashloanDataStarts := add(context.offset, 21)
                let flashloanDataEnds :=
                    add(flashloanDataStarts, shl(0x05, and(0xff, calldataload(add(context.offset, 20)))))

                mstore(0, 0xfbacefce) // cleanup(address) selector
                mstore(0x20, cleanupRecipient)

                // Iterate over each flashloan.
                for { let flashloanDataOffset := flashloanDataStarts } lt(flashloanDataOffset, flashloanDataEnds) {
                    flashloanDataOffset := add(flashloanDataOffset, 0x20)
                } {
                    // Note: confirm that this is the correct usage of byte opcode
                    let flashloanData := calldataload(flashloanDataOffset)
                    // let shouldCall := byte(12, flashloanData)
                    let recipient := and(0xffffffffffffffffffffffffffffffffffffffff, flashloanData)
                    let value := shr(168, flashloanData)

                    // Fire off call to recipient. Revert & bubble up revert
                    // data if present & reasonably-sized, else revert with a
                    // custom error. Note that checking for sufficient native
                    // token balance is an option here if more specific custom
                    // reverts are preferred.
                    let success := call(gas(), recipient, value, 0x1c, 0x24, 0, 4)

                    if or(
                        iszero(success),
                        // cleanup(address) selector
                        xor(mload(0), 0xfbacefce000000000000000000000000000000000000000000000000fbacefce)
                    ) {
                        if and(and(iszero(success), iszero(iszero(returndatasize()))), lt(returndatasize(), 0xffff)) {
                            returndatacopy(0, 0, returndatasize())
                            revert(0, returndatasize())
                        }

                        // CallFailed()
                        mstore(0, 0x3204506f)
                        revert(0x1c, 0x04)
                    }
                }
            }

            // return RatifyOrderMagicValue
            mstore(0, 0xf4dd92ce)
            return(0x1c, 0x04)
        }
    }

    /**
     * @dev View function to preview an order generated in response to a minimum
     *      set of received items, maximum set of spent items, and context
     *      (supplied as extraData).
     *
     * @custom:param caller      The address of the caller (e.g. Seaport).
     * @custom:param fulfiller    The address of the fulfiller (e.g. the account
     *                           calling Seaport).
     * @custom:param minReceived The minimum items that the caller is willing to
     *                           receive.
     * @custom:param maxSpent    The maximum items caller is willing to spend.
     * @custom:param context     Additional context of the order.
     *
     * @return offer         A tuple containing the offer items.
     * @return consideration A tuple containing the consideration items.
     */
    function previewOrder(address, address, SpentItem[] calldata, SpentItem[] calldata, bytes calldata)
        external
        pure
        override
        returns (SpentItem[] memory, ReceivedItem[] memory)
    {
        revert NotImplemented();
    }

    /**
     * @dev Gets the metadata for this contract offerer.
     *
     * @return name    The name of the contract offerer.
     * @return schemas The schemas supported by the contract offerer.
     */
    function getSeaportMetadata()
        external
        pure
        override
        returns (
            string memory name,
            Schema[] memory schemas // map to Seaport Improvement Proposal IDs
        )
    {
        schemas = new Schema[](0);
        return ("FlashloanOfferer", schemas);
    }

    function _processFlashloan(bytes calldata context) internal returns (uint256 totalSpent) {
        // Get the length of the context array from calldata (masked).
        uint256 contextLength;
        assembly {
            contextLength := and(calldataload(context.offset), 0xfffffff)
        }

        // console.log('contextLength', contextLength);
        // console.log('context.length', context.length);

        if (contextLength == 0 || context.length == 0) {
            revert InvalidExtraDataEncoding(uint8(context[0]));
        }

        // The expected structure of the context is:
        // [version, 1 byte][ignored 27 bytes][context arg length 4 bytes]
        // [cleanupRecipient, 20 bytes][totalFlashloans, 1 byte][flashloanData...]
        //
        // 0x00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee11111111
        // aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaccffffffffffffffffffffff...

        uint256 flashloanDataSize;
        {
            // Declare an error buffer; first check is that caller is Seaport.
            // If the caller is not Seaport, revert with an InvalidCaller error.
            uint256 errorBuffer = _cast(msg.sender != _SEAPORT);
            // console.log('OPTIMIZED ==========================================');
            // console.log('errorBuffer', errorBuffer);

            // Next, check for sip-6 version byte. If the version byte is not
            // 0, revert with an UnsupportedExtraDataVersion error.
            errorBuffer |= errorBuffer ^ (_cast(context[0] != 0x00) << 1);

            // console.log('errorBuffer', errorBuffer);

            uint256 totalFlashloans;

            // Retrieve the number of flashloans.
            assembly {
                totalFlashloans := and(0xff, calldataload(add(context.offset, 21)))

                // Include one word of flashloan data for each flashloan.
                flashloanDataSize := shl(0x05, totalFlashloans)
            }

            // console.log('contextLength', contextLength);
            // console.log('TOTAL FLASHLOANS', totalFlashloans);
            // console.log('flashloanDataSize', flashloanDataSize);

            // Next, check for sufficient context length. If the context length
            // is less than 22 + flashloanDataSize, revert with an
            // InvalidExtraDataEncoding error.
            unchecked {
                errorBuffer |= errorBuffer ^ (_cast(contextLength < 22 + flashloanDataSize) << 2);
            }
            // console.log('errorBuffer', errorBuffer);

            // Handle decoding errors.
            if (errorBuffer != 0) {
                uint8 version = uint8(context[0]);

                if (errorBuffer << 255 != 0) {
                    revert InvalidCaller(msg.sender);
                } else if (errorBuffer << 254 != 0) {
                    revert UnsupportedExtraDataVersion(version);
                } else if (errorBuffer << 253 != 0) {
                    revert InvalidExtraDataEncoding(version);
                }
            }
        }

        uint256 totalValue;

        assembly {
            let flashloanDataStarts := add(context.offset, 21)
            let flashloanDataEnds := add(flashloanDataStarts, flashloanDataSize)
            // Iterate over each flashloan.
            for { let flashloanDataOffset := flashloanDataStarts } lt(flashloanDataOffset, flashloanDataEnds) {
                flashloanDataOffset := add(flashloanDataOffset, 0x20)
            } {
                let value := shr(168, calldataload(flashloanDataOffset))
                let recipient := and(0xffffffffffffffffffffffffffffffffffffffff, calldataload(flashloanDataOffset))

                totalValue := add(totalValue, value)

                // Fire off call to recipient. Revert & bubble up revert data if
                // present & reasonably-sized, else revert with a custom error.
                // Note that checking for sufficient native token balance is an
                // option here if more specific custom reverts are preferred.
                if iszero(call(gas(), recipient, value, 0, 0, 0, 0)) {
                    if and(iszero(iszero(returndatasize())), lt(returndatasize(), 0xffff)) {
                        returndatacopy(0, 0, returndatasize())
                        revert(0, returndatasize())
                    }

                    // CallFailed()
                    mstore(0, 0x3204506f)
                    revert(0x1c, 0x04)
                }
            }
        }

        return totalValue;
    }

    function _processDepositOrWithdrawal(address fulfiller, SpentItem calldata spentItem, bytes calldata context)
        internal
    {
        {
            // Get the length of the context array from calldata (unmasked).
            uint256 contextLength;
            assembly {
                contextLength := calldataload(context.offset)
            }

            // Declare an error buffer; first check is that caller is Seaport.
            uint256 errorBuffer = _cast(msg.sender != _SEAPORT);

            // Next, check that context is empty.
            errorBuffer |= errorBuffer ^ (_cast(contextLength != 0 || context.length != 0) << 1);

            // Handle decoding errors.
            if (errorBuffer != 0) {
                if (errorBuffer << 255 != 0) {
                    revert InvalidCaller(msg.sender);
                } else if (errorBuffer << 254 != 0) {
                    revert InvalidExtraDataEncoding(0);
                }
            }

            // if the item has this contract as its token, process as a deposit.
            if (spentItem.token == address(this)) {
                balanceOf[fulfiller] += spentItem.amount;
            } else {
                // otherwise it is a withdrawal.
                balanceOf[fulfiller] -= spentItem.amount;
            }
        }
    }

    /**
     * @dev Internal pure function to cast a `bool` value to a `uint256` value.
     *
     * @param b The `bool` value to cast.
     *
     * @return u The `uint256` value.
     */
    function _cast(bool b) internal pure returns (uint256 u) {
        assembly {
            u := b
        }
    }

    /**
     * @dev Copies a spent item from calldata and converts into a received item,
     *      applying address(this) as the recipient. Note that this currently
     *      clobbers the word directly after the spent item in memory.
     *
     * @param spentItem The spent item.
     *
     * @return receivedItem The received item.
     */
    function _copySpentAsReceivedToSelf(SpentItem calldata spentItem)
        internal
        view
        returns (ReceivedItem memory receivedItem)
    {
        assembly {
            calldatacopy(receivedItem, spentItem, 0x80)
            mstore(add(receivedItem, 0x80), address())
        }
    }
}
