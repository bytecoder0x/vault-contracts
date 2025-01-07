// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

contract MockQuoterV2 {
    struct QuoteExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint24 fee;
        uint160 sqrtPriceLimitX96;
    }

    uint256 PRECISION = 1 ether;
    mapping(uint24 => uint256) public feeToRate;
    bool public shouldRevert;

    constructor() {
        feeToRate[500] = 1 ether;     // 0.05% fee
        feeToRate[3000] = 0.1 ether;  // 0.3% fee
        feeToRate[10000] = 0.2 ether; // 1% fee
    }

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function quoteExactInputSingle(QuoteExactInputSingleParams memory params) external view returns (
        uint256 amountOut,
        uint160 sqrtPriceX96After,
        uint32 initializedTicksCrossed,
        uint256 gasEstimate
    ) {
        if (shouldRevert) {
            revert("Mock quote reverted");
        }
        uint256 currentRate = feeToRate[params.fee];

        amountOut = params.amountIn * currentRate / PRECISION;
        sqrtPriceX96After = uint160(2 ** 96);
        initializedTicksCrossed = 1;
        gasEstimate = 100_000;

        return (amountOut, sqrtPriceX96After, initializedTicksCrossed, gasEstimate);
    }
}