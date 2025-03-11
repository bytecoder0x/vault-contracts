// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

interface IScoringManager {
    struct PerformanceData {
        uint256 reputationRatio;
        uint256 financialHealthRatio;
    }

    error AdminCannotBeZeroAddress();
    error ThresholdCapitalCannotBeZero();
    error ThresholdCollateralCannotBeZero();
    error InvalidReputationRatio();
    error InvalidFinancialHealthRatio();
    error InvalidMarketConditionRatio();
    error InvalidDataLength();
    error ThresholdCapitalCannotBeTheSame();
    error ThresholdCollateralCannotBeTheSame();
    error ReputationRatioCannotBeTheSame();
    error FinancialHealthRatioCannotBeTheSame();
    error MarketConditionRatioCannotBeTheSame();
    error EntityCannotBeZeroAddress();
    error PerformanceDataAlreadySet();
    error PoolSizeWeightCannotBeZero();
    error PoolSizeWeightCannotBeGreaterThanMaxRatio();
    error PoolSizeWeightCannotBeTheSame();
    error DecreaseSuccessFactorCannotBeZero();
    error DecreaseSuccessFactorCannotBeGreaterThanMaxRatio();
    error DecreaseSuccessFactorCannotBeTheSame();

    event ThresholdCapitalUpdated(uint256 indexed thresholdCapital);
    event ThresholdCollateralUpdated(uint256 indexed thresholdCollateral);
    event MarketConditionRatioUpdated(uint256 indexed marketConditionRatio);
    event PoolSizeWeightUpdated(uint24 poolSizeWeight);
    event DecreaseSuccessFactorUpdated(uint24 decreaseSuccessFactor);
    event PerformanceDataUpdated(address indexed entity, uint256 reputationRatio, uint256 financialHealthRatio);

    function setDecreaseSuccessFactor(uint24 _decreaseSuccessFactor) external;
    function setPoolSizeWeight(uint24 _poolSizeWeight) external;
    function setPerformanceDataBatch(address[] calldata _entities, uint256[] calldata _reputationRatios, uint256[] calldata _financialHealthRatios) external;
    function setPerformanceData(address _entity, uint256 _reputationRatio, uint256 _financialHealthRatio) external;
    function setThresholdCollateral(uint256 _thresholdCollateral) external;
    function setThresholdCapital(uint256 _thresholdCapital) external;
    function setMarketConditionRatio(uint256 _marketConditionRatio) external;
}

