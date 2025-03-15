// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

interface IScoring {
    struct ScoreDetails {
        uint256 score; 
        uint256 poolSize; // pool size that need for recalculating pool size ratio
        uint256 totalFails; // total fails on that moment when score was set, penalty based on this value
        bool isVaultFailed;
    }

    error TreasuryMustBeContract();
    error VaultFactoryMustBeContract();
    error GoilTokenMustBeContract();
    error LicenseMustBeContract();
    error LicenseIsNotPending();
    error OnlyVault();
    error OnlyManagerOrLicense();

    event EntityScoreUpdated(address indexed entity, uint256 newScore);
    event EntityScoreUpdatedAfterLiquidation(address indexed entity, uint256 newScore);

    function updateEntityScore() external;
    function updateEntityScoreAfterLiquidation(uint256 _depositedAmount) external;
    function setInitialScore(address _entity) external;
    function isReadyToSetInitialScore(address _entity) external view returns (bool);
    function getMaxPoolSize(address _entity) external view returns (uint256 maxPoolSize);
    function getMaxPossiblePoolSize(address _entity) external view returns (uint256 maxPossiblePoolSize);
    function getScores(address _entity) external view returns (uint256[] memory scores);
    function getScoresCount(address _entity) external view returns (uint256 scoresCount);
    function getLastScore(address _entity) external view returns (uint256 lastScore);
}