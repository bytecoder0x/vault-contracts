// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

interface ITreasury {
    struct Collateral {
        uint256 collateralLocked;
        uint256 collateralUnlocked;
    }

    event TokensWithdrawn(address indexed token, address indexed to, uint256 amount);
    event VaultFunded(address indexed vault, uint256 amount);
    event StakingTokensReplenished(address indexed token, uint256 amount);
    event StakingTokensTransferred(address indexed recipient, uint256 amount);
    event CollateralUnlocked(address indexed entity, uint256 amount);
    event CollateralDeposited(address indexed depositor, address indexed entity, address indexed vault, uint256 amount);
    event CollateralWithdrawn(address indexed entity, uint256 amount);
    event ScoringContractUpdated(address indexed scoring);
    event StakingContractUpdated(address indexed staking);
    event LicenseContractUpdated(address indexed license);

    error OracleMustBeContract();
    error ZeroAmountToFundVault();
    error ZeroAmountToUnlockCollateral();
    error ZeroAmountToTransfer();
    error OnlyScoringAllowed();
    error OnlyStakingAllowed();
    error OnlyLicenseAllowed();
    error OnlyVaultFactoryAllowed();
    error VaultFactoryMustBeContract();
    error GoilTokenMustBeContract();
    error ScoringMustBeContract();
    error StakingMustBeContract();
    error LicenseMustBeContract();
    error AdminCannotBeZeroAddress();
    error RecipientCannotBeZeroAddress();
    error ZeroAmountToDeposit();
    error ZeroAmountToWithdraw();
    error CannotWithdrawDuringActiveLicense();
    error InsufficientCollateral();
    error VaultIsNotValid();
    error ScoringContractNotSet();
    error StakingContractNotSet();
    error LicenseContractNotSet();
    error ScoringAlreadySet();
    error StakingAlreadySet();
    error LicenseAlreadySet();
    
    function collateral(address _entity) external view returns (uint256, uint256);

    function depositCollateral(address _vault) external;
    function depositCollateral(address _entity, uint256 _amount) external;
    function withdrawCollateral(uint256 _amount) external;
    function unlockCollateral(address _vault) external;
    function fundVault(address _vault) external;
    function unstakeTokens(address _recipient, uint256 _amount) external;
    function withdrawTokens(address _recipient, address _token, uint256 _amount) external;
    function withdrawAllTokens(address _token) external;
    function setScoringContract(address _scoring) external;
    function setStakingContract(address _staking) external;
    function setLicenseContract(address _license) external;
    function getRequiredCollateral(uint256 _poolSize) external view returns (uint256);
}