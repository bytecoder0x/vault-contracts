// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {ITreasury} from "../ITreasury.sol";
import {IScoring} from "../IScoring.sol";
import {ILicense} from "../ILicense.sol";

interface IVaultFactoryManager {
    error DepositTokensLengthCannotBeZero();
    error AdminCannotBeZeroAddress();
    error DepositTokenMustBeContract();
    error DepositTokenAlreadyExists();
    error DepositTokenDoesNotExist();
    error CannotRemoveLastDepositToken();
    error ScoringContractAlreadySet();
    error ScoringContractNotSet();
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
    error StakingPercentageCannotBeZero();
    error StakingPercentageCannotBeGreaterThanMaxBips();

    event DepositTokenAdded(address indexed depositToken);
    event DepositTokenRemoved(address indexed depositToken);
    event LicenseContractSet(address indexed licenseContract);
    event ScoringContractSet(address indexed scoringContract);
    event TreasuryContractSet(address indexed treasuryContract);
    event StakingContractSet(address indexed stakingContract);
    event StakingPercentageSet(uint256 indexed stakingPercentage);

    function TREASURY() external view returns (ITreasury);
    function SCORING() external view returns (IScoring);
    function LICENSE() external view returns (ILicense);
    function stakingPercentage() external view returns (uint256);
    function isDepositToken(address _depositToken) external view returns (bool);
    function depositTokens(uint256 _index) external view returns (address);

    function addDepositToken(address _depositToken) external;
    function removeDepositToken(address _depositToken) external;
    function setScoringContract(address _scoringContract) external;
    function setTreasuryContract(address _treasuryContract) external;
    function setStakingContract(address _stakingContract) external;
    function setLicenseContract(address _licenseContract) external;
    function setStakingPercentage(uint256 _stakingPercentage) external;
}