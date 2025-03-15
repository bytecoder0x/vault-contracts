// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {IOracle} from "./IOracle.sol";
import {ITreasury} from "./ITreasury.sol";
import {IScoring} from "./IScoring.sol";
import {ILicense} from "./ILicense.sol";
interface IVaultFactory {
    error GoilTokenMustBeContract();
    error OracleMustBeContract();
    error RouterV2MustBeContract();
    error RouterV3MustBeContract();
    error DesiredCapCannotBeZero(); 
    error InterestRateCannotBeZero();
    error StartTimeMustBeInFuture();
    error StartTimeMustBeBeforeFundingEndTime();
    error FundingEndTimeMustBeBeforeUnlockEndTime();
    error NotAllowedPoolSize();
    error HighInterestRate();
    error QuoterMustBeContract();
    error UnlockPeriodTooLong();

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

    event VaultCreated(address indexed vault, address indexed entity, VaultInfo vaultInfo);

    function ORACLE() external view returns (IOracle);
    function VAULT_EXPIRY_LIMIT_AFTER_LICENSE() external view returns (uint256);
    function isVault(address _vault) external view returns (bool);
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

    function getVaultEntity(address _vault) external view returns (address);
    function getVaultsByEntity(address _entity) external view returns (VaultInfo[] memory);
    function getVaultsCountByEntity(address _entity) external view returns (uint256);
    function getCollateralAmount(address _vault) external view returns (uint256);
    function getRefundableAmount(address _vault) external view returns (uint256);
    function getPoolSize(address _vault) external view returns (uint256);
    function getVault(address _vault) external view returns (VaultInfo memory);
    function getAllVaults() external view returns (VaultInfo[] memory);
    function getVaultsCount() external view returns (uint256);
}