// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { ContractOffererInterface } from
    "seaport-types/interfaces/ContractOffererInterface.sol";

import { ItemType } from "seaport-types/lib/ConsiderationEnums.sol";

import {
    ReceivedItem,
    Schema,
    SpentItem
} from "seaport-types/lib/ConsiderationStructs.sol";

import "forge-std/console.sol";

/**
 * @title FlashloanOfferer
 * @author 0age, snotrocket.eth
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

    address private wrappedTokenAddress;

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

    /**
     * @dev Revert with an error if the supplied maximumSpentItem is not WETH.
     *
     * @param item The invalid maximumSpentItem.
     */
    error InvalidMaximumSpentItem(SpentItem item);

    /**
     * @dev Revert with an error if the chainId is not supported.
     *
     * @param chainId The invalid chainId.
     */
    error UnsupportedChainId(uint256 chainId);

    /**
     * @dev Emit an event at deployment to indicate the contract is SIP-5
     *      compatible.
     */
    event SeaportCompatibleContractDeployed();

    constructor(address seaport) {
        _SEAPORT = seaport;

        // Set the wrapped token address based on chain id.
        if (block.chainid == 1) {
            // Mainnet
            wrappedTokenAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        } else if (block.chainid == 5) {
            // Goerli
            wrappedTokenAddress = 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6;
        } else if (block.chainid == 11155111) {
            // Sepolia
            wrappedTokenAddress = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
        } else if (block.chainid == 137) {
            // Polygon (WMATIC)
            wrappedTokenAddress = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
        } else if (block.chainid == 80001) {
            // Mumbai (WMATIC)
            wrappedTokenAddress = 0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889;
        } else if (block.chainid == 10 || block.chainid == 420) {
            // Optimism and Optimism Goerli
            wrappedTokenAddress = 0x4200000000000000000000000000000000000006;
        } else if (block.chainid == 42161) {
            // Arbitrum One
            wrappedTokenAddress = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
        } else if (block.chainid == 421613) {
            // Arbitrum Goerli
            wrappedTokenAddress = 0xEe01c0CD76354C383B8c7B4e65EA88D00B06f36f;
        } else if (block.chainid == 42170) {
            // Arbitrum Nova
            wrappedTokenAddress = 0x722E8BdD2ce80A4422E880164f2079488e115365;
        } else if (block.chainid == 43114) {
            // Avalanche C-Chain (WAVAX)
            wrappedTokenAddress = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
        } else if (block.chainid == 43113) {
            // Avalanche Fuji (WAVAX)
            wrappedTokenAddress = 0xd00ae08403B9bbb9124bB305C09058E32C39A48c;
        } else if (block.chainid == 56) {
            // Binance Smart Chain (WBNB)
            wrappedTokenAddress = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
        } else if (block.chainid == 97) {
            // Binance Smart Chain Testnet (WBNB)
            wrappedTokenAddress = 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd;
        } else if (block.chainid == 100) {
            // Gnosis (WXDAI)
            wrappedTokenAddress = 0xe91D153E0b41518A2Ce8Dd3D7944Fa863463a97d;
        } else if (block.chainid == 8217) {
            // Klaytn (WKLAY)
            wrappedTokenAddress = 0xfd844c2fcA5e595004b17615f891620d1cB9bBB2;
        } else if (block.chainid == 1001) {
            // Baobab (WKLAY)
            wrappedTokenAddress = 0x9330dd6713c8328a8D82b14e3f60a0f0b4cc7Bfb;
        } else if (block.chainid == 1284) {
            // Moonbeam (WGLMR)
            wrappedTokenAddress = 0xAcc15dC74880C9944775448304B263D191c6077F;
        } else if (block.chainid == 1285) {
            // Moonriver (WMOVR)
            wrappedTokenAddress = 0x98878B06940aE243284CA214f92Bb71a2b032B8A;
        } else if (
            block
                // OP chains: Optimisim (10), Optimism Goerli (420), Base
                // (8453), Base Goerli (84531), Zora (7777777), and Zora Testnet
                // (999).
                .chainid == 10 || block.chainid == 420 || block.chainid == 8453
                || block.chainid == 84531 || block.chainid == 7777777
                || block.chainid == 999
        ) {
            wrappedTokenAddress = 0x4200000000000000000000000000000000000006;
        } else {
            // Revert if the chain ID is not supported.
            revert UnsupportedChainId(block.chainid);
        }

        // Emit an event to indicate the contract is SIP-5 compatible.
        emit SeaportCompatibleContractDeployed();
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        returns (bool)
    {
        return interfaceId == type(ContractOffererInterface).interfaceId;
    }

    /**
     * @dev Enable accepting ERC721 tokens via safeTransfer.
     */
    function onERC721Received(address, address, uint256, bytes calldata)
        external
        payable
        returns (bytes4)
    {
        assembly {
            mstore(0, 0x150b7a02)
            return(0x1c, 0x20)
        }
    }

    /**
     * @dev Enable accepting ERC1155 tokens via safeTransfer.
     */
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external payable returns (bytes4) {
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
     *                           - context length (4 bytes)
     *                           - cleanupRecipient: arg for cleanup (20 bytes)
     *                           - flashloans to send (1 byte)
     *                           - flashloan data:
     *                               - amount (11 bytes * totalRecipients)
     *                               - shouldCallback (1 byte * totalRecipients)
     *                               - recipient (20 bytes * totalRecipients)
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
    )
        external
        override
        returns (SpentItem[] memory offer, ReceivedItem[] memory consideration)
    {
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
            if (_isInvalidMaximumSpentItem(maximumSpentItem)) {
                revert InvalidMaximumSpentItem(maximumSpentItem);
            }
            if (_processFlashloan(context) > maximumSpentAmount) {
                revert InsufficientMaximumSpentAmount();
            }
        } else if (minimumReceived.length == 1) {
            // One minimumReceived item indicates a deposit or withdrawal.
            SpentItem calldata minimumReceivedItem = minimumReceived[0];

            assembly {
                // Revert if minimumReceived item amount is greater than
                // maximumSpent, or if any of the following is not true:
                //  - one of the item types is 1 and the other is 0 (so, both
                // item items same, revert)
                //  - one of the tokens is address(this) and the other is null
                // (so, both same, revert or neither is this, revert)
                //  - item type 1 has address(this) token and 0 is null token

                // Ensure that minimumReceived item amount is less than or equal
                // to maximumSpent.
                let errorBuffer :=
                    gt(
                        calldataload(add(minimumReceivedItem, 0x60)),
                        maximumSpentAmount
                    )

                // Ensure that the items don't share a type.
                errorBuffer :=
                    or(
                        errorBuffer,
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
                errorBuffer :=
                    or(
                        errorBuffer,
                        shl(
                            2,
                            // 1 if the ERC20 address is not this contract.
                            iszero(
                                // 1 if the ERC20 address is this contract.
                                eq(
                                    // Since it has to be a zero and a 1 for item
                                    // types, this just returns the non-null address
                                    // token.
                                    add(
                                        // Token value if ERC20, 0 otherwise.
                                        mul(
                                            calldataload(minimumReceivedItem),
                                            calldataload(
                                                add(minimumReceivedItem, 0x20)
                                            )
                                        ),
                                        // Token value if ERC20, 0 otherwise.
                                        mul(
                                            calldataload(maximumSpentItem),
                                            calldataload(
                                                add(maximumSpentItem, 0x20)
                                            )
                                        )
                                    ),
                                    address()
                                )
                            )
                        )
                    )

                // Ensure that exactly one of the items uses address(this).
                errorBuffer :=
                    or(
                        errorBuffer,
                        shl(
                            3,
                            iszero(
                                // 1 if one is native and the other is this address.
                                and(
                                    // 1 if either is native.
                                    iszero(
                                        // 0 if either is native.
                                        mul(
                                            calldataload(
                                                add(minimumReceivedItem, 0x20)
                                            ),
                                            calldataload(
                                                add(maximumSpentItem, 0x20)
                                            )
                                        )
                                    ),
                                    // 1 if the lone non-null address is this
                                    // contract.
                                    iszero(
                                        // Returns either this address or 0.
                                        // Is only zero if the address from the
                                        // `add` is this address.
                                        xor(
                                            // Just returns the non-null address
                                            // token.
                                            add(
                                                calldataload(
                                                    add(minimumReceivedItem, 0x20)
                                                ),
                                                calldataload(
                                                    add(maximumSpentItem, 0x20)
                                                )
                                            ),
                                            address()
                                        )
                                    )
                                )
                            )
                        )
                    )

                if errorBuffer {
                    if shl(255, errorBuffer) {
                        mstore(0, 0xc9b4d6ba)
                        revert(0x1c, 0x04)
                    }

                    if shl(254, errorBuffer) {
                        mstore(0, 0xc25bddad)
                        revert(0x1c, 0x04)
                    }

                    if shl(253, errorBuffer) {
                        mstore(0, 0xdd55e6a8)
                        revert(0x1c, 0x04)
                    }

                    if shl(252, errorBuffer) {
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
    receive() external payable { }

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
                let cleanupRecipient :=
                    shr(96, calldataload(add(32, context.offset)))
                // 53 = 32 bytes for the first word (SIP encoding and length),
                // plus 20 bytes for the cleanup recipient, plus one for the
                // total flashloans.
                let flashloanDataStarts := add(context.offset, 53)
                let totalFlashloans :=
                    and(0xff, calldataload(add(context.offset, 21)))

                // Include one word of flashloan data for each flashloan.
                let flashloanDataSize := shl(0x05, totalFlashloans)
                let flashloanDataEnds :=
                    add(flashloanDataStarts, flashloanDataSize)

                mstore(0, 0xfbacefce) // cleanup(address) selector
                mstore(0x20, cleanupRecipient)

                // Iterate over each flashloan.
                for { let flashloanDataOffset := flashloanDataStarts } lt(
                    flashloanDataOffset, flashloanDataEnds
                ) { flashloanDataOffset := add(flashloanDataOffset, 0x20) } {
                    let flashloanData := calldataload(flashloanDataOffset)
                    let shouldCall := byte(11, flashloanData)
                    let flashloanRecipient :=
                        and(
                            0xffffffffffffffffffffffffffffffffffffffff,
                            flashloanData
                        )

                    // Fire off call to flashloanRecipient. Revert & bubble up
                    // revert data if present & reasonably-sized, else revert
                    // with a custom error. Note that checking for sufficient
                    // native token balance is an option here if more specific
                    // custom reverts are preferred.
                    if shouldCall {
                        let success :=
                            call(gas(), flashloanRecipient, 0, 0x1c, 0x24, 0, 4)

                        if or(
                            or(iszero(success), iszero(shouldCall)),
                            // magic cleanup(address) selector
                            xor(
                                mload(0),
                                0xfbacefce000000000000000000000000000000000000000000000000fbacefce
                            )
                        ) {
                            if and(
                                and(
                                    iszero(success),
                                    iszero(iszero(returndatasize()))
                                ),
                                lt(returndatasize(), 0xffff)
                            ) {
                                returndatacopy(0, 0, returndatasize())
                                revert(0, returndatasize())
                            }

                            // CallFailed()
                            mstore(0, 0x3204506f)
                            revert(0x1c, 0x04)
                        }
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
     * @custom:param fulfiller   The address of the fulfiller (e.g. the account
     *                           calling Seaport).
     * @custom:param minReceived The minimum items that the caller is willing to
     *                           receive.
     * @custom:param maxSpent    The maximum items caller is willing to spend.
     * @custom:param context     Additional context of the order.
     *
     * @return offer         A tuple containing the offer items.
     * @return consideration A tuple containing the consideration items.
     */
    function previewOrder(
        address,
        address,
        SpentItem[] calldata,
        SpentItem[] calldata,
        bytes calldata
    )
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
        schemas = new Schema[](1);
        // TODO: update this to the correct SIP ID
        schemas[0] = Schema({ id: 12, metadata: "" });
        return ("FlashloanOfferer", schemas);
    }

    function _processFlashloan(bytes calldata context)
        internal
        returns (uint256 totalSpent)
    {
        // Get the length of the context array from calldata (masked).
        uint256 contextLength;
        assembly {
            contextLength := and(calldataload(context.offset), 0xfffffff)
        }

        if (contextLength == 0 || context.length == 0) {
            revert InvalidExtraDataEncoding(uint8(context[0]));
        }

        // The expected structure of the context is:
        // [version, 1 byte][ignored 27 bytes][context arg length 4 bytes]
        // [cleanupRecipient, 20 bytes][totalFlashloans, 1
        // byte][flashloanData...]
        //
        // 0x00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee11111111
        // aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaccffffffffffffffffffffff...

        uint256 flashloanDataSize;
        {
            // Declare an error buffer; first check is that caller is Seaport.
            // If the caller is not Seaport, revert with an InvalidCaller error.
            uint256 errorBuffer = _cast(msg.sender != _SEAPORT);

            // Next, check for sip-6 version byte. If the version byte is not
            // 0, revert with an UnsupportedExtraDataVersion error.
            errorBuffer |= errorBuffer ^ (_cast(context[0] != 0x00) << 1);

            uint256 totalFlashloans;

            // Retrieve the number of flashloans.
            assembly {
                totalFlashloans :=
                    and(0xff, calldataload(add(context.offset, 21)))

                // Include one word of flashloan data for each flashloan.
                flashloanDataSize := shl(0x05, totalFlashloans)
            }

            // Next, check for sufficient context length. If the context length
            // is less than 22 + flashloanDataSize, revert with an
            // InvalidExtraDataEncoding error.
            unchecked {
                errorBuffer |= errorBuffer
                    ^ (_cast(contextLength < 22 + flashloanDataSize) << 2);
            }

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
            // 53 = 32 bytes for the first word (SIP encoding and length), plus
            // 20 bytes for the cleanup recipient, plus one for the total
            // flashloans.
            let flashloanDataStarts := add(context.offset, 53)
            let flashloanDataEnds := add(flashloanDataStarts, flashloanDataSize)
            // Iterate over each flashloan.
            for { let flashloanDataOffset := flashloanDataStarts } lt(
                flashloanDataOffset, flashloanDataEnds
            ) { flashloanDataOffset := add(flashloanDataOffset, 0x20) } {
                // Load the entire flashloan data word. Shift right 21 bytes to
                // get the value, and mask the recipient address.
                let value := shr(168, calldataload(flashloanDataOffset))
                // Load the entire flashloan data word. Mask it to get the
                // recipient address.
                let recipient :=
                    and(
                        0xffffffffffffffffffffffffffffffffffffffff,
                        calldataload(flashloanDataOffset)
                    )

                totalValue := add(totalValue, value)

                // Fire off call to recipient. Revert & bubble up revert data if
                // present & reasonably-sized, else revert with a custom error.
                // Note that checking for sufficient native token balance is an
                // option here if more specific custom reverts are preferred.
                if iszero(call(gas(), recipient, value, 0, 0, 0, 0)) {
                    if and(
                        iszero(iszero(returndatasize())),
                        lt(returndatasize(), 0xffff)
                    ) {
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

    function _processDepositOrWithdrawal(
        address fulfiller,
        SpentItem calldata spentItem,
        bytes calldata context
    ) internal {
        {
            // Get the length of the context array from calldata (unmasked).
            uint256 contextLength;
            assembly {
                contextLength := calldataload(context.offset)
            }

            // Declare an error buffer; first check is that caller is Seaport.
            uint256 errorBuffer = _cast(msg.sender != _SEAPORT);

            // Next, check that context is empty.
            errorBuffer |= errorBuffer
                ^ (_cast(contextLength != 0 || context.length != 0) << 1);

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

    function _isInvalidMaximumSpentItem(SpentItem memory maximumSpentItem)
        internal
        view
        returns (bool)
    {
        if (
            maximumSpentItem.itemType != ItemType.ERC20
                && maximumSpentItem.itemType != ItemType.NATIVE
        ) {
            return true;
        }

        if (
            maximumSpentItem.token == address(0)
                || maximumSpentItem.token == wrappedTokenAddress
        ) {
            return false;
        }

        return true;
    }

    function getBalance(address account) external view returns (uint256) {
        return balanceOf[account];
    }
}
