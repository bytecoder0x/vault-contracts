// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

interface IScoring {
    // Errors
    error AdminCannotBeZeroAddress();
    error ThresholdCapitalCannotBeZero();
    error ThresholdCollateralCannotBeZero();
    error VaultFactoryMustBeContract();
    error GoilTokenMustBeContract();
    error InvalidReputationRatio();
    error InvalidFinancialHealthRatio();
    error InvalidMarketConditionRatio();
    error ThresholdCapitalCannotBeTheSame();
    error ThresholdCollateralCannotBeTheSame();
    error ReputationRatioCannotBeTheSame();
    error FinancialHealthRatioCannotBeTheSame();
    error MarketConditionRatioCannotBeTheSame();
    error PoolSizeCannotBeGreaterThanMaxPoolSize();
    error IncorrectWeights();
    error OnlyVaultFactory();

    event ThresholdCapitalUpdated(uint256 indexed thresholdCapital);
    event ThresholdCollateralUpdated(uint256 indexed thresholdCollateral);
    event ReputationRatioUpdated(uint256 indexed reputationRatio);
    event FinancialHealthRatioUpdated(uint256 indexed financialHealthRatio);
    event MarketConditionRatioUpdated(uint256 indexed marketConditionRatio);
    event EntityScoreUpdated(address indexed entity, uint256 indexed newScore);

    function updateEntityScore(address _entity, uint256 _poolSize, bool _isFail) external;
    function getMaxPoolSize(address _entity) external view returns (uint256 maxPoolSize);
    function getInitialScore(address _entity) external view returns (uint256 score);
    function getPenalty(address _entity) external view returns (uint256 penalty);
    function getHistoricalPerformance(address _entity) external view returns (uint256 historicalPerformance);
    function setThresholdCollateral(uint256 _thresholdCollateral) external;
    function setThresholdCapital(uint256 _thresholdCapital) external;
    function setReputationRatio(uint256 _reputationRatio) external;
    function setFinancialHealthRatio(uint256 _financialHealthRatio) external;
    function setMarketConditionRatio(uint256 _marketConditionRatio) external;
}