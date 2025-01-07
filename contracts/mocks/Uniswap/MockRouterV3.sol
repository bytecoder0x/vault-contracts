// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockRouterV3 {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    uint256 public RATE = 1 ether;
    uint256 public PRECISION = 1 ether;
    
    constructor() { }

    function setRate(uint256 _rate) external {
        RATE = _rate;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut) {
        IERC20(params.tokenIn).transferFrom(
            msg.sender,
            address(this),
            params.amountIn
        );
        
        amountOut = params.amountIn * RATE / PRECISION;
        
        if (amountOut < params.amountOutMinimum) {
            revert("Insufficient output amount");
        }
        
        IERC20(params.tokenOut).transfer(params.recipient, amountOut);
        
        return amountOut;
    }
}