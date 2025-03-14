// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {ScoringManager} from "./components/ScoringManager.sol";
import {ABDKMath64x64} from "abdk-libraries-solidity/ABDKMath64x64.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVaultFactory} from "../interfaces/vaults/IVaultFactory.sol";
import {IVault} from "../interfaces/vaults/IVault.sol";
import {ITreasury} from "../interfaces/vaults/ITreasury.sol";
import {IScoring} from "../interfaces/vaults/IScoring.sol";
import {ILicense} from "../interfaces/vaults/ILicense.sol";

contract Scoring is ScoringManager, IScoring {
    // max ratio is 100_000 (in scoring manager)
    uint24 public constant SCORE_PRECISION = 100_000;

    uint16 public constant TOKENS_COLLATERAL_WEIGHT = 40_000;
    uint16 public constant REPUTATION_WEIGHT = 20_000;
    uint16 public constant FINANCIAL_HEALTH_WEIGHT = 25_000;
    uint16 public constant MARKET_CONDITION_WEIGHT = 15_000;

    // weights for current score in history (last score is the most important and has the highest weight)
    uint16[] public HISTORY_SCORE_WEIGHTS = [10_000, 10_000, 10_000, 20_000, 50_000];

    uint8 public constant MAX_HISTORY_SCORE_COUNT = 5;

    IERC20 public immutable GOIL_TOKEN;
    ITreasury public immutable TREASURY;
    ILicense public immutable LICENSE;
    IVaultFactory public immutable VAULT_FACTORY;

    mapping(uint256 => ScoreDetails) public scoresDetails; // id -> info about score
    mapping(address => uint256) public scoresIds; // vault -> id of score
    mapping(address => uint256[]) public scores; // entity -> scores
    mapping(address => uint256) public totalFails; // total fails with score precision

    modifier onlyVault() {
        if (!VAULT_FACTORY.isVault(msg.sender)) revert OnlyVault();
        _;
    }

    modifier onlyManagerOrLicense() {
        if (!hasRole(SCORING_MANAGER_ROLE, msg.sender) && msg.sender != address(LICENSE)) revert OnlyManagerOrLicense();
        _;
    }

    constructor(
        address _admin,
        address _vaultFactory,
        address _treasury,
        address _license,
        address _goilToken,
        uint256 _thresholdCapital,
        uint256 _thresholdCollateral,
        uint256 _marketConditionRatio
    ) ScoringManager(_admin, _thresholdCapital, _thresholdCollateral, _marketConditionRatio) {
        if (!_isContract(_vaultFactory)) revert VaultFactoryMustBeContract();
        if (!_isContract(_goilToken)) revert GoilTokenMustBeContract();
        if (!_isContract(_treasury)) revert TreasuryMustBeContract();
        if (!_isContract(_license)) revert LicenseMustBeContract();

        VAULT_FACTORY = IVaultFactory(_vaultFactory);
        GOIL_TOKEN = IERC20(_goilToken);
        TREASURY = ITreasury(_treasury);
        LICENSE = ILicense(_license);
    }

    function updateEntityScore() external onlyVault {
        IVault vault = IVault(msg.sender);

        bool isVaultFailed = !vault.isVaultSuccess();
        address entity = vault.ENTITY();
        uint256 poolSize = vault.desiredCap();
        
        uint256[] storage entityScores = scores[entity];
        uint256 lastScore = entityScores[entityScores.length - 1];

        uint256 poolSizeRatio = poolSize * poolSizeWeight / (lastScore * thresholdCapital / SCORE_PRECISION); // pool size div max pool size
        uint256 updatedScore = lastScore + (poolSizeRatio * _calculateHistoricalPerformance(entityScores) / SCORE_PRECISION);

        if (isVaultFailed) {
            uint256 failureRate = _calculateFailureRate(address(vault));

            totalFails[entity] += failureRate;
            updatedScore = updatedScore * _calculatePenalty(totalFails[entity]) / SCORE_PRECISION;
        }  else {
            TREASURY.unlockCollateral(address(vault));
        }

        TREASURY.releaseBorrowed(address(vault));

        updatedScore = updatedScore > MAX_RATIO ? MAX_RATIO : updatedScore;
        entityScores.push(updatedScore);

        uint256 scoreId = entityScores.length;
        scoresIds[msg.sender] = scoreId;
        scoresDetails[scoreId] = ScoreDetails({
            score: updatedScore,
            poolSize: poolSize,
            totalFails: totalFails[entity],
            isVaultFailed: isVaultFailed
        });

        emit EntityScoreUpdated(entity, updatedScore);
    }

    function updateEntityScoreAfterLiquidation(uint256 _depositedAmount) external onlyVault {
        IVault vault = IVault(msg.sender);
        address entity = vault.ENTITY();

        uint256[] storage entityScores = scores[entity];

        uint256 scoreId = scoresIds[msg.sender];
        uint256 indexOfScore = scoreId - 1;
        uint256 totalScores = entityScores.length;

        // its means that we cannot update score if its older than 5 scores
        if (totalScores >= MAX_HISTORY_SCORE_COUNT && indexOfScore < totalScores - MAX_HISTORY_SCORE_COUNT) {
            return;
        }

        ScoreDetails storage scoreDetails = scoresDetails[scoreId];
        // success rate: (deposited amount / promised cap) * decrease success factor
        uint256 successRate = (_depositedAmount * decreaseSuccessFactor) / vault.promisedCap();
        // new score: score * new penalty / penalty of previous score
        uint256 updatedScore = scoreDetails.score * _calculatePenalty(scoreDetails.totalFails - successRate) / _calculatePenalty(scoreDetails.totalFails);

        scoreDetails.score = updatedScore;
        scoreDetails.totalFails -= successRate;
        entityScores[indexOfScore] = updatedScore;
        totalFails[entity] -= successRate;

        _updateHistoricalScores(entityScores, scoreId, indexOfScore, totalScores, successRate);
    }
    
    function setPerformanceData(
        address _entity,
        uint256 _reputationRatio,
        uint256 _financialHealthRatio
    ) public override onlyRole(SCORING_MANAGER_ROLE) {
        super.setPerformanceData(_entity, _reputationRatio, _financialHealthRatio);

        if (LICENSE.getLicenseIsActive(_entity)) {
            setInitialScore(_entity);
        }
    }

    function setInitialScore(address _entity) public onlyManagerOrLicense {
        (uint256 entityCollateral, ) = TREASURY.collateral(_entity); // collateral when submitting a license

        uint256 entityReputationRatio = performanceData[_entity].reputationRatio;
        uint256 entityFinancialHealthRatio = performanceData[_entity].financialHealthRatio;

        uint256 collateralRatio = (entityCollateral * SCORE_PRECISION) / thresholdCollateral;
        if (collateralRatio > MAX_RATIO) collateralRatio = MAX_RATIO;

        uint256 weightedCollateralRatio = collateralRatio * TOKENS_COLLATERAL_WEIGHT / SCORE_PRECISION;
        uint256 weightedReputationRatio = entityReputationRatio * REPUTATION_WEIGHT / SCORE_PRECISION;
        uint256 weightedFinancialHealthRatio = entityFinancialHealthRatio * FINANCIAL_HEALTH_WEIGHT / SCORE_PRECISION;
        uint256 weightedMarketConditionRatio = marketConditionRatio * MARKET_CONDITION_WEIGHT / SCORE_PRECISION;

        uint256 initialScore = weightedCollateralRatio + weightedReputationRatio + weightedFinancialHealthRatio + weightedMarketConditionRatio;

        scores[_entity].push(initialScore);

        emit EntityScoreUpdated(_entity, initialScore);
    }

    function getScores(address _entity) public view returns (uint256[] memory) {
        return scores[_entity];
    }

    function getScoresCount(address _entity) public view returns (uint256) {
        return scores[_entity].length;
    }

    function getLastScore(address _entity) public view returns (uint256) {
        return scores[_entity][scores[_entity].length - 1];
    }
    
    function getMaxPoolSize(address _entity) public view returns (uint256 maxPoolSize) {
        uint256 lastScore = getLastScore(_entity);
        maxPoolSize = (lastScore * thresholdCapital) / SCORE_PRECISION;
    }

    function getMaxPossiblePoolSize(address _entity) public view returns (uint256 maxPossiblePoolSize) {
        uint256 maxPoolSize = getMaxPoolSize(_entity);
        uint256 totalBorrowed = TREASURY.getTotalBorrowed(_entity);

        if (totalBorrowed > maxPoolSize) {
            maxPossiblePoolSize = 0;
        } else {
            maxPossiblePoolSize = maxPoolSize - totalBorrowed;
        }
    }

    function isReadyToSetInitialScore(address _entity) public view returns (bool) {
        uint256 reputationRatio = performanceData[_entity].reputationRatio;
        uint256 financialHealthRatio = performanceData[_entity].financialHealthRatio;
        uint256 totalScores = scores[_entity].length;
        
        return totalScores == 0 && reputationRatio != 0 && financialHealthRatio != 0;
    }

    function _updateHistoricalScores(
        uint256[] storage entityScores,
        uint256 scoreId,
        uint256 indexOfScore,
        uint256 totalScores,
        uint256 successRate
    ) private {
        // example: we have 10 scores and current score with id 6 (indexOfScore = 5) 
        // so we need to update scores from 6 to 10 (with id 6 already updated). 10 - 5 - 1 = 4
        uint256 totalScoresToUpdate = totalScores - indexOfScore - 1;

        for (uint256 i = 0; i < totalScoresToUpdate; ) {
            uint256 currentScoreId = scoreId + i + 1;
            uint256 currentIndexOfScore = currentScoreId - 1;

            ScoreDetails storage currentScoreDetails = scoresDetails[currentScoreId];
            
            uint256[] memory historyScore = _getCurrentHistoricalScores(entityScores, currentIndexOfScore);
            uint256 newHistoricalPerformance = _calculateHistoricalPerformance(historyScore);

            uint256 lastScore = scoresDetails[currentScoreId - 1].score;
            uint256 poolSizeRatio = (currentScoreDetails.poolSize * poolSizeWeight) / (lastScore * thresholdCapital / SCORE_PRECISION);
            uint256 currentUpdatedScore = (lastScore + poolSizeRatio * newHistoricalPerformance / SCORE_PRECISION);

            if (currentScoreDetails.isVaultFailed) {
                currentUpdatedScore = currentUpdatedScore * _calculatePenalty(currentScoreDetails.totalFails - successRate) / SCORE_PRECISION;
            }

            if (currentUpdatedScore > MAX_RATIO) {
                currentUpdatedScore = MAX_RATIO;
            }

            currentScoreDetails.totalFails -= successRate;
            currentScoreDetails.score = currentUpdatedScore;
            entityScores[currentIndexOfScore] = currentUpdatedScore;
            
            unchecked {
                i++;
            }
        }
    }

    function _calculatePenalty(uint256 _totalFailureRate) private pure returns (uint256 penalty) {
        int256 negativeFailureRate = int256(_totalFailureRate) * -1; // convert to negative number
        
        // calculate power of exponent
        int128 power = ABDKMath64x64.div(
            ABDKMath64x64.fromInt(negativeFailureRate),
            ABDKMath64x64.fromUInt(SCORE_PRECISION)
        );
        // calculate exponent
        int128 result = ABDKMath64x64.exp(power);

        penalty = uint256(ABDKMath64x64.mulu(result, SCORE_PRECISION));
    }

    function _calculateFailureRate(address _vault) private view returns (uint256 failureRate) {
        (uint256 promisedAmount, uint256 unpaidAmount) = IVault(_vault).getPromisedAndUnpaidAmount();

        failureRate = (unpaidAmount * SCORE_PRECISION) / promisedAmount;
    }

    function _calculateHistoricalPerformance(uint256[] memory _entityScores) private view returns (uint256 historicalPerformance) {
        uint256 accumulatedHistoricalScore;
        uint256 maxEntityScore;

        uint256 totalScores = _entityScores.length;

        uint256 historyScoreCount = totalScores < MAX_HISTORY_SCORE_COUNT ? totalScores : MAX_HISTORY_SCORE_COUNT;
        uint256 historyScoreWeightsCount = HISTORY_SCORE_WEIGHTS.length;
        
        for (uint256 i = 0; i < historyScoreCount; ) {  
            uint256 currentScore = _entityScores[totalScores - (i + 1)];
            uint256 currentWeight = HISTORY_SCORE_WEIGHTS[historyScoreWeightsCount - (i + 1)];

            accumulatedHistoricalScore += currentScore * currentWeight / SCORE_PRECISION;
            if (currentScore > maxEntityScore) maxEntityScore = currentScore;

            unchecked {
                i++;
            }
        }

        historicalPerformance = (accumulatedHistoricalScore * SCORE_PRECISION) / maxEntityScore;
    }

    function _getCurrentHistoricalScores(uint256[] memory _entityScores, uint256 _indexOfScore) private pure returns (uint256[] memory) {
        uint256 amountToCopy = _indexOfScore >= MAX_HISTORY_SCORE_COUNT ? MAX_HISTORY_SCORE_COUNT : _indexOfScore;
        uint256[] memory historyScores = new uint256[](amountToCopy);

        // Copy previous elements to new array
        uint256 startIndex = _indexOfScore - amountToCopy;
        for (uint256 i = 0; i < amountToCopy; ) {
            historyScores[i] = _entityScores[startIndex + i];
            unchecked {
                i++;
            }
        }

        return historyScores;
    }
}
