// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

interface IScoring {
    struct PerformanceData {
        uint256 reputationRatio;
        uint256 financialHealthRatio;
    }

    error AdminCannotBeZeroAddress();
    error ThresholdCapitalCannotBeZero();
    error ThresholdCollateralCannotBeZero();
    error TreasuryMustBeContract();
    error VaultFactoryMustBeContract();
    error GoilTokenMustBeContract();
    error LicenseMustBeContract();
    error InvalidReputationRatio();
    error InvalidFinancialHealthRatio();
    error InvalidMarketConditionRatio();
    error ThresholdCapitalCannotBeTheSame();
    error ThresholdCollateralCannotBeTheSame();
    error ReputationRatioCannotBeTheSame();
    error FinancialHealthRatioCannotBeTheSame();
    error MarketConditionRatioCannotBeTheSame();
    error PoolSizeCannotBeGreaterThanMaxPoolSize();
    error EntityCannotBeZeroAddress();
    error PerformanceDataAlreadySet();
    error LicenseIsNotPending();
    error IncorrectWeights();
    error OnlyVaultFactory();
    error OnlyAdminOrLicense();

    event ThresholdCapitalUpdated(uint256 indexed thresholdCapital);
    event ThresholdCollateralUpdated(uint256 indexed thresholdCollateral);
    event MarketConditionRatioUpdated(uint256 indexed marketConditionRatio);
    event EntityScoreUpdated(address indexed entity, uint256 newScore);
    event PerformanceDataUpdated(address indexed entity, uint256 reputationRatio, uint256 financialHealthRatio);

    function updateEntityScore() external;
    function setInitialScore(address _entity) external;
    function setThresholdCollateral(uint256 _thresholdCollateral) external;
    function setThresholdCapital(uint256 _thresholdCapital) external;
    function setMarketConditionRatio(uint256 _marketConditionRatio) external;
    function getIsReadyToSetInitialScore(address _entity) external view returns (bool);
    function getMaxPoolSize(address _entity) external view returns (uint256 maxPoolSize);
}