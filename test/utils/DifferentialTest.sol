// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Test } from "forge-std/Test.sol";

contract DifferentialTest is Test {
    ///@dev error to supply
    error RevertWithFailureStatus(bool status);
    error DifferentialTestAssertionFailed();

    // slot where vm stores a bool representing whether or not an assertion has
    // failed
    bytes32 vm_FAILED_SLOT = bytes32("failed");

    // hash of the bytes surfaced by `revert RevertWithFailureStatus(false)`
    bytes32 PASSING_HASH = keccak256(
        abi.encodeWithSelector(RevertWithFailureStatus.selector, false)
    );

    ///@dev reverts after function body with vm failure status, which clears all
    /// state changes
    ///     but still surfaces assertion failure status.
    modifier stateless() {
        _;
        revert RevertWithFailureStatus(readvmFailureSlot());
    }

    ///@dev revert if the supplied bytes do not match the expected "passing"
    /// revert bytes
    function assertPass(bytes memory reason) internal view {
        // hash the reason and compare to the hash of the passing revert bytes
        if (keccak256(reason) != PASSING_HASH) {
            revert DifferentialTestAssertionFailed();
        }
    }

    ///@dev read the failure slot of the vm using the vm.load cheatcode
    ///     Returns true if there was an assertion failure. recorded.
    function readvmFailureSlot() internal view returns (bool) {
        return vm.load(address(vm), vm_FAILED_SLOT) == bytes32(uint256(1));
    }
}
