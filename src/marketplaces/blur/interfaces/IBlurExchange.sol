// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import { Input, Execution } from "../lib/OrderStructs.sol";

interface IBlurExchange {
    function open() external;

    function execute(Input calldata sell, Input calldata buy)
        external
        payable;

    function bulkExecute(Execution[] calldata executions) external payable;
}
