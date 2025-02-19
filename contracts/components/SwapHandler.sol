// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IUniswapV2Router01} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IQuoterV2} from "@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";

import {ISwapHandler} from "../interfaces/common/ISwapHandler.sol";

abstract contract SwapHandler is Initializable, ISwapHandler {
    uint256 public constant BASIS_POINTS = 100_00;
    uint256 public constant SLIPPAGE_MULTIPLIER = BASIS_POINTS - 2_00; // slippage == 2%
    uint256 public constant TRANSACTION_TIMEOUT = 15 minutes;

    IUniswapV2Router01 public ROUTER_V2;
    ISwapRouter public ROUTER_V3;
    IQuoterV2 public QUOTER;

    function __SwapHandler_init(address _routerV2, address _routerV3, address _quoter) internal onlyInitializing {
        if (_routerV2 == address(0)) revert RouterV2MustBeContract();
        if (_routerV3 == address(0)) revert RouterV3MustBeContract();
        if (_quoter == address(0)) revert QuoterMustBeContract();

        ROUTER_V2 = IUniswapV2Router01(_routerV2);
        ROUTER_V3 = ISwapRouter(_routerV3);
        QUOTER = IQuoterV2(_quoter);
    }

    function _swap(
        uint256 _amountIn,
        address _recipient,
        address _tokenOut,
        address _tokenIn
    ) internal returns (uint256 amountOut) {
        (Swap decision, uint24 fee, uint256 maxAmount) = _decider(
            _amountIn,
            _tokenIn,
            _tokenOut
        );

        if (decision == Swap.V2) {
            address[] memory path = new address[](2);
            path[0] = _tokenIn;
            path[1] = _tokenOut;

            amountOut = _swapV2(path, _amountIn, maxAmount, _recipient);
        } else {
            amountOut = _swapV3(
                _tokenIn,
                _tokenOut,
                fee,
                _amountIn,
                maxAmount,
                _recipient
            );
        }
    }

    function _decider(uint256 _amountIn, address _tokenIn, address _tokenOut) private returns (Swap, uint24, uint256) {
        uint256 amount1 = _getQuote(_tokenIn, _tokenOut, _amountIn, 5_00); //fee 0.05%
        uint256 amount2 = _getQuote(_tokenIn, _tokenOut, _amountIn, 3_000); //fee 0.3%
        uint256 amount3 = _getQuote(_tokenIn, _tokenOut, _amountIn, 10_000); //fee 1%
        uint256 amount4;

        address[] memory path = new address[](2);
        path[0] = _tokenIn;
        path[1] = _tokenOut;

        try ROUTER_V2.getAmountsOut(_amountIn, path) returns (uint256[] memory result) {
            amount4 = result[1];
        } catch {
            amount4 = 0;
        }
        
        uint256 maxAmount = amount1;
        uint24 fee = 5_00;
        Swap decision = Swap.V3_500;

        if (amount2 > maxAmount) {
            maxAmount = amount2;
            decision = Swap.V3_3000;
            fee = 30_00;
        }

        if (amount3 > maxAmount) {
            maxAmount = amount3;
            decision = Swap.V3_10000;
            fee = 10_000;
        }

        if (amount4 > maxAmount) {
            maxAmount = amount4;
            decision = Swap.V2;
            fee = 0;
        }

        return (decision, fee, maxAmount);
    }

    function _getQuote(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        uint24 _fee
    ) private returns (uint256) {
        uint256 amountOut;

        IQuoterV2.QuoteExactInputSingleParams memory params = IQuoterV2
            .QuoteExactInputSingleParams({
                tokenIn: _tokenIn,
                tokenOut: _tokenOut,
                amountIn: _amountIn,
                fee: _fee,
                sqrtPriceLimitX96: 0
            });

        try QUOTER.quoteExactInputSingle(params) returns (uint256 out, uint160 , uint32, uint256) {
            amountOut = out;
        } catch {
            amountOut = 0;
        }
        
        return amountOut;
    }

    function _swapV2(
        address[] memory _path,
        uint256 _amountIn,
        uint256 _amountOut,
        address _recipient
    ) private returns (uint256 amountOut) {
        uint256 amountOutMin = (_amountOut * SLIPPAGE_MULTIPLIER) / BASIS_POINTS;
        uint256 deadline = block.timestamp + TRANSACTION_TIMEOUT;

        IERC20Upgradeable(_path[0]).approve(address(ROUTER_V2), _amountIn);
        uint256[] memory amounts = ROUTER_V2.swapExactTokensForTokens(
            _amountIn,
            amountOutMin,
            _path,
            _recipient,
            deadline
        );

        amountOut = amounts[amounts.length - 1];
    }

    function _swapV3(
        address _tokenIn,
        address _tokenOut,
        uint24 _fee,
        uint256 _amountIn,
        uint256 _amountOut,
        address _recipient
    ) private returns (uint256 amountOut) {
        uint256 amountOutMin = (_amountOut * SLIPPAGE_MULTIPLIER) / BASIS_POINTS;
        uint256 deadline = block.timestamp + TRANSACTION_TIMEOUT;

        IERC20Upgradeable(_tokenIn).approve(address(ROUTER_V3), _amountIn);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: _tokenIn,
                tokenOut: _tokenOut,
                fee: _fee,
                recipient: _recipient,
                deadline: deadline,
                amountIn: _amountIn,
                amountOutMinimum: amountOutMin,
                sqrtPriceLimitX96: 0
            });

        amountOut = ROUTER_V3.exactInputSingle(params);
    }
}