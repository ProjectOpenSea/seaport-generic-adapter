// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { Call, OrderContext } from "../../src/lib/AdapterHelperLib.sol";

struct SetupCall {
    address sender;
    address target;
    bytes data;
}

struct OrderPayload {
    // Call needed to submit order on-chain without signature
    Call submitOrder;
    // Call needed to actually execute the order
    Call executeOrder;
}
