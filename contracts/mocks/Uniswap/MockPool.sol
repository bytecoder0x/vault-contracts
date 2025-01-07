// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

contract MockPool {
    struct Slot0 {
        // the current price
        uint160 sqrtPriceX96;
        // the current tick
        int24 tick;
        // the most-recently updated index of the observations array
        uint16 observationIndex;
        // the current maximum number of observations that are being stored
        uint16 observationCardinality;
        // the next maximum number of observations to store, triggered in observations.write
        uint16 observationCardinalityNext;
        // the current protocol fee as a percentage of the swap fee taken on withdrawal
        // represented as an integer denominator (1/x)%
        uint8 feeProtocol;
        // whether the pool is locked
        bool unlocked;
    }

    struct Observation {
        // the block timestamp of the observation
        uint32 blockTimestamp;
        // the tick accumulator, i.e. tick * time elapsed since the pool was first initialized
        int56 tickCumulative;
        // the seconds per liquidity, i.e. seconds elapsed / max(1, liquidity) since the pool was first initialized
        uint160 secondsPerLiquidityCumulativeX128;
        // whether or not the observation is initialized
        bool initialized;
    }

    Slot0 public slot0;
    uint128 public poolLiquidity;
    address public token0;
    address public token1;
    Observation[65535] public observations;

    constructor(address _token0, address _token1) {
        token0 = _token0;
        token1 = _token1;
        slot0.observationCardinality = 2;
        slot0.observationIndex = 1;

        observations[0] = Observation(uint32(block.timestamp - 100), 0, 0, true);
        observations[1] = Observation(uint32(block.timestamp - 50), 0, 0, true);
    }

    function observe(uint32[] calldata)
        external
        pure
        returns (int56[] memory, uint160[] memory)
    {
        int56[] memory tickCumulatives = new int56[](2);
        uint160[] memory secondsPerLiquidityCumulativeX128s = new uint160[](2);

        tickCumulatives[0] = 6932;
        tickCumulatives[1] = 6932;

        secondsPerLiquidityCumulativeX128s[0] = 0;
        secondsPerLiquidityCumulativeX128s[1] = 0;

        return (tickCumulatives, secondsPerLiquidityCumulativeX128s);
    }

    function updateObservationTime(uint observationIndex, uint32 blockTimestamp) external {
        observations[observationIndex].blockTimestamp = blockTimestamp;
    }

    function updateObservationCardinality(uint16 observationCardinality) external {
        slot0.observationCardinality = observationCardinality;
    }
}