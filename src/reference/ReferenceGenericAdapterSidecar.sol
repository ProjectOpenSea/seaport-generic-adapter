// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

struct Call {
    address target;
    bool allowFailure;
    uint256 value;
    bytes callData;
}

/**
 * @title ReferenceGenericAdapterSidecar
 * @author 0age, snotrocket.eth
 * @notice GenericAdapterSidecar is a contract that is deployed alongside a
 *         GenericAdapter contract and that performs arbitrary calls in an
 *         isolated context. It is imperative that this contract does not ever
 *         receive approvals, as there are no access controls preventing an
 *         arbitrary party from taking those tokens. Similarly, any tokens left
 *         on this contract can be taken by an arbitrary party on subsequent
 *         calls.  This is the high level reference implementation.
 */
contract ReferenceGenericAdapterSidecar {
    error InvalidEncodingOrCaller(); // 0x8f183575
    error CallFailed(uint256 index); // 0x3f9a3b48
    error NativeTokenTransferGenericFailure(); // 0xffce28d3
    error NoContract(address);

    address private immutable _DESIGNATED_CALLER;

    constructor() {
        _DESIGNATED_CALLER = msg.sender;
    }

    /**
     * @dev Enable accepting native tokens.
     */
    receive() external payable { }

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
     * @dev Execute an arbitrary sequence of calls. Only callable from the
     *      designated caller.  The selector is 0xb252b6e5.
     */
    function execute(Call[] calldata calls) external payable {
        // Retrieve designated caller from runtime code & place value on stack.
        address designatedCaller = _DESIGNATED_CALLER;

        // Revert if the caller is not the designated caller.
        if (msg.sender != designatedCaller) {
            revert InvalidEncodingOrCaller();
        }

        bool success;

        // Iterate over each call.
        for (uint256 i = 0; i < calls.length; ++i) {
            if (calls[i].target.code.length == 0) {
                revert NoContract(calls[i].target);
            }

            // Call the target and get success status.
            (success,) =
                calls[i].target.call{ value: calls[i].value }(calls[i].callData);

            // If the call fails and the call is not allowed to fail, revert.
            if (calls[i].allowFailure == false && success == false) {
                revert CallFailed(i);
            }
        }

        // Return excess native tokens, if any remain, to the caller.
        if (address(this).balance > 0) {
            // Declare a variable indicating whether the call was successful.
            (success,) = msg.sender.call{ value: address(this).balance }("");

            // If the call fails, revert.
            if (!success) {
                revert NativeTokenTransferGenericFailure();
            }
        }
    }
}
