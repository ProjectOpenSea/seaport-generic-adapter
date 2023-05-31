// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ConduitController } from "seaport-core/conduit/ConduitController.sol";

import { ConduitControllerInterface } from "seaport-types/interfaces/ConduitControllerInterface.sol";

import { ConsiderationInterface } from "seaport-types/interfaces/ConsiderationInterface.sol";

import { ItemType } from "seaport-types/lib/ConsiderationEnums.sol";

import { OfferItem, ConsiderationItem } from "seaport-types/lib/ConsiderationStructs.sol";

import { DifferentialTest } from "./DifferentialTest.sol";

import { StructCopier } from "./StructCopier.sol";

import { Conduit } from "seaport-core/conduit/Conduit.sol";

import { Consideration } from "seaport-core/lib/Consideration.sol";

/// @dev Base test case that deploys Consideration and its dependencies
contract BaseConsiderationTest is DifferentialTest, StructCopier {
    ConsiderationInterface consideration;
    bytes32 conduitKeyOne;
    ConduitControllerInterface conduitController;
    Conduit conduit;
    bool coverage_or_debug;

    function tryEnvBool(string memory envVar) internal view returns (bool) {
        try vm.envBool(envVar) returns (bool _value) {
            return _value;
        } catch {
            return false;
        }
    }

    function tryEnvString(string memory envVar) internal view returns (string memory) {
        try vm.envString(envVar) returns (string memory _value) {
            return _value;
        } catch {
            return "";
        }
    }

    function stringEq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }

    function debugEnabled() internal view returns (bool) {
        return tryEnvBool("SEAPORT_COVERAGE") || stringEq(tryEnvString("FOUNDRY_PROFILE"), "debug");
    }

    function setUp() public virtual {
        // conditionally deploy contracts normally or from precompiled source
        // deploys normally when SEAPORT_COVERAGE is true for coverage analysis
        // or when FOUNDRY_PROFILE is "debug" for debugging with source maps
        // deploys from precompiled source when both are false
        coverage_or_debug = debugEnabled();

        conduitKeyOne = bytes32(uint256(uint160(address(this))) << 96);
        _deployAndConfigurePrecompiledOptimizedConsideration();

        vm.label(address(conduitController), "conduitController");
        vm.label(address(consideration), "consideration");
        vm.label(address(conduit), "conduit");
        vm.label(address(this), "testContract");
    }

    ///@dev deploy optimized consideration contracts from pre-compiled source
    //      (solc-0.8.17, IR pipeline enabled, unless running coverage or debug)
    function _deployAndConfigurePrecompiledOptimizedConsideration() public {
        if (!coverage_or_debug) {
            conduitController = ConduitController(deployCode("out/ConduitController.sol/ConduitController.json"));
            consideration = ConsiderationInterface(
                deployCode("out/Consideration.sol/Consideration.json", abi.encode(address(conduitController)))
            );
        } else {
            conduitController = new ConduitController();
            consideration = new Consideration(address(conduitController));
        }
        //create conduit, update channel
        conduit = Conduit(conduitController.createConduit(conduitKeyOne, address(this)));
        conduitController.updateChannel(address(conduit), address(consideration), true);
    }

    function singleOfferItem(
        ItemType _itemType,
        address _tokenAddress,
        uint256 _identifierOrCriteria,
        uint256 _startAmount,
        uint256 _endAmount
    ) internal pure returns (OfferItem[] memory offerItem) {
        offerItem = new OfferItem[](1);
        offerItem[0] = OfferItem(_itemType, _tokenAddress, _identifierOrCriteria, _startAmount, _endAmount);
    }

    function singleConsiderationItem(
        ItemType _itemType,
        address _tokenAddress,
        uint256 _identifierOrCriteria,
        uint256 _startAmount,
        uint256 _endAmount,
        address _recipient
    ) internal pure returns (ConsiderationItem[] memory considerationItem) {
        considerationItem = new ConsiderationItem[](1);
        considerationItem[0] = ConsiderationItem(
            _itemType, _tokenAddress, _identifierOrCriteria, _startAmount, _endAmount, payable(_recipient)
        );
    }

    function signOrder(ConsiderationInterface _consideration, uint256 _pkOfSigner, bytes32 _orderHash)
        internal
        view
        returns (bytes memory)
    {
        (bytes32 r, bytes32 s, uint8 v) = getSignatureComponents(_consideration, _pkOfSigner, _orderHash);
        return abi.encodePacked(r, s, v);
    }

    function signOrder2098(ConsiderationInterface _consideration, uint256 _pkOfSigner, bytes32 _orderHash)
        internal
        view
        returns (bytes memory)
    {
        (bytes32 r, bytes32 s, uint8 v) = getSignatureComponents(_consideration, _pkOfSigner, _orderHash);
        uint256 yParity;
        if (v == 27) {
            yParity = 0;
        } else {
            yParity = 1;
        }
        uint256 yParityAndS = (yParity << 255) | uint256(s);
        return abi.encodePacked(r, yParityAndS);
    }

    function getSignatureComponents(ConsiderationInterface _consideration, uint256 _pkOfSigner, bytes32 _orderHash)
        internal
        view
        returns (bytes32, bytes32, uint8)
    {
        (, bytes32 domainSeparator,) = _consideration.information();
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(_pkOfSigner, keccak256(abi.encodePacked(bytes2(0x1901), domainSeparator, _orderHash)));
        return (r, s, v);
    }
}
