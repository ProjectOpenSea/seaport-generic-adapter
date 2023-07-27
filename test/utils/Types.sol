// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { CallParameters } from "../../src/lib/AdapterHelperLib.sol";

struct SetupCall {
    address sender;
    address target;
    bytes data;
}

struct TestOrderPayload {
    // Call needed to submit order on-chain without signature
    CallParameters submitOrder;
    // Call needed to actually execute the order
    CallParameters executeOrder;
}
