// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockRouterV2 {
    uint256 public PRECISION = 1 ether; 
    uint256 public RATE = 0.5 ether;
    
    function setRate(uint256 _rate) external {
        RATE = _rate;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        require(block.timestamp <= deadline, "UniswapV2Router: EXPIRED");
        require(path.length >= 2, "UniswapV2Router: INVALID_PATH");
        
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        
        uint256 amountOut = amountIn * RATE / PRECISION;
        if(amountOut < amountOutMin) revert("UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT");
        
        IERC20(path[path.length - 1]).transfer(to, amountOut);

        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        amounts[path.length - 1] = amountOut;
        
        return amounts;
    }

    function getAmountsOut(uint256 amountIn, address[] calldata path) 
        external 
        view  
        returns (uint256[] memory amounts) 
    {
        if(path.length < 2) revert("UniswapV2Router: INVALID_PATH");
        
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        amounts[path.length - 1] = amountIn * RATE / PRECISION;
        
        return amounts;
    }
}