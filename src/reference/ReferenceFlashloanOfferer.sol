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

interface Cleanup {
    function cleanup(address recipient) external payable returns (bytes4);
}

/**
 * @title ReferenceFlashloanOfferer
 * @author 0age, snotrocket.eth
 * @notice FlashloanOfferer is a proof of concept for a flashloan contract
 *         offerer. It will send native tokens to each specified recipient in
 *         the given amount when generating an order, and can optionally trigger
 *         callbacks for those recipients when ratifying the order after it has
 *         executed. It will aggregate all provided native tokens and return a
 *         single maximumSpent item with itself as the recipient for the total
 *         amount of aggregated native tokens. This is the reference
 *         implementation.
 */
contract ReferenceFlashloanOfferer is ContractOffererInterface {
    address private immutable _SEAPORT;

    address private wrappedTokenAddress;

    mapping(address => uint256) public balanceOf;

    Cleanup cleanupInterface;

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

        emit SeaportCompatibleContractDeployed();
    }

    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
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
        return this.onERC721Received.selector;
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
        return this.onERC1155Received.selector;
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
    )
        external
        override
        returns (SpentItem[] memory offer, ReceivedItem[] memory consideration)
    {
        address _fulfiller = fulfiller;

        // Revert if the maximumSpent array is not exactly 1 item long.
        if (maximumSpent.length != 1) {
            revert InvalidTotalMaximumSpentItems();
        }

        // Get the maximumSpent item and amount.
        SpentItem calldata maximumSpentItem = maximumSpent[0];
        uint256 maximumSpentAmount = maximumSpentItem.amount;

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

            // Revert if minimumReceived item amount is greater than
            // maximumSpent, or if any of the following are not true:
            //  - one of the item types is 1 and the other is 0
            //  - one of the tokens is address(this) and the other is null
            //  - item type 1 has address(this) token and 0 is null token

            if (minimumReceivedItem.amount > maximumSpentAmount) {
                revert MinGreaterThanMax();
            }

            if (minimumReceivedItem.itemType == maximumSpentItem.itemType) {
                revert SharedItemTypes();
            }

            // These are silly, just an experiment in more closely modeling
            // the behavior of the optimized contracts.

            address typeNeutralizedAddressMin = minimumReceivedItem.itemType
                == ItemType.ERC20 ? minimumReceivedItem.token : address(0);
            address typeNeutralizedAddressMax = maximumSpentItem.itemType
                == ItemType.ERC20 ? maximumSpentItem.token : address(0);
            address xorAddress = address(
                uint160(typeNeutralizedAddressMin)
                    ^ uint160(typeNeutralizedAddressMax)
            );

            if (xorAddress != address(this)) {
                revert UnacceptableTokenPairing();
            }

            bool isOneButNotBoth = (
                minimumReceivedItem.token == address(this)
                    || maximumSpentItem.token == address(this)
            )
                && !(
                    minimumReceivedItem.token == address(this)
                        && maximumSpentItem.token == address(this)
                );

            if (
                !(isOneButNotBoth)
                    || !(
                        minimumReceivedItem.itemType == ItemType.NATIVE
                            || maximumSpentItem.itemType == ItemType.NATIVE
                    )
            ) {
                revert MismatchedAddresses();
            }

            // Process the deposit or withdrawal.
            _processDepositOrWithdrawal(
                _fulfiller, minimumReceivedItem, context
            );
        } else {
            // Revert if the minimumReceived array is not 0 or 1 items long.
            revert InvalidTotalMinimumReceivedItems();
        }

        // Convert the maximumSpent item to a ReceivedItem.
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
    ) external override returns (bytes4 ratifyOrderMagicValue) {
        // Silence compiler warning.
        ratifyOrderMagicValue = bytes4(0);

        // If the caller is not Seaport, revert.
        if (msg.sender != _SEAPORT) {
            revert InvalidCaller(msg.sender);
        }

        // If context is present...
        if (context.length > 0) {
            // ...look for flashloans with callback flags.

            // Extract the cleanup recipient address from the context.
            address cleanupRecipient = address(
                // My God the assembly might be clearer than this.
                uint160(bytes20(context[32:52]))
            );

            // Retrieve the number of flashloans.
            uint256 totalFlashloans = uint256(bytes32(context[52:53])) >> 248;

            // Include one word of flashloan data for each flashloan.
            uint256 flashloanDataSize = 32 * totalFlashloans;

            uint256 flashloanDataInitialOffset = 21;
            uint256 startingIndex;
            uint256 endingIndex;
            bool shouldCall;

            // Iterate over each flashloan, one word of memory at a time.
            for (uint256 i = 0; i < flashloanDataSize;) {
                // Increment i by 32 bytes (1 word) to get the next word.
                i += 32;

                startingIndex = flashloanDataInitialOffset + i;
                endingIndex = flashloanDataInitialOffset + i + 32;

                // Extract the shouldCall flag from the flashloan data.
                shouldCall = context[startingIndex + 11] == 0x01;

                // Extract the recipient address from the flashloan data.
                address recipient = address(
                    uint160(bytes20(context[endingIndex - 20:endingIndex]))
                );

                if (shouldCall == true) {
                    // Call the generic adapter's cleanup function.
                    (bool success, bytes memory returnData) = recipient.call(
                        abi.encodeWithSignature(
                            "cleanup(address)", cleanupRecipient
                        )
                    );

                    if (
                        success == false
                            || bytes4(returnData)
                                != cleanupInterface.cleanup.selector
                    ) {
                        revert CallFailed();
                    }
                }
            }

            // If everything's OK, return the magic value.
            return bytes4(this.ratifyOrder.selector);
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
        schemas[0] = Schema({ id: 12, metadata: "" });
        return ("FlashloanOfferer", schemas);
    }

    function _processFlashloan(bytes calldata context)
        internal
        returns (uint256 totalSpent)
    {
        // Get the length of the context array from calldata.
        uint256 contextLength = uint256(bytes32(context[31:32])) >> 248;

        if (contextLength == 0 || context.length == 0) {
            revert InvalidExtraDataEncoding(uint8(context[0]));
        }

        uint256 flashloanDataSize;
        {
            // Check is that caller is Seaport.
            if (msg.sender != _SEAPORT) {
                revert InvalidCaller(msg.sender);
            }

            // Check for sip-6 version byte.
            if (context[0] != 0x00) {
                revert UnsupportedExtraDataVersion(uint8(context[0]));
            }

            // Retrieve the number of flashloans.
            uint256 totalFlashloans = uint256(bytes32(context[52:53])) >> 248;

            // Include one word of flashloan data for each flashloan.
            flashloanDataSize = 32 * totalFlashloans;

            if (contextLength < 22 + flashloanDataSize) {
                revert InvalidExtraDataEncoding(uint8(context[0]));
            }
        }

        uint256 flashloanDataInitialOffset = 21;
        uint256 startingIndex;
        uint256 endingIndex;
        uint256 value;
        address recipient;
        uint256 totalValue;

        // Iterate over each flashloan, one word of memory at a time.
        for (uint256 i = 0; i < flashloanDataSize;) {
            // Increment i by 32 bytes (1 word) to get the next word.
            i += 32;

            // The first 32 bytes of the context are the SIP encoding and the
            // context length with some ignored bytes in between. The next 21
            // bytes of the context are the cleanup recipient address, the sum
            // of the two gives the start i value.
            // So, the first flashloan starts at byte 53 and goes to byte
            // 85. `startingIndex` and `endingIndex` define the range of bytes
            // for each flashloan.
            startingIndex = flashloanDataInitialOffset + i;
            endingIndex = flashloanDataInitialOffset + i + 32;

            // Bytes at indexes 0-10 are the value, at index 11 is the flag, and
            // at indexes 12-31 are the recipient address.
            value = uint256(bytes32(context[startingIndex:startingIndex + 11]))
                >> 168;
            recipient =
                address(uint160(bytes20(context[endingIndex - 20:endingIndex])));

            // Track the total value of all flashloans for a subsequent check in
            // `generateOrder`.
            totalValue += value;

            // Send the flashloan to the recipient.
            (bool success,) = recipient.call{ value: value }("");

            // If the call fails, revert.
            if (!success) {
                revert CallFailed();
            }
        }

        // Return the total value of all flashloans.
        return totalValue;
    }

    function _processDepositOrWithdrawal(
        address fulfiller,
        SpentItem calldata spentItem,
        bytes calldata context
    ) internal {
        // Get the length of the context array from calldata (unmasked).
        uint256 contextLength = uint256(bytes32(context));

        // Check is that caller is Seaport.
        if (msg.sender != _SEAPORT) {
            revert InvalidCaller(msg.sender);
        }

        // Next, check that context is empty.
        if (contextLength != 0 || context.length != 0) {
            revert InvalidExtraDataEncoding(0);
        }

        // If the item has this contract as its token, process as a deposit.
        if (spentItem.token == address(this)) {
            balanceOf[fulfiller] += spentItem.amount;
        } else {
            // Otherwise it is a withdrawal.
            balanceOf[fulfiller] -= spentItem.amount;
        }
    }

    /**
     * @dev Copies a spent item from calldata and converts into a received item,
     *      applying address(this) as the recipient.
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
        return ReceivedItem({
            itemType: spentItem.itemType,
            token: spentItem.token,
            identifier: spentItem.identifier,
            amount: spentItem.amount,
            recipient: payable(address(this))
        });
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
