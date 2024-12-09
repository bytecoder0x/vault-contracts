// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVaultFactory} from "../interfaces/vaults/IVaultFactory.sol";
import {IScoring} from "../interfaces/vaults/IScoring.sol";

contract Scoring is AccessControl, IScoring {
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    uint8 public constant MAX_HISTORY_SCORE_COUNT = 5;

    uint256 public constant EXP = 2_71828; // 2.71828 * SCORE_PRECISION

    uint24 public constant SCORE_PRECISION = 1e5;
    uint24 public constant MAX_RATIO = 100_000;

    uint16 public constant TOKENS_COLLATERAL_WEIGHT = 40_000;
    uint16 public constant REPUTATION_WEIGHT = 20_000;
    uint16 public constant FINANCIAL_HEALTH_WEIGHT = 25_000;
    uint16 public constant MARKET_CONDITION_WEIGHT = 15_000;

    uint16 public constant POOL_SIZE_WEIGHT = 10_000;

    uint16[] public HISTORY_SCORE_WEIGHTS = [10_000, 10_000, 10_000, 20_000, 50_000];

    IERC20 public immutable GOIL_TOKEN;
    IVaultFactory public immutable VAULT_FACTORY;

    uint256 public thresholdCapital;
    uint256 public thresholdCollateral;
    uint256 public reputationRatio;
    uint256 public financialHealthRatio;
    uint256 public marketConditionRatio;

    mapping(address => uint256[]) public scores;
    mapping(address => uint256) public totalFails;

    modifier onlyVaultFactory() {
        if (msg.sender != address(VAULT_FACTORY)) revert OnlyVaultFactory();
        _;
    }

    constructor(
        address _admin,
        address _vaultFactory,
        address _goilToken,
        uint256 _thresholdCapital,
        uint256 _thresholdCollateral,
        uint256 _reputationRatio,
        uint256 _financialHealthRatio,
        uint256 _marketConditionRatio
    ) {
        if (!_isContract(_vaultFactory)) revert VaultFactoryMustBeContract();
        if (!_isContract(_goilToken)) revert GoilTokenMustBeContract();
        if (_admin == address(0)) revert AdminCannotBeZeroAddress();
        if (_thresholdCapital == 0) revert ThresholdCapitalCannotBeZero();
        if (_thresholdCollateral == 0) revert ThresholdCollateralCannotBeZero();
        if (_reputationRatio > MAX_RATIO || _reputationRatio == 0) revert InvalidReputationRatio();
        if (_financialHealthRatio > MAX_RATIO || _financialHealthRatio == 0) revert InvalidFinancialHealthRatio();
        if (_marketConditionRatio > MAX_RATIO || _marketConditionRatio == 0) revert InvalidMarketConditionRatio();

        VAULT_FACTORY = IVaultFactory(_vaultFactory);
        GOIL_TOKEN = IERC20(_goilToken);
        thresholdCapital = _thresholdCapital;
        thresholdCollateral = _thresholdCollateral;
        reputationRatio = _reputationRatio;
        financialHealthRatio = _financialHealthRatio;
        marketConditionRatio = _marketConditionRatio;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(MANAGER_ROLE, _admin);
    }

    function updateEntityScore(address _entity, uint256 _poolSize, bool _isFail) public onlyVaultFactory {
        uint256[] memory entityScores = scores[_entity];
        uint256 totalScores = entityScores.length;

        if (totalScores == 0) {
            uint256 initialScore = getInitialScore(_entity);
            scores[_entity].push(initialScore);
        }
        if (_isFail) totalFails[_entity] += 1;

        uint256 lastScore = entityScores[totalScores - 1];
        uint256 maxPoolSize = getMaxPoolSize(_entity);
        uint256 historicalPerformance = getHistoricalPerformance(_entity);
        uint256 penalty = getPenalty(_entity);
        uint256 poolSizeRatio = (_poolSize * POOL_SIZE_WEIGHT) / maxPoolSize;

        if (_poolSize > maxPoolSize) revert PoolSizeCannotBeGreaterThanMaxPoolSize();

        uint256 newScore = lastScore + (poolSizeRatio * historicalPerformance * penalty) / (SCORE_PRECISION * SCORE_PRECISION);

        if (newScore > MAX_RATIO) newScore = MAX_RATIO;
        scores[_entity].push(newScore);

        emit EntityScoreUpdated(_entity, newScore);
    }

    function getMaxPoolSize(address _entity) public view returns (uint256 maxPoolSize) {
        uint256 lastScore = scores[_entity][scores[_entity].length - 1];
        maxPoolSize = (lastScore * thresholdCapital) / SCORE_PRECISION;
    }

    function getInitialScore(address _entity) public view returns (uint256 score) {
        uint256 entityTokenHoldings = GOIL_TOKEN.balanceOf(_entity); // TODO: mb it must be recorded when entity got license?
        uint256 normalizedCollateralRatio = (entityTokenHoldings * MAX_RATIO) / thresholdCollateral;
        if (normalizedCollateralRatio > MAX_RATIO) normalizedCollateralRatio = MAX_RATIO;

        uint256 normalizedReputationRatio = reputationRatio * REPUTATION_WEIGHT / MAX_RATIO;
        uint256 normalizedFinancialHealthRatio = financialHealthRatio * FINANCIAL_HEALTH_WEIGHT / MAX_RATIO;
        uint256 normalizedMarketConditionRatio = marketConditionRatio * MARKET_CONDITION_WEIGHT / MAX_RATIO;

        score = normalizedCollateralRatio + normalizedReputationRatio + normalizedFinancialHealthRatio + normalizedMarketConditionRatio;
    }

    function getPenalty(address _entity) public view returns (uint256 penalty) {
        uint256 power = totalFails[_entity];
        penalty = (uint256(SCORE_PRECISION) ** (power + 1)) / (EXP ** power);
    }

    function getHistoricalPerformance(address _entity) public view returns (uint256 historicalPerformance) {
        uint256 accumulatedHistoricalScore;
        uint256 maxEntityScore;

        uint256[] memory entityScores = scores[_entity];
        uint256 totalScores = entityScores.length;

        uint256 historyScoreCount = totalScores < MAX_HISTORY_SCORE_COUNT ? totalScores : MAX_HISTORY_SCORE_COUNT;

        for (uint256 i = 0; i < historyScoreCount; i++) {  
            uint256 currentScore = entityScores[totalScores - (i + 1)];
            uint256 currentWeight = HISTORY_SCORE_WEIGHTS[i];

            accumulatedHistoricalScore += currentScore * currentWeight / SCORE_PRECISION;
            if (currentScore > maxEntityScore) maxEntityScore = currentScore;
        }

        historicalPerformance = (accumulatedHistoricalScore * SCORE_PRECISION) / maxEntityScore;
    }

    function setThresholdCollateral(uint256 _thresholdCollateral) external onlyRole(MANAGER_ROLE) {
        if (_thresholdCollateral == 0) revert ThresholdCollateralCannotBeZero();
        if (thresholdCollateral == _thresholdCollateral) revert ThresholdCollateralCannotBeTheSame();

        thresholdCollateral = _thresholdCollateral;
        emit ThresholdCollateralUpdated(_thresholdCollateral);
    }

    function setThresholdCapital(uint256 _thresholdCapital) external onlyRole(MANAGER_ROLE) {
        if (_thresholdCapital == 0) revert ThresholdCapitalCannotBeZero();
        if (thresholdCapital == _thresholdCapital) revert ThresholdCapitalCannotBeTheSame();

        thresholdCapital = _thresholdCapital;
        emit ThresholdCapitalUpdated(_thresholdCapital);
    }

    function setReputationRatio(uint256 _reputationRatio) external onlyRole(MANAGER_ROLE) {
        if (_reputationRatio > MAX_RATIO || _reputationRatio == 0) revert InvalidReputationRatio();
        if (reputationRatio == _reputationRatio) revert ReputationRatioCannotBeTheSame();

        reputationRatio = _reputationRatio;
        emit ReputationRatioUpdated(_reputationRatio);
    }

    function setFinancialHealthRatio(uint256 _financialHealthRatio) external onlyRole(MANAGER_ROLE) {
        if (_financialHealthRatio > MAX_RATIO || _financialHealthRatio == 0) revert InvalidFinancialHealthRatio();
        if (financialHealthRatio == _financialHealthRatio) revert FinancialHealthRatioCannotBeTheSame();

        financialHealthRatio = _financialHealthRatio;
        emit FinancialHealthRatioUpdated(_financialHealthRatio);
    }

    function setMarketConditionRatio(uint256 _marketConditionRatio) external onlyRole(MANAGER_ROLE) {
        if (_marketConditionRatio > MAX_RATIO || _marketConditionRatio == 0) revert InvalidMarketConditionRatio();
        if (marketConditionRatio == _marketConditionRatio) revert MarketConditionRatioCannotBeTheSame();

        marketConditionRatio = _marketConditionRatio;
        emit MarketConditionRatioUpdated(_marketConditionRatio);
    }

    function _isContract(address _address) private view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_address)
        }
        return (size > 0);
    }
}
