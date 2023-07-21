// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

struct Item721 {
    address token;
    uint256 identifier;
}

struct Item1155 {
    address token;
    uint256 identifier;
    uint256 amount;
}

struct Item20 {
    address token;
    uint256 amount;
}

struct CallParameters {
    address target;
    uint256 value;
    bytes data;
}

struct SetupCall {
    address sender;
    address target;
    bytes data;
}

struct TestOrderContext {
    bool listOnChain;
    bool routeThroughAdapter;
    address offerer;
    address fulfiller;
    address flashloanOfferer;
    address adapter;
    address sidecar;
}

struct TestOrderPayload {
    // Call needed to submit order on-chain without signature
    CallParameters submitOrder;
    // Call needed to actually execute the order
    CallParameters executeOrder;
}
