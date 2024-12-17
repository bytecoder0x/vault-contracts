// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

interface ITreasury {
    event TokensWithdrawn(address indexed token, address indexed to, uint256 amount);
    event VaultFunded(address indexed vault, uint256 amount);
    event StakingTokensReplenished(address indexed token, uint256 amount);
    event StakingTokensTransferred(address indexed recipient, uint256 amount);
    event CollateralDeposited(address indexed depositor, address indexed entity, uint256 amount);
    event CollateralWithdrawn(address indexed entity, uint256 amount);

    error ZeroAmountToFundVault();
    error ZeroAmountToTransfer();
    error OnlyScoringAllowed();
    error OnlyStakingAllowed();
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

    function collateralDeposited(address) external view returns (uint256);
    
    function depositCollateral(address _entity, uint256 _amount) external;
    function withdrawCollateral(uint256 _amount) external;
    function fundVault(address _vault, uint256 _amount) external;
    // function transferStakingTokens(address _recipient, uint256 _amount) external;
    // function withdrawTokens(address _recipient, address _token, uint256 _amount) external;
    // function withdrawAllTokens(address _token) external;
}