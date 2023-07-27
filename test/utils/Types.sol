// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { Call, OrderContext } from "../../src/lib/AdapterHelperLib.sol";

struct TestOrderContext {
    bool listOnChain;
    bool routeThroughAdapter;
    OrderContext orderContext;
}

struct SetupCall {
    address sender;
    address target;
    bytes data;
}

struct TestOrderPayload {
    // Call needed to submit order on-chain without signature
    Call submitOrder;
    // Call needed to actually execute the order
    Call executeOrder;
}
