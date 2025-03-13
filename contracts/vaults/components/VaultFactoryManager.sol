// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IVaultFactoryManager} from "../../interfaces/vaults/components/IVaultFactoryManager.sol";

import {ITreasury} from "../../interfaces/vaults/ITreasury.sol";
import {ILicense} from "../../interfaces/vaults/ILicense.sol";
import {IScoring} from "../../interfaces/vaults/IScoring.sol";
import {IStaking} from "../../interfaces/vaults/IStaking.sol";

contract VaultFactoryManager is AccessControl, IVaultFactoryManager {
    bytes32 public constant VAULT_FACTORY_MANAGER_ROLE = keccak256("VAULT_FACTORY_MANAGER_ROLE");

    uint256 public constant MAX_BIPS = 100_00;

    ITreasury public TREASURY;
    ILicense public LICENSE;
    IScoring public SCORING;
    IStaking public STAKING;

    uint256 public stakingPercentage = 1_00;

    mapping(address => bool) public isDepositToken;
    address[] public depositTokens;

    constructor(
        address _admin,
        address[] memory _depositTokens
    ) {
        if (_admin == address(0)) revert AdminCannotBeZeroAddress();
        if (_depositTokens.length == 0) revert DepositTokensLengthCannotBeZero();

        uint256 totalDepositTokens = _depositTokens.length;
        for (uint256 i = 0; i < totalDepositTokens; ) {
            if (!_isContract(_depositTokens[i])) revert DepositTokenMustBeContract();

            isDepositToken[_depositTokens[i]] = true;
            depositTokens.push(_depositTokens[i]);

            unchecked {
                i++;
            }
        }
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(VAULT_FACTORY_MANAGER_ROLE, _admin);
    }
    
    function addDepositToken(address _depositToken) public onlyRole(VAULT_FACTORY_MANAGER_ROLE) {
        if (!_isContract(_depositToken)) revert DepositTokenMustBeContract();
        if (isDepositToken[_depositToken]) revert DepositTokenAlreadyExists();

        isDepositToken[_depositToken] = true;
        depositTokens.push(_depositToken);
        emit DepositTokenAdded(_depositToken);
    }

    function removeDepositToken(address _depositToken) public onlyRole(VAULT_FACTORY_MANAGER_ROLE) {
        uint256 totalDepositTokens = depositTokens.length;
        if (totalDepositTokens == 1) revert CannotRemoveLastDepositToken();
        if (!isDepositToken[_depositToken]) revert DepositTokenDoesNotExist();

        isDepositToken[_depositToken] = false;
        for (uint256 i = 0; i < totalDepositTokens; i++) {
            if (depositTokens[i] == _depositToken) {
                depositTokens[i] = depositTokens[totalDepositTokens - 1];
                depositTokens.pop();
                break;
            }
        }

        emit DepositTokenRemoved(_depositToken);
    }

    function setStakingPercentage(uint256 _stakingPercentage) public onlyRole(VAULT_FACTORY_MANAGER_ROLE) {
        if (_stakingPercentage > MAX_BIPS) revert StakingPercentageCannotBeGreaterThanMaxBips();
        if (_stakingPercentage == 0) revert StakingPercentageCannotBeZero();

        stakingPercentage = _stakingPercentage;
        emit StakingPercentageSet(_stakingPercentage);
    }

    function setLicenseContract(address _licenseContract) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!_isContract(_licenseContract)) revert LicenseContractMustBeContract();
        if (address(LICENSE) != address(0)) revert LicenseContractAlreadySet();

        LICENSE = ILicense(_licenseContract);
        emit LicenseContractSet(_licenseContract);
    }

    function setScoringContract(address _scoringContract) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!_isContract(_scoringContract)) revert ScoringContractMustBeContract();
        if (address(SCORING) != address(0)) revert ScoringContractAlreadySet();

        SCORING = IScoring(_scoringContract);
        emit ScoringContractSet(_scoringContract);
    }

    function setTreasuryContract(address _treasuryContract) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!_isContract(_treasuryContract)) revert TreasuryContractMustBeContract();
        if (address(TREASURY) != address(0)) revert TreasuryContractAlreadySet();

        TREASURY = ITreasury(_treasuryContract);
        emit TreasuryContractSet(_treasuryContract);
    }

    function setStakingContract(address _stakingContract) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!_isContract(_stakingContract)) revert StakingContractMustBeContract();
        if (address(STAKING) != address(0)) revert StakingContractAlreadySet();

        STAKING = IStaking(_stakingContract);
        emit StakingContractSet(_stakingContract);
    }

    function _isContract(address _address) internal view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_address)
        }
        return (size > 0);
    }
}
