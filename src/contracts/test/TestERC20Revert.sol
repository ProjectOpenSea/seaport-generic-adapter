// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC20} from "@rari-capital/solmate/src/tokens/ERC20.sol";

contract TestERC20Revert is ERC20("TestRevert", "REVERT", 18) {
    error AlwaysRevert();

    bool revertSpectacularly;

    function setRevertSpectacularly(bool _revertSpectacularly) external {
        revertSpectacularly = _revertSpectacularly;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function transferFrom(
        address,
        /* from */
        address,
        /* to */
        uint256 /* amount */
    ) public view override returns (bool) {
        if (revertSpectacularly) {
            revert(
                "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
            );
        } else {
            revert AlwaysRevert();
        }
    }

    function approve(
        address,
        /* spender */
        uint256 /* amount */
    ) public view override returns (bool) {
        if (revertSpectacularly) {
            revert(
                "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
            );
        } else {
            revert AlwaysRevert();
        }
    }
}
