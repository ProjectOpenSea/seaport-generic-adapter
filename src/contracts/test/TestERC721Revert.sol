// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import { TestERC721 } from "./TestERC721.sol";

contract TestERC721Revert is TestERC721 {
    error AlwaysRevert();

    bool revertSpectacularly;

    function setRevertSpectacularly(bool _revertSpectacularly) external {
        revertSpectacularly = _revertSpectacularly;
    }

    function transferFrom(address, address, uint256) public view override {
        if (revertSpectacularly) {
            bytes memory a = new bytes(0x10000);
            for (uint256 i; i < a.length; ++i) {
                a[i] = bytes1("a");
            }
            revert(string(a));
        } else {
            revert AlwaysRevert();
        }
    }

    function setApprovalForAll(address, bool) public view override {
        if (revertSpectacularly) {
            bytes memory a = new bytes(0x10000);
            for (uint256 i; i < a.length; ++i) {
                a[i] = bytes1("a");
            }
            revert(string(a));
        } else {
            revert AlwaysRevert();
        }
    }
}
