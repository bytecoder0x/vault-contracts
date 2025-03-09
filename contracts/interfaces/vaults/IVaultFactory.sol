// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {IOracle} from "./IOracle.sol";
import {ITreasury} from "./ITreasury.sol";
import {IScoring} from "./IScoring.sol";

interface IVaultFactory {
    error AdminCannotBeZeroAddress();
    error OracleMustBeContract();
    error RouterV2MustBeContract();
    error RouterV3MustBeContract();
    error DepositTokenMustBeContract();
    error DepositTokenAlreadyExists();
    error DepositTokenDoesNotExist();
    error CannotRemoveLastDepositToken();
    error DepositTokensCannotBeZero();
    error DesiredCapCannotBeZero(); 
    error InterestRateCannotBeZero();
    error StartTimeMustBeInFuture();
    error StartTimeMustBeBeforeFundingEndTime();
    error FundingEndTimeMustBeBeforeUnlockEndTime();
    error NooAllowedPoolSize();
    error HighInterestRate();
    error ScoringContractAlreadySet();
    error ScoringContractNotSet();
    error TreasuryContractCannotBeZeroAddress();
    error TreasuryContractAlreadySet();
    error TreasuryContractNotSet();
    error StakingContractAlreadySet();
    error StakingContractNotSet();
    error LicenseContractAlreadySet();
    error LicenseContractNotSet();
    error LicenseContractMustBeContract();
    error ScoringContractMustBeContract();
    error TreasuryContractMustBeContract();
    error StakingContractMustBeContract();
    error QuoterMustBeContract();
    error UnlockPeriodTooLong();
    error StakingPercentageCannotBeZero();
    error StakingPercentageCannotBeGreaterThanMaxBips();

    struct VaultInfo {
        address vault;
        address entity;
        address depositToken;
        uint256 interestRate;
        uint256 desiredCap;
        uint256 startTime;
        uint256 fundingEndTime;
        uint256 unlockEndTime;
        uint256 collateralAmount;
        uint256 refundableAmount;
    }

    event DepositTokenAdded(address indexed depositToken);
    event DepositTokenRemoved(address indexed depositToken);
    event LicenseContractSet(address indexed licenseContract);
    event ScoringContractSet(address indexed scoringContract);
    event TreasuryContractSet(address indexed treasuryContract);
    event StakingContractSet(address indexed stakingContract);
    event StakingPercentageSet(uint256 indexed stakingPercentage);
    event VaultCreated(address indexed vault, address indexed entity, VaultInfo vaultInfo);

    function ORACLE() external view returns (IOracle);
    function TREASURY() external view returns (ITreasury);
    function SCORING() external view returns (IScoring);
    function MAX_BIPS() external view returns (uint256);
    function COLLATERAL_PERCENTAGE() external view returns (uint256);
    function stakingPercentage() external view returns (uint256);
    function isVault(address _vault) external view returns (bool);
    function isDepositToken(address _depositToken) external view returns (bool);
    function vaults(address _vault) external view returns (
        address vault,
        address entity, 
        address depositToken,
        uint256 interestRate,
        uint256 desiredCap,
        uint256 startTime,
        uint256 fundingEndTime,
        uint256 unlockEndTime,
        uint256 collateralAmount,
        uint256 refundableAmount
    );

    function createVault(
        address _depositToken,
        uint256 _interestRate,
        uint256 _desiredCap,
        uint256 _startTime,
        uint256 _fundingPeriod,
        uint256 _unlockPeriod
    ) external;

    function addDepositToken(address _depositToken) external;
    function removeDepositToken(address _depositToken) external;

    function setScoringContract(address _scoringContract) external;
    function setTreasuryContract(address _treasuryContract) external;
    function setStakingContract(address _stakingContract) external;
    function setLicenseContract(address _licenseContract) external;
    function setStakingPercentage(uint256 _stakingPercentage) external;
    function getVaultEntity(address _vault) external view returns (address);
    function getLastVaultAddressByEntity(address _entity) external view returns (address);
    function getVaultsByEntity(address _entity) external view returns (VaultInfo[] memory);
    function getVaultsCountByEntity(address _entity) external view returns (uint256);
    function getCollateralAmount(address _vault) external view returns (uint256);
    function getRefundableAmount(address _vault) external view returns (uint256);
    function getVault(address _vault) external view returns (VaultInfo memory);
    function getAllVaults() external view returns (VaultInfo[] memory);
    function getVaultsCount() external view returns (uint256);
}