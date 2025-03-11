// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IScoringManager} from "../../interfaces/vaults/components/IScoringManager.sol";

contract ScoringManager is AccessControl, IScoringManager {
    bytes32 public constant SCORING_MANAGER_ROLE = keccak256("SCORING_MANAGER_ROLE");

    uint24 public constant MAX_RATIO = 100_000;

    // if entity repay after liquidation, success rate based on paid amount will be multiplied by this factor
    uint24 public decreaseSuccessFactor = 80_000; // firstly is 0.8 (with precision 100_000)
    uint24 public poolSizeWeight = 10_000; // 0.1 (10%) its means that score cannot be increased by more than 10%

    uint256 public thresholdCapital;
    uint256 public thresholdCollateral;
    uint256 public marketConditionRatio;

    mapping(address => PerformanceData) public performanceData; // reputation ratio and financial health ratio

    constructor(
        address _admin,
        uint256 _thresholdCapital,
        uint256 _thresholdCollateral,
        uint256 _marketConditionRatio
    ) {
        if (_admin == address(0)) revert AdminCannotBeZeroAddress();
        if (_thresholdCapital == 0) revert ThresholdCapitalCannotBeZero();
        if (_thresholdCollateral == 0) revert ThresholdCollateralCannotBeZero();
        if (_marketConditionRatio > MAX_RATIO || _marketConditionRatio == 0) revert InvalidMarketConditionRatio();

        thresholdCapital = _thresholdCapital;
        thresholdCollateral = _thresholdCollateral;
        marketConditionRatio = _marketConditionRatio;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(SCORING_MANAGER_ROLE, _admin);
    }
    
    function setPerformanceData(
        address _entity,
        uint256 _reputationRatio,
        uint256 _financialHealthRatio
    ) public virtual onlyRole(SCORING_MANAGER_ROLE) {
        uint256 reputationRatio = performanceData[_entity].reputationRatio;
        uint256 financialHealthRatio = performanceData[_entity].financialHealthRatio;

        if (_entity == address(0)) revert EntityCannotBeZeroAddress();
        if (reputationRatio != 0 || financialHealthRatio != 0) revert PerformanceDataAlreadySet();
        if (_reputationRatio > MAX_RATIO || _reputationRatio == 0) revert InvalidReputationRatio();
        if (_financialHealthRatio > MAX_RATIO || _financialHealthRatio == 0) revert InvalidFinancialHealthRatio();

        performanceData[_entity] = PerformanceData({
            reputationRatio: _reputationRatio,
            financialHealthRatio: _financialHealthRatio
        });

        emit PerformanceDataUpdated(_entity, _reputationRatio, _financialHealthRatio);
    }

    function setPerformanceDataBatch(
        address[] calldata _entities,
        uint256[] calldata _reputationRatios,
        uint256[] calldata _financialHealthRatios
    ) public onlyRole(SCORING_MANAGER_ROLE) {
        if (_entities.length != _reputationRatios.length || _entities.length != _financialHealthRatios.length) {
            revert InvalidDataLength();
        }

        uint256 entitiesLength = _entities.length;
        for (uint256 i = 0; i < entitiesLength; ) {
            setPerformanceData(_entities[i], _reputationRatios[i], _financialHealthRatios[i]);
            unchecked {
                i++;
            }
        }
    }

    function setDecreaseSuccessFactor(uint24 _decreaseSuccessFactor) external onlyRole(SCORING_MANAGER_ROLE) {
        if (_decreaseSuccessFactor > MAX_RATIO) revert DecreaseSuccessFactorCannotBeGreaterThanMaxRatio();
        if (decreaseSuccessFactor == _decreaseSuccessFactor) revert DecreaseSuccessFactorCannotBeTheSame();
        if (_decreaseSuccessFactor == 0) revert DecreaseSuccessFactorCannotBeZero();

        decreaseSuccessFactor = _decreaseSuccessFactor;
        emit DecreaseSuccessFactorUpdated(_decreaseSuccessFactor);
    }

    function setPoolSizeWeight(uint24 _poolSizeWeight) external onlyRole(SCORING_MANAGER_ROLE) {
        if (_poolSizeWeight > MAX_RATIO) revert PoolSizeWeightCannotBeGreaterThanMaxRatio();
        if (poolSizeWeight == _poolSizeWeight) revert PoolSizeWeightCannotBeTheSame();
        if (_poolSizeWeight == 0) revert PoolSizeWeightCannotBeZero();

        poolSizeWeight = _poolSizeWeight;
        emit PoolSizeWeightUpdated(_poolSizeWeight);
    }

    function setThresholdCollateral(uint256 _thresholdCollateral) external onlyRole(SCORING_MANAGER_ROLE) {
        if (_thresholdCollateral == 0) revert ThresholdCollateralCannotBeZero();
        if (thresholdCollateral == _thresholdCollateral) revert ThresholdCollateralCannotBeTheSame();

        thresholdCollateral = _thresholdCollateral;
        emit ThresholdCollateralUpdated(_thresholdCollateral);
    }

    function setThresholdCapital(uint256 _thresholdCapital) external onlyRole(SCORING_MANAGER_ROLE) {
        if (_thresholdCapital == 0) revert ThresholdCapitalCannotBeZero();
        if (thresholdCapital == _thresholdCapital) revert ThresholdCapitalCannotBeTheSame();

        thresholdCapital = _thresholdCapital;
        emit ThresholdCapitalUpdated(_thresholdCapital);
    }

    function setMarketConditionRatio(uint256 _marketConditionRatio) external onlyRole(SCORING_MANAGER_ROLE) {
        if (_marketConditionRatio > MAX_RATIO || _marketConditionRatio == 0) revert InvalidMarketConditionRatio();
        if (marketConditionRatio == _marketConditionRatio) revert MarketConditionRatioCannotBeTheSame();

        marketConditionRatio = _marketConditionRatio;
        emit MarketConditionRatioUpdated(_marketConditionRatio);
    }

    function _isContract(address _address) internal view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_address)
        }
        return (size > 0);
    }
}
