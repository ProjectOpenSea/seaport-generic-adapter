// SPDX-License-Identifier: MIT
pragma solidity >=0.8.14;

import { BaseMarketConfig } from "../BaseMarketConfig.sol";
import { SetupCall, OrderPayload } from "../../utils/Types.sol";
import { Item20, Call, OrderContext } from "../../lib/AdapterHelperLib.sol";
import { ISwapRouter } from "./interfaces/ISwapRouter.sol";
import "forge-std/console2.sol";
import { TestERC20 } from "../../contracts/test/TestERC20.sol";
import { CastOfCharacters } from "../../../src/lib/AdapterHelperLib.sol";

import "forge-std/console.sol";

contract UniswapConfig is BaseMarketConfig {
    address factory;
    address currentMarket;

    function name() external pure override returns (string memory) {
        return "Uniswap";
    }

    function market() public view override returns (address) {
        return currentMarket;
    }

    ISwapRouter internal constant uniswapV3 =
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    address internal constant approvalTarget =
        0xE592427A0AEce92De3Edee1F18E0157C05861564;

    TestERC20 internal constant weth =
        TestERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    function beforeAllPrepareMarketplace(address, address) external override {
        buyerNftApprovalTarget = sellerNftApprovalTarget =
        buyerErc20ApprovalTarget =
            sellerErc20ApprovalTarget = address(approvalTarget);
    }

    function beforeAllPrepareMarketplaceCall(
        CastOfCharacters calldata,
        address[] calldata,
        address[] calldata
    ) external pure override returns (SetupCall[] memory) {
        SetupCall[] memory setupCalls = new SetupCall[](0);
        return setupCalls;
    }

    function getPayload_BuyOfferedERC20WithERC20(
        OrderContext calldata context,
        Item20 memory desiredPayment,
        Item20 memory offeredPayment
    ) external override returns (OrderPayload memory execution) {
        if (!context.listOnChain) {
            _notImplemented();
        }

        factory = uniswapV3.factory();
        (bool success, bytes memory data) = factory.call(
            abi.encodeWithSignature(
                "getPool(address,address,uint24)",
                desiredPayment.token,
                offeredPayment.token,
                500
            )
        );

        // TODO
        if (!success) {
            _notImplemented();
        }

        // uniswapV3.getPool(address(weth), offeredPayment.token, 500);

        currentMarket = address(uint160(uint256(bytes32(data))));

        // // This is just a no op to avoid errors. The idea is just to use the
        // // actual DAI/WETH pool for testing.
        // execution.submitOrder = Call({
        //     target: address(0),
        //     allowFailure: false,
        //     value: 0,
        //     callData: ""
        // });

        execution.executeOrder = Call(
            address(uniswapV3),
            false,
            0,
            getCalldataToBuyOfferedERC20WithERC20(
                context, desiredPayment, offeredPayment
            )
        );
    }

    function getCalldataToBuyOfferedERC20WithERC20(
        OrderContext calldata context,
        Item20 memory desiredPayment,
        Item20 memory offeredPayment
    ) public view returns (bytes memory) {
        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter
            .ExactOutputSingleParams({
            tokenIn: offeredPayment.token,
            tokenOut: desiredPayment.token,
            // TODO: come back and handle pool selection to make tests pass.
            fee: 500 * 6,
            recipient: context.castOfCharacters.fulfiller,
            deadline: block.timestamp + 1,
            amountOut: desiredPayment.amount,
            amountInMaximum: offeredPayment.amount,
            sqrtPriceLimitX96: 0
        });

        return abi.encodeWithSelector(
            ISwapRouter.exactOutputSingle.selector, params
        );

        // TODO: look into refunds
    }

    function getPayload_BuyOfferedERC20WithEther(
        OrderContext calldata context,
        Item20 memory desiredPayment,
        uint256 offeredEthAmount
    ) external view override returns (OrderPayload memory execution) {
        if (!context.listOnChain) {
            _notImplemented();
        }

        // // This is just a no op to avoid errors. The idea is just to use the
        // // actual DAI/WETH pool for testing.
        // execution.submitOrder = Call({
        //     target: address(0),
        //     allowFailure: false,
        //     value: 0,
        //     callData: ""
        // });

        execution.executeOrder = Call(
            address(uniswapV3),
            false,
            offeredEthAmount,
            getCalldataToBuyOfferedERC20WithEther(
                context, desiredPayment, offeredEthAmount
            )
        );
    }

    function getCalldataToBuyOfferedERC20WithEther(
        OrderContext calldata context,
        Item20 memory desiredPayment,
        uint256 offeredEthAmount
    ) public view returns (bytes memory) {
        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter
            .ExactOutputSingleParams({
            tokenIn: address(weth),
            tokenOut: desiredPayment.token,
            fee: 500 * 6, // TODO: Think about how to intelligently pick the
                // right pool.
            recipient: context.castOfCharacters.fulfiller, // TODO: handle
                // fulfiller/sidecar/adapter choice gracefully,
            deadline: block.timestamp + 1,
            amountOut: desiredPayment.amount,
            amountInMaximum: offeredEthAmount,
            sqrtPriceLimitX96: 0 // TODO: figure out what this is.
         });

        return abi.encodeWithSelector(
            ISwapRouter.exactOutputSingle.selector, params
        );

        // TODO: look into refunds
    }

    function getPayload_BuyOfferedEtherWithERC20(
        OrderContext calldata context,
        uint256 desiredEthAmount,
        Item20 memory offeredPayment
    ) external view override returns (OrderPayload memory execution) {
        if (!context.listOnChain) {
            _notImplemented();
        }

        // // This is just a no op to avoid errors. The idea is just to use the
        // // actual DAI/WETH pool for testing.
        // execution.submitOrder = Call({
        //     target: address(0),
        //     allowFailure: false,
        //     value: 0,
        //     callData: ""
        // });

        execution.executeOrder = Call(
            address(uniswapV3),
            false,
            0,
            getCalldataToBuyOfferedEtherWithERC20(
                context, desiredEthAmount, offeredPayment
            )
        );
    }

    function getCalldataToBuyOfferedEtherWithERC20(
        OrderContext calldata context,
        uint256 desiredEthAmount,
        Item20 memory offeredPayment
    ) public view returns (bytes memory) {
        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter
            .ExactOutputSingleParams({
            tokenIn: offeredPayment.token,
            tokenOut: address(weth),
            fee: 500 * 6,
            recipient: context.castOfCharacters.fulfiller,
            deadline: block.timestamp + 1,
            amountOut: desiredEthAmount,
            amountInMaximum: offeredPayment.amount,
            sqrtPriceLimitX96: 0
        });

        return abi.encodeWithSelector(
            ISwapRouter.exactOutputSingle.selector, params
        );

        // TODO: look into refunds
    }
}
