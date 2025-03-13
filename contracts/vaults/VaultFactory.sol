// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {VaultFactoryManager} from "./components/VaultFactoryManager.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Vault} from "./Vault.sol";

import {IVaultFactory} from "../interfaces/vaults/IVaultFactory.sol";
import {IVault} from "../interfaces/vaults/IVault.sol"
import {IOracle} from "../interfaces/vaults/IOracle.sol";

contract VaultFactory is VaultFactoryManager, IVaultFactory {
    using Clones for address;

    uint256 public constant VAULT_EXPIRY_LIMIT_AFTER_LICENSE = 2628000; // ~ 30.42 days it is more accurate in seconds;

    IOracle public immutable ORACLE;
    address public immutable VAULT_IMPLEMENTATION = address(new Vault());
    address public immutable GOIL_TOKEN;

    address public immutable ROUTER_V3;
    address public immutable ROUTER_V2;
    address public immutable QUOTER;

    VaultInfo[] public allVaults;

    mapping(address => VaultInfo[]) public vaultsByEntity;
    mapping(address => VaultInfo) public vaults;
    mapping(address => bool) public isVault;

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
    ) VaultFactoryManager(_admin, _depositTokens) {
        if (_admin == address(0)) revert AdminCannotBeZeroAddress();
        if (!_isContract(_oracle)) revert OracleMustBeContract();
        if (!_isContract(_goilToken)) revert GoilTokenMustBeContract();
        if (!_isContract(_routerV2)) revert RouterV2MustBeContract();
        if (!_isContract(_routerV3)) revert RouterV3MustBeContract();
        if (!_isContract(_quoter)) revert QuoterMustBeContract();

        ORACLE = IOracle(_oracle);
        GOIL_TOKEN = _goilToken;
        ROUTER_V2 = _routerV2;
        ROUTER_V3 = _routerV3;
        QUOTER = _quoter;
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

        uint256 maxPossiblePoolSize = SCORING.getMaxPossiblePoolSize(msg.sender);
        uint256 maxAllowedPoolSize = _desiredCap + (_interestRate * _lockPeriod) / MAX_BIPS;
        uint256 promisedCap = (_desiredCap * (MAX_BIPS + _interestRate)) / MAX_BIPS;

        if (_desiredCap > maxPossiblePoolSize) revert NotAllowedPoolSize();
        if (maxPossiblePoolSize < maxAllowedPoolSize) revert HighInterestRate();

        uint256 refundableAmount = ORACLE.getPaymentAmountForTokens(_desiredCap);
        uint256 requiredCollateral = TREASURY.getRequiredCollateral(_desiredCap);

        (address vault, VaultInfo memory newVault) = _createVault(
            _depositToken,
            _desiredCap,
            promisedCap,
            _interestRate,
            requiredCollateral,
            refundableAmount,
            _startTime,
            fundingEndTime,
            unlockEndTime
        );

        TREASURY.depositCollateral(
            msg.sender,
            requiredCollateral,
            refundableAmount,
            _desiredCap
        );

        emit VaultCreated(address(vault), msg.sender, newVault);
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

    function getPoolSize(address _vault) public view returns (uint256) {
        return vaults[_vault].desiredCap;
    }

    function getVault(address _vault) public view returns (VaultInfo memory) {
        return vaults[_vault];
    }

    function getVaultsByEntity(
        address _entity
    ) public view returns (VaultInfo[] memory) {
        return vaultsByEntity[_entity];
    }

    function getVaultsCountByEntity(
        address _entity
    ) public view returns (uint256) {
        return vaultsByEntity[_entity].length;
    }

    function getAllVaults() public view returns (VaultInfo[] memory) {
        return allVaults;
    }

    function getVaultsCount() public view returns (uint256) {
        return allVaults.length;
    }

    function getDepositTokens() public view returns (address[] memory) {
        return depositTokens;
    }

    function getDepositTokensCount() public view returns (uint256) {
        return depositTokens.length;
    }

    function _createVault(
        address _depositToken,
        uint256 _desiredCap,
        uint256 _promisedCap,
        uint256 _interestRate,
        uint256 _requiredCollateral,
        uint256 _refundableAmount,
        uint256 _startTime,
        uint256 _fundingEndTime,
        uint256 _unlockEndTime
    ) private returns (address, VaultInfo memory) {
        IVault.VaultParams memory vaultParams = IVault.VaultParams({
            entity: msg.sender,
            scoring: address(SCORING),
            treasury: address(TREASURY),
            staking: address(STAKING),
            goilToken: GOIL_TOKEN,
            depositToken: _depositToken,
            desiredCap: _desiredCap,
            promisedCap: _promisedCap,
            startTime: _startTime,
            fundingEndTime: _fundingEndTime,
            unlockEndTime: _unlockEndTime,
            amountForStaking: ((_promisedCap - _desiredCap) *
                stakingPercentage) / MAX_BIPS
        });

        IVault.DexParams memory dexParams = IVault.DexParams({
            routerV2: ROUTER_V2,
            routerV3: ROUTER_V3,
            quoter: QUOTER
        });

        IVault vault = IVault(VAULT_IMPLEMENTATION.clone());
        vault.initialize(vaultParams, dexParams);

        VaultInfo memory newVault = VaultInfo({
            vault: address(vault),
            entity: msg.sender,
            depositToken: _depositToken,
            interestRate: _interestRate,
            desiredCap: _desiredCap,
            startTime: _startTime,
            fundingEndTime: _fundingEndTime,
            unlockEndTime: _unlockEndTime,
            collateralAmount: _requiredCollateral,
            refundableAmount: _refundableAmount
        });

        isVault[address(vault)] = true;
        vaultsByEntity[msg.sender].push(newVault);
        vaults[address(vault)] = newVault;
        allVaults.push(newVault);

        return (address(vault), newVault);
    }
}
