// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Vault} from "./Vault.sol";

import {IVaultFactory} from "../interfaces/vaults/IVaultFactory.sol";
import {ITreasury} from "../interfaces/vaults/ITreasury.sol";
import {ILicense} from "../interfaces/vaults/ILicense.sol";
import {IScoring} from "../interfaces/vaults/IScoring.sol";
import {IOracle} from "../interfaces/vaults/IOracle.sol";
import {IStaking} from "../interfaces/vaults/IStaking.sol";

contract VaultFactory is AccessControl, IVaultFactory {
    using Clones for address;

    uint256 public constant MAX_BIPS = 100_00;
    uint256 public constant COLLATERAL_PERCENTAGE = 10_00;

    uint256 public constant VAULT_EXPIRY_LIMIT_AFTER_LICENSE = 30 days;

    IOracle public immutable ORACLE;
    address public immutable GOIL_TOKEN;
    address public immutable VAULT_IMPLEMENTATION;


    address public immutable ROUTER_V3;
    address public immutable ROUTER_V2;
    address public immutable QUOTER;

    ITreasury public TREASURY;
    ILicense public LICENSE;
    IScoring public SCORING;
    IStaking public STAKING;

    uint256 public stakingPercentage = 1_00;

    address[] public depositTokens;
    VaultInfo[] public allVaults;

    mapping(address => VaultInfo[]) public vaultsByEntity;
    mapping(address => VaultInfo) public vaults;
    mapping(address => bool) public isVault;
    mapping(address => bool) public isDepositToken;

    modifier withExistingDepositToken(address _depositToken) {
        if (!isDepositToken[_depositToken]) revert DepositTokenDoesNotExist();
        _;
    }

    modifier withSetupNecessaryContracts() {
        if (address(SCORING) == address(0)) revert ScoringContractNotSet();
        if (address(TREASURY) == address(0)) revert TreasuryContractNotSet();
        if (address(STAKING) == address(0)) revert StakingContractNotSet();
        if (address(LICENSE) == address(0)) revert LicenseContractNotSet();
        _;
    }

    constructor(
        address _admin,
        address _goilToken,
        address _oracle,
        address _routerV2,
        address _routerV3,
        address _quoter,
        address[] memory _depositTokens
    ) {
        if (_admin == address(0)) revert AdminCannotBeZeroAddress();
        if (!_isContract(_oracle)) revert OracleMustBeContract();
        if (!_isContract(_routerV2)) revert RouterV2MustBeContract();
        if (!_isContract(_routerV3)) revert RouterV3MustBeContract();
        if (!_isContract(_quoter)) revert QuoterMustBeContract();
        if (_depositTokens.length == 0) revert DepositTokensCannotBeZero();

        for (uint256 i = 0; i < _depositTokens.length; i++) {
            if (!_isContract(_depositTokens[i])) revert DepositTokenMustBeContract();
            depositTokens.push(_depositTokens[i]);
            isDepositToken[_depositTokens[i]] = true;
        }
        
        ORACLE = IOracle(_oracle);
        GOIL_TOKEN = _goilToken;
        ROUTER_V2 = _routerV2;
        ROUTER_V3 = _routerV3;
        QUOTER = _quoter;

        VAULT_IMPLEMENTATION = address(new Vault());

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    function createVault(
        address _depositToken,
        uint256 _interestRate,
        uint256 _desiredCap,
        uint256 _startTime,
        uint256 _fundingPeriod,
        uint256 _lockPeriod
    ) external withSetupNecessaryContracts withExistingDepositToken(_depositToken) {
        uint256 fundingEndTime = _startTime + _fundingPeriod;
        uint256 unlockEndTime = fundingEndTime + _lockPeriod;
        
        if (_desiredCap == 0) revert DesiredCapCannotBeZero();
        if (_interestRate == 0) revert InterestRateCannotBeZero();
        if (_startTime <= block.timestamp) revert StartTimeMustBeInFuture();
        if (fundingEndTime <= _startTime) revert StartTimeMustBeBeforeFundingEndTime();
        if (unlockEndTime <= fundingEndTime) revert FundingEndTimeMustBeBeforeUnlockEndTime();

        uint256 maxAllowedUnlockPeriod = LICENSE.getLicenseExpirationTime(msg.sender) + VAULT_EXPIRY_LIMIT_AFTER_LICENSE;
        if (unlockEndTime > maxAllowedUnlockPeriod) revert UnlockPeriodTooLong();

        uint256 maxPoolSize = SCORING.getMaxPoolSize(msg.sender);
        uint256 maxAllowedPoolSize = maxPoolSize + (_interestRate * _lockPeriod) / MAX_BIPS;
        uint256 promisedCap = (_desiredCap * (MAX_BIPS + _interestRate)) / MAX_BIPS;

        if (_desiredCap > maxPoolSize) revert NooAllowedPoolSize();
        if (maxPoolSize < maxAllowedPoolSize) revert HighInterestRate();

        uint256 refundableAmount = ORACLE.getPaymentAmountForTokens(_desiredCap);
        uint256 requiredCollateral = TREASURY.getRequiredCollateral(_desiredCap);

        Vault vault = Vault(VAULT_IMPLEMENTATION.clone());
        vault.initialize(
            msg.sender,
            address(SCORING),
            address(TREASURY),
            address(STAKING),
            GOIL_TOKEN,
            _depositToken,
            ROUTER_V2,
            ROUTER_V3,
            QUOTER,
            _desiredCap,
            promisedCap,
            _startTime,
            fundingEndTime,
            unlockEndTime,
            refundableAmount,
            stakingPercentage
        );

        VaultInfo memory newVault = VaultInfo({
            vault: address(vault),
            entity: msg.sender,
            depositToken: _depositToken,
            interestRate: _interestRate,
            desiredCap: _desiredCap,
            startTime: _startTime,
            fundingEndTime: fundingEndTime,
            unlockEndTime: unlockEndTime,
            collateralAmount: requiredCollateral,
            refundableAmount: refundableAmount
        });

        isVault[address(vault)] = true;
        vaultsByEntity[msg.sender].push(newVault);
        vaults[address(vault)] = newVault;
        allVaults.push(newVault);
        
        TREASURY.depositCollateral(msg.sender, requiredCollateral, refundableAmount);

        emit VaultCreated(address(vault), msg.sender, newVault);
    }

    function addDepositToken(address _depositToken) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!_isContract(_depositToken)) revert DepositTokenMustBeContract();
        if (isDepositToken[_depositToken]) revert DepositTokenAlreadyExists();

        isDepositToken[_depositToken] = true;
        depositTokens.push(_depositToken);
        emit DepositTokenAdded(_depositToken);
    }

    function removeDepositToken(address _depositToken) public onlyRole(DEFAULT_ADMIN_ROLE) {
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

    function setStakingPercentage(uint256 _stakingPercentage) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_stakingPercentage > MAX_BIPS) revert StakingPercentageCannotBeGreaterThanMaxBips();
        if (_stakingPercentage == 0) revert StakingPercentageCannotBeZero();

        stakingPercentage = _stakingPercentage;
        emit StakingPercentageSet(_stakingPercentage);
    }

    function getVaultEntity(address _vault) public view returns (address) {
        return vaults[_vault].entity;
    }

    function getCollateralAmount(address _vault) public view returns (uint256) {
        return vaults[_vault].collateralAmount;
    }

    function getRefundableAmount(address _vault) public view returns (uint256) {
        return vaults[_vault].refundableAmount;
    }

    function getVault(address _vault) public view returns (VaultInfo memory) {
        return vaults[_vault];
    }

    function getAllVaults() public view returns (VaultInfo[] memory) {
        return allVaults;
    }

    function getVaultsCount() public view returns (uint256) {
        return allVaults.length;
    }

    function _isContract(address _address) private view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_address)
        }
        return (size > 0);
    }
}
