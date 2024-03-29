// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {
    SetupCall,
    TestOrderPayload,
    TestOrderContext,
    CallParameters,
    Item20,
    Item721,
    Item1155
} from "./utils/Types.sol";

import { ConsiderationInterface as ISeaport } from
    "seaport-types/interfaces/ConsiderationInterface.sol";

import { AdapterHelperLib } from "../src/lib/AdapterHelperLib.sol";

import { FlashloanOffererInterface } from
    "../src/interfaces/FlashloanOffererInterface.sol";

import { GenericAdapterInterface } from
    "../src/interfaces/GenericAdapterInterface.sol";

import { GenericAdapterSidecarInterface } from
    "../src/interfaces/GenericAdapterSidecarInterface.sol";

import { BasicOrderParameters } from
    "seaport-types/lib/ConsiderationStructs.sol";
import { CastOfCharacters } from "../src/lib/AdapterHelperLib.sol";

abstract contract BaseMarketConfig {
    FlashloanOffererInterface testFlashloanOfferer;
    GenericAdapterInterface testAdapter;
    GenericAdapterSidecarInterface testSidecar;

    /**
     * @dev Market name used in results
     */
    function name() external pure virtual returns (string memory);

    function market() public view virtual returns (address);

    /**
     * @dev Address that should be approved for nft tokens (ERC721 and ERC1155).
     *      Should be set during beforeAllPrepareMarketplace`.
     */
    address public sellerNftApprovalTarget;
    address public buyerNftApprovalTarget;

    /**
     * @dev Address that should be approved for ERC1155 tokens. Only set if
     *      different than ERC721 which is defined above. Set during
     *      `beforeAllPrepareMarketplace`.
     */
    address public sellerErc1155ApprovalTarget;
    address public buyerErc1155ApprovalTarget;

    /**
     * @dev Address that should be approved for erc20 tokens. Should be set
     *      during `beforeAllPrepareMarketplace`.
     */
    address public sellerErc20ApprovalTarget;
    address public buyerErc20ApprovalTarget;

    ISeaport internal constant seaport =
        ISeaport(0x00000000000000ADc04C56Bf30aC9d3c0aAF14dC);

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    /**
     * @dev Get calldata to call from test prior to starting tests
     *      (e.g. used by wyvern to create proxies)
     *
     * @ param seller The seller address used for testing the marketplace
     * @ param buyer  The buyer address used for testing the marketplace
     *
     * @return From address, to address, and calldata
     */
    function beforeAllPrepareMarketplaceCall(
        CastOfCharacters calldata,
        address[] calldata,
        address[] calldata
    ) external virtual returns (SetupCall[] memory) {
        SetupCall[] memory empty = new SetupCall[](0);
        return empty;
    }

    /**
     * @dev Final setup prior to starting tests
     * @ param seller The seller address used for testing the marketplace
     * @ param buyer The buyer address used for testing the marketplace
     */
    function beforeAllPrepareMarketplace(address, address buyer)
        external
        virtual;

    /*//////////////////////////////////////////////////////////////
                        Test Payload Calls
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Get call parameters to execute an order selling a 721 token for
     * Ether.
     *   If `context.listOnChain` is true and marketplace does not support
     * on-chain
     *   listing, this function must revert with NotImplemented.
     * @ param context Order context, including the buyer and seller and whether
     * the
     *   order should be listed on chain.
     * @ param nft Address and ID for ERC721 token to be sold.
     * @ param ethAmount Amount of Ether to be received for the NFT.
     */
    function getPayload_BuyOfferedERC721WithEther(
        TestOrderContext calldata,
        Item721 calldata,
        uint256
    ) external virtual returns (TestOrderPayload memory) {
        _notImplemented();
    }

    /**
     * @dev Get call parameters to execute an order selling an 1155 token for
     * Ether.
     *   If `context.listOnChain` is true and marketplace does not support
     * on-chain
     *   listing, this function must revert with NotImplemented.
     * @ param context Order context, including the buyer and seller and whether
     * the
     *  order should be listed on chain.
     * @ param nft Address, ID and amount for ERC1155 token to be sold.
     * @ param ethAmount Amount of Ether to be received for the NFT.
     */
    function getPayload_BuyOfferedERC1155WithEther(
        TestOrderContext calldata,
        Item1155 calldata,
        uint256
    ) external view virtual returns (TestOrderPayload memory) {
        _notImplemented();
    }

    /**
     * @dev Get call parameters to execute an order selling a 721 token for an
     * ERC20.
     *   If `context.listOnChain` is true and marketplace does not support
     * on-chain
     *   listing, this function must revert with NotImplemented.
     * @ param context Order context, including the buyer and seller and whether
     * the
     *  order should be listed on chain.
     * @ param nft Address and ID of 721 token to be sold.
     * @ param erc20 Address and amount for ERC20 to be received for nft.
     */
    function getPayload_BuyOfferedERC721WithERC20(
        TestOrderContext calldata,
        Item721 calldata,
        Item20 calldata
    ) external virtual returns (TestOrderPayload memory) {
        _notImplemented();
    }

    function getComponents_BuyOfferedERC721WithERC20(
        address,
        Item721 calldata,
        Item20 calldata
    ) external view virtual returns (BasicOrderParameters memory) {
        _notImplemented();
    }

    /**
     * @dev Get call parameters to execute an order selling a 721 token for
     * WETH.
     *   If `context.listOnChain` is true and marketplace does not support
     * on-chain
     *   listing, this function must revert with NotImplemented.
     * @ param context Order context, including the buyer and seller and whether
     * the
     *  order should be listed on chain.
     * @ param nft Address and ID of 721 token to be sold.
     * @ param erc20 Address and amount for WETH to be received for nft.
     */
    function getPayload_BuyOfferedERC721WithWETH(
        TestOrderContext calldata,
        Item721 calldata,
        Item20 calldata
    ) external virtual returns (TestOrderPayload memory) {
        _notImplemented();
    }

    function getPayload_BuyOfferedERC721WithBETH(
        TestOrderContext calldata, /* context */
        Item721 calldata, /* nft */
        Item20 calldata /* erc20*/
    ) external virtual returns (TestOrderPayload memory /*execution*/ ) {
        _notImplemented();
    }

    /**
     * @dev Get call parameters to execute an order selling an 1155 token for an
     * ERC20.
     *   If `context.listOnChain` is true and marketplace does not support
     * on-chain
     *   listing, this function must revert with NotImplemented.
     * @ param context Order context, including the buyer and seller and whether
     * the
     *  order should be listed on chain.
     * @ param nft Address, ID and amount for ERC1155 token to be sold.
     * @ param erc20 Address and amount for ERC20 to be received for nft.
     */
    function getPayload_BuyOfferedERC1155WithERC20(
        TestOrderContext calldata,
        Item1155 calldata,
        Item20 calldata
    ) external view virtual returns (TestOrderPayload memory) {
        _notImplemented();
    }

    /**
     * @dev Get call parameters to execute an order selling an ERC20 token for
     * an ERC721.
     *   If `context.listOnChain` is true and marketplace does not support
     * on-chain
     *   listing, this function must revert with NotImplemented.
     * @ param context Order context, including the buyer and seller and whether
     * the
     *  order should be listed on chain.
     * @ param erc20 Address and amount for ERC20 to be sold.
     * @ param nft Address and ID for 721 token to be received for ERC20.
     */
    function getPayload_BuyOfferedERC20WithERC721(
        TestOrderContext calldata,
        Item20 calldata,
        Item721 calldata
    ) external virtual returns (TestOrderPayload memory) {
        _notImplemented();
    }

    /**
     * @dev Get call parameters to execute an order selling WETH for an ERC721.
     *   If `context.listOnChain` is true and marketplace does not support
     * on-chain
     *   listing, this function must revert with NotImplemented.
     * @ param context Order context, including the buyer and seller and whether
     * the
     *  order should be listed on chain.
     * @ param erc20 Address and amount of WETH to be sold.
     * @ param nft Address and ID for 721 token to be received for WETH.
     */
    function getPayload_BuyOfferedWETHWithERC721(
        TestOrderContext calldata,
        Item20 calldata,
        Item721 calldata
    ) external virtual returns (TestOrderPayload memory) {
        _notImplemented();
    }

    function getPayload_BuyOfferedBETHWithERC721(
        TestOrderContext calldata, /* context */
        Item20 calldata, /* erc20 */
        Item721 calldata /* nft */
    ) external virtual returns (TestOrderPayload memory /* execution */ ) {
        _notImplemented();
    }

    /**
     * @dev Get call parameters to execute an order selling an ERC20 token for
     * an ERC1155.
     *   If `context.listOnChain` is true and marketplace does not support
     * on-chain
     *   listing, this function must revert with NotImplemented.
     * @ param context Order context, including the buyer and seller and whether
     * the
     *  order should be listed on chain.
     * @ param erc20 Address and amount for ERC20 to be sold.
     * @ param nft Address, ID and amount for 1155 token to be received for
     * ERC20.
     */
    function getPayload_BuyOfferedERC20WithERC1155(
        TestOrderContext calldata,
        Item20 calldata,
        Item1155 calldata
    ) external view virtual returns (TestOrderPayload memory) {
        _notImplemented();
    }

    /**
     * @dev Get call parameters to execute an order selling an ERC721 token for
     * an ERC1155.
     *   If `context.listOnChain` is true and marketplace does not support
     * on-chain
     *   listing, this function must revert with NotImplemented.
     * @ param context Order context, including the buyer and seller and whether
     * the
     *  order should be listed on chain.
     * @ param sellNft Address and ID of 721 token to be sold.
     * @ param buyNft Address, ID and amount of 1155 token to be received for
     * ERC721.
     */
    function getPayload_BuyOfferedERC721WithERC1155(
        TestOrderContext calldata,
        Item721 calldata,
        Item1155 calldata
    ) external view virtual returns (TestOrderPayload memory) {
        _notImplemented();
    }

    /**
     * @dev Get call parameters to execute an order selling an ERC1155 token for
     * an ERC721.
     *   If `context.listOnChain` is true and marketplace does not support
     * on-chain
     *   listing, this function must revert with NotImplemented.
     * @ param context Order context, including the buyer and seller and whether
     * the
     *  order should be listed on chain.
     * @ param sellNft Address and ID of 1155 token to be sold.
     * @ param buyNft Address, ID and amount of 721 token to be received for
     * ERC1155.
     */
    function getPayload_BuyOfferedERC1155WithERC721(
        TestOrderContext calldata,
        Item1155 calldata,
        Item721 calldata
    ) external view virtual returns (TestOrderPayload memory) {
        _notImplemented();
    }

    /**
     * @dev Get call parameters to execute an order selling a 721 token for
     * Ether with one fee recipient.
     *   If `context.listOnChain` is true and marketplace does not support
     * on-chain
     *   listing, this function must revert with NotImplemented.
     * @ param context Order context, including the buyer and seller and whether
     * the
     *  order should be listed on chain.
     * @ param nft Address and ID for ERC721 token to be sold.
     * @ param priceEthAmount Amount of Ether to be received for the NFT.
     * @ param feeRecipient Address to send fee to.
     * @ param feeEthAmount Amount of Ether to send for fee.
     */
    function getPayload_BuyOfferedERC721WithEtherOneFeeRecipient(
        TestOrderContext calldata,
        Item721 memory,
        uint256,
        address,
        uint256
    ) external virtual returns (TestOrderPayload memory) {
        _notImplemented();
    }

    /**
     * @dev Get call parameters to execute an order selling a 721 token for
     * Ether with two fee recipients.
     *   If `context.listOnChain` is true and marketplace does not support
     * on-chain
     *   listing, this function must revert with NotImplemented.
     * @ param context Order context, including the buyer and seller and whether
     * the
     *  order should be listed on chain.
     * @ param nft Address and ID for ERC721 token to be sold.
     * @ param priceEthAmount Amount of Ether to be received for the NFT.
     * @ param feeRecipient1 Address to send first fee to.
     * @ param feeEthAmount1 Amount of Ether to send for first fee.
     * @ param feeRecipient2 Address to send second fee to.
     * @ param feeEthAmount2 Amount of Ether to send for second fee.
     */
    function getPayload_BuyOfferedERC721WithEtherTwoFeeRecipient(
        TestOrderContext calldata,
        Item721 memory,
        uint256,
        address,
        uint256,
        address,
        uint256
    ) external view virtual returns (TestOrderPayload memory) {
        _notImplemented();
    }

    /**
     * @dev Get call parameters to execute an order selling many 721 tokens for
     * Ether.
     *   If `context.listOnChain` is true and marketplace does not support
     * on-chain
     *   listing, this function must revert with NotImplemented.
     * @ param context Order context, including the buyer and seller and whether
     * the
     *  order should be listed on chain.
     * @ param nfts Array of Address and ID for ERC721 tokens to be sold.
     * @ param ethAmount Amount of Ether to be received for the NFT.
     */
    function getPayload_BuyOfferedManyERC721WithEther(
        TestOrderContext calldata,
        Item721[] calldata,
        uint256
    ) external virtual returns (TestOrderPayload memory) {
        _notImplemented();
    }

    /**
     * @dev Get call parameters to execute an order "sweeping the floor" buy
     * filling 10 distinct
     *   ERC-721->ETH orders at once. Same seller on each order. If the market
     * does not support the
     *   order type, must revert with NotImplemented.
     * @ param contexts Array of contexts for each order
     * @ param nfts Array of NFTs for each order
     * @ param ethAmounts Array of Ether emounts to be received for the NFTs in
     * each order
     */
    function getPayload_BuyOfferedManyERC721WithEtherDistinctOrders(
        TestOrderContext[] calldata,
        Item721[] calldata,
        uint256[] calldata
    ) external view virtual returns (TestOrderPayload memory) {
        _notImplemented();
    }

    /**
     * @dev Get call parameters to execute an order "sweeping the floor" buy
     * filling 10 distinct
     *   ERC-721->ERC-20 orders at once. Same seller on each order. If the
     * market does not support the
     *   order type, must revert with NotImplemented.
     * @ param contexts Array of contexts for each order
     * @ param erc20Address The erc20 address to use across orders
     * @ param nfts Array of NFTs for each order
     * @ param erc20Amounts Array of Erc20 amounts to be received for the NFTs
     * in each order
     */
    function getPayload_BuyOfferedManyERC721WithErc20DistinctOrders(
        TestOrderContext[] calldata,
        address,
        Item721[] calldata,
        uint256[] calldata
    ) external view virtual returns (TestOrderPayload memory) {
        _notImplemented();
    }

    /**
     * @dev Get call parameters to execute an order "sweeping the floor" buy
     * filling 10 distinct
     *   ERC-721->WETH orders at once. Same seller on each order. If the market
     * does not support the
     *   order type, must revert with NotImplemented.
     * @ param contexts Array of contexts for each order
     * @ param erc20Address The WETH address to use across orders
     * @ param nfts Array of NFTs for each order
     * @ param erc20Amounts Array of WETH amounts to be received for the NFTs in
     * each order
     */
    function getPayload_BuyOfferedManyERC721WithWETHDistinctOrders(
        TestOrderContext[] calldata,
        address,
        Item721[] calldata,
        uint256[] calldata
    ) external view virtual returns (TestOrderPayload memory) {
        _notImplemented();
    }

    /**
     * @dev Get call parameters to execute a match orders style execution. This
     * execution
     *   involves arbitrary number of orders in the pattern A -> B -> C -> A.
     * Where each arrow
     *   indicates an individual order. There orders are not fulfillable
     * individually,
     *   however, they are when executed atomically.
     * @ param contexts Array of contexts for each order
     * @ param nfts Array of NFTs in the order A, B, C...
     */
    function getPayload_MatchOrders_ABCA(
        TestOrderContext[] calldata,
        Item721[] calldata
    ) external view virtual returns (TestOrderPayload memory) {
        _notImplemented();
    }

    function getPayload_MatchOrders_Aggregate(
        TestOrderContext[] calldata,
        Item721[] calldata
    ) external view virtual returns (TestOrderPayload memory) {
        _notImplemented();
    }

    function getComponents_BuyOfferedERC1155WithERC20(
        address,
        Item1155 calldata,
        Item20 memory
    ) public view virtual returns (BasicOrderParameters memory) {
        _notImplemented();
    }

    function getComponents_BuyOfferedERC20WithERC1155(
        address,
        Item20 calldata,
        Item1155 calldata
    ) external view virtual returns (BasicOrderParameters memory) {
        _notImplemented();
    }

    /*//////////////////////////////////////////////////////////////
                          Helpers
    //////////////////////////////////////////////////////////////*/
    ITestRunner private _tester;

    error NotImplemented();

    /**
     * @dev Revert if the type of requested order is impossible
     * to execute for a marketplace.
     */
    function _notImplemented() internal pure {
        revert NotImplemented();
    }

    constructor() {
        _tester = ITestRunner(msg.sender);
    }

    /**
     * @dev Request a signature from the testing contract.
     */
    function _sign(address signer, bytes32 digest)
        internal
        view
        returns (uint8, bytes32, bytes32)
    {
        return _tester.signDigest(signer, digest);
    }
}

interface ITestRunner {
    function signDigest(address signer, bytes32 digest)
        external
        view
        returns (uint8, bytes32, bytes32);
}
