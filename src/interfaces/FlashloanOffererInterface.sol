// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { ContractOffererInterface } from
    "seaport-types/interfaces/ContractOffererInterface.sol";

import {
    ReceivedItem,
    Schema,
    SpentItem
} from "seaport-types/lib/ConsiderationStructs.sol";

interface FlashloanOffererInterface is ContractOffererInterface {
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

    error UnsupportedChainId(uint256 chainId);

    function generateOrder(
        address fulfiller,
        SpentItem[] calldata minimumReceived,
        SpentItem[] calldata maximumSpent,
        bytes calldata context // encoded based on the schemaID
    )
        external
        returns (SpentItem[] memory offer, ReceivedItem[] memory consideration);

    function ratifyOrder(
        SpentItem[] calldata, /* offer */
        ReceivedItem[] calldata, /* consideration */
        bytes calldata context, // encoded based on the schemaID
        bytes32[] calldata, /* orderHashes */
        uint256 /* contractNonce */
    ) external returns (bytes4);

    function previewOrder(
        address,
        address,
        SpentItem[] calldata,
        SpentItem[] calldata,
        bytes calldata
    ) external pure returns (SpentItem[] memory, ReceivedItem[] memory);

    function getSeaportMetadata()
        external
        pure
        returns (string memory name, Schema[] memory schemas); // map to Seaport Improvement Proposal IDs

    function getBalance(address account) external view returns (uint256);
}
