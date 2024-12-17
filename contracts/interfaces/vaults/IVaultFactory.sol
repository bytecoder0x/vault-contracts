// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {IOracle} from "./IOracle.sol";
import {ITreasury} from "./ITreasury.sol";
import {IScoring} from "./IScoring.sol";

interface IVaultFactory {
    error OracleMustBeContract();
    error DepositTokenMustBeContract();
    error DesiredCapCannotBeZero(); 
    error InterestRateCannotBeZero();
    error StartTimeMustBeInFuture();
    error StartTimeMustBeBeforeFundingEndTime();
    error FundingEndTimeMustBeBeforeUnlockEndTime();
    error NooAllowedPoolSize();
    error ScoringContractAlreadySet();
    error ScoringContractNotSet();
    error TreasuryContractCannotBeZeroAddress();
    error TreasuryContractAlreadySet();
    error TreasuryContractNotSet();
    error ScoringContractMustBeContract();
    error TreasuryContractMustBeContract();

    struct VaultInfo {
        address entity;
        uint256 interestRate;
        uint256 desiredCap;
        uint256 startTime;
        uint256 fundingEndTime;
        uint256 unlockEndTime;
        uint256 collateralAmount;
    }

    event ScoringContractSet(address indexed scoringContract);
    event TreasuryContractSet(address indexed treasuryContract);
    event VaultCreated(address indexed vault, address indexed entity, VaultInfo vaultInfo);

    function ORACLE() external view returns (IOracle);
    function DEPOSIT_TOKEN() external view returns (address);
    function VAULT_IMPLEMENTATION() external view returns (address);
    function TREASURY() external view returns (ITreasury);
    function SCORING() external view returns (IScoring);
    function MAX_BIPS() external view returns (uint256);
    function COLLATERAL_PERCENTAGE() external view returns (uint256);

    function createVault(
        uint256 _interestRate,
        uint256 _desiredCap,
        uint256 _startTime,
        uint256 _fundingPeriod,
        uint256 _unlockPeriod
    ) external;

    function setScoringContract(address _scoringContract) external;
    function setTreasuryContract(address _treasuryContract) external;
    function getIsValidVault(address _vault) external view returns (bool);
    function getVaultEntity(address _vault) external view returns (address);
    function getAllVaults() external view returns (VaultInfo[] memory);
    function getVaultsCount() external view returns (uint256);
}