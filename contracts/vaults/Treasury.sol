// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVaultFactory} from "../interfaces/vaults/IVaultFactory.sol";
import {IVault} from "../interfaces/vaults/IVault.sol";
import {ITreasury} from "../interfaces/vaults/ITreasury.sol";
import {ILicense} from "../interfaces/vaults/ILicense.sol";
import {IOracle} from "../interfaces/vaults/IOracle.sol";

contract Treasury is AccessControl, ITreasury {
    using SafeERC20 for IERC20;

    bytes32 public constant TREASURY_MANAGER_ROLE = keccak256("TREASURY_MANAGER_ROLE");

    uint256 public constant MAX_COLLATERAL_PERCENTAGE = 100_00;

    IVaultFactory public immutable VAULT_FACTORY;
    IERC20 public immutable GOIL_TOKEN;
    IOracle public immutable ORACLE;
    ILicense public LICENSE;
    address public SCORING;
    address public STAKING;

    uint256 public requiredCollateralPercentage = 10_00;
    uint256 public totalRefundableAmount;

    mapping(address => Collateral) public collateral;

    modifier onlyScoring() {
        if (msg.sender != SCORING) revert OnlyScoringAllowed();
        _;
    }

    modifier onlyStaking() {
        if (msg.sender != STAKING) revert OnlyStakingAllowed();
        _;
    }

    modifier onlyVaultFactory() {
        if (msg.sender != address(VAULT_FACTORY)) revert OnlyVaultFactoryAllowed();
        _;
    }

    modifier onlyVault() {
        if (!VAULT_FACTORY.isVault(msg.sender)) revert OnlyVaultAllowed();
        _;
    }

    modifier onlyLicense() {
        if (msg.sender != address(LICENSE)) revert OnlyLicenseAllowed();
        _;
    }

    modifier withLockedRefundableAmount() {
        _;
        if (getGoilBalance() < totalRefundableAmount) revert InsufficientRefundableAmount();
    }

    modifier withSetupNecessaryContracts() {
        if (SCORING == address(0)) revert ScoringContractNotSet();
        if (STAKING == address(0)) revert StakingContractNotSet();
        if (address(LICENSE) == address(0)) revert LicenseContractNotSet();
        _;
    }

    constructor(
        address _goilToken,
        address _oracle,
        address _vaultFactory,
        address _admin
    ) {
        if (!_isContract(_goilToken)) revert GoilTokenMustBeContract();
        if (!_isContract(_oracle)) revert OracleMustBeContract();
        if (!_isContract(_vaultFactory)) revert VaultFactoryMustBeContract();
        if (_admin == address(0)) revert AdminCannotBeZeroAddress();

        VAULT_FACTORY = IVaultFactory(_vaultFactory);
        ORACLE = IOracle(_oracle);
        GOIL_TOKEN = IERC20(_goilToken);

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(TREASURY_MANAGER_ROLE, _admin);
    }

    function depositCollateral(
        address _entity,
        uint256 _amount
    ) public onlyLicense withSetupNecessaryContracts {
        if (_amount == 0) revert ZeroAmountToDeposit();

        collateral[_entity].collateralLocked += _amount;
        GOIL_TOKEN.transferFrom(msg.sender, address(this), _amount);

        emit CollateralDeposited(_entity, _amount);
    }

    function depositCollateral(
        address _entity,
        uint256 _requiredCollateral,
        uint256 _refundableAmount
    ) external onlyVaultFactory withSetupNecessaryContracts {
        collateral[_entity].collateralLocked += _requiredCollateral;
        totalRefundableAmount += _refundableAmount;

        GOIL_TOKEN.transferFrom(_entity, address(this), _requiredCollateral);
        emit CollateralDeposited(_entity, _requiredCollateral);
    }

    function withdrawCollateral() external withSetupNecessaryContracts withLockedRefundableAmount {
        address entity = msg.sender;
        uint256 collateralAmount;

        if (LICENSE.getLicenseIsActive(entity)) {
            collateralAmount = collateral[entity].collateralUnlocked;
            collateral[entity].collateralUnlocked = 0;
        } else {
            collateralAmount = collateral[entity].collateralLocked + collateral[entity].collateralUnlocked;
            collateral[entity].collateralLocked = 0;
            collateral[entity].collateralUnlocked = 0;
            // TODO: thing about collateral on locked vaults after license expiration
        }

        if (collateralAmount == 0) revert NoCollateralToWithdraw();

        GOIL_TOKEN.transfer(entity, collateralAmount);
        emit CollateralWithdrawn(entity, collateralAmount);
    }

    function unlockCollateral(address _vault) external onlyScoring withSetupNecessaryContracts {
        address entity = IVault(_vault).ENTITY();
        uint256 collateralAmount = VAULT_FACTORY.getCollateralAmount(_vault);
        uint256 refundableAmount = VAULT_FACTORY.getRefundableAmount(_vault);

        totalRefundableAmount -= refundableAmount;

        collateral[entity].collateralLocked -= collateralAmount;
        collateral[entity].collateralUnlocked += collateralAmount; 

        emit CollateralUnlocked(entity, collateralAmount);
    }

    function fundVault() external onlyVault withSetupNecessaryContracts {
        address vault = msg.sender;

        address entity = IVault(vault).ENTITY();
        uint256 refundableAmount = VAULT_FACTORY.getRefundableAmount(vault);
        uint256 collateralAmountByEntity = collateral[entity].collateralLocked;

        if (collateralAmountByEntity < refundableAmount) {
            collateral[entity].collateralLocked = 0;
        } else {
            collateral[entity].collateralLocked -= refundableAmount;
        }

        totalRefundableAmount -= refundableAmount;

        GOIL_TOKEN.transfer(vault, refundableAmount);
        emit VaultFunded(vault, refundableAmount);
    }

    function unstakeTokens(
        address _recipient,
        uint256 _amount
    )
        external
        onlyStaking
        withSetupNecessaryContracts
        withLockedRefundableAmount
    {
        if (_recipient == address(0)) revert RecipientCannotBeZeroAddress();
        if (_amount == 0) revert ZeroAmountToTransfer();

        GOIL_TOKEN.transfer(_recipient, _amount);
        emit StakingTokensTransferred(_recipient, _amount);
    }

    function setRequiredCollateralPercentage(
        uint256 _requiredCollateralPercentage
    ) external onlyRole(TREASURY_MANAGER_ROLE) {
        if (_requiredCollateralPercentage == 0) revert RequiredCollateralPercentageCannotBeZero();
        if (_requiredCollateralPercentage == requiredCollateralPercentage) revert RequiredCollateralPercentageCannotBeTheSame();
        if (_requiredCollateralPercentage > MAX_COLLATERAL_PERCENTAGE) revert RequiredCollateralPercentageTooHigh();

        requiredCollateralPercentage = _requiredCollateralPercentage;
        emit RequiredCollateralPercentageUpdated(_requiredCollateralPercentage);
    }

    function withdrawTokens(
        address _recipient,
        address _token,
        uint256 _amount
    ) external withLockedRefundableAmount onlyRole(TREASURY_MANAGER_ROLE) {
        IERC20(_token).safeTransfer(_recipient, _amount);
    }

    function withdrawAllTokens(
        address _token
    ) external withLockedRefundableAmount onlyRole(TREASURY_MANAGER_ROLE) {
        uint256 balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, balance);
    }

    function setScoringContract(address _scoring) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (SCORING != address(0)) revert ScoringAlreadySet();
        if (!_isContract(_scoring)) revert ScoringMustBeContract();

        SCORING = _scoring;
        emit ScoringContractUpdated(_scoring);
    }

    function setStakingContract(address _staking) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (STAKING != address(0)) revert StakingAlreadySet();
        if (!_isContract(_staking)) revert StakingMustBeContract();

        STAKING = _staking;
        emit StakingContractUpdated(_staking);
    }

    function setLicenseContract(address _license) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (address(LICENSE) != address(0)) revert LicenseAlreadySet();
        if (!_isContract(_license)) revert LicenseMustBeContract();

        LICENSE = ILicense(_license);
        emit LicenseContractUpdated(_license);
    }

    function getRequiredCollateral(uint256 _poolSize) public view returns (uint256) {
        uint256 poolSizeInGoil = ORACLE.getTokenAmountForPayment(_poolSize);
        uint256 defaultCollateral = poolSizeInGoil * requiredCollateralPercentage / MAX_COLLATERAL_PERCENTAGE;
        uint256 totalBalanceGoil = GOIL_TOKEN.balanceOf(address(this));

        if (totalBalanceGoil < totalRefundableAmount + poolSizeInGoil) {
            return poolSizeInGoil - (totalBalanceGoil - totalRefundableAmount);
        }

        return defaultCollateral;        
    }

    function getGoilBalance() public view returns (uint256) {
        return GOIL_TOKEN.balanceOf(address(this));
    }

    function _isContract(address _address) private view returns (bool) {
        uint32 size;

        assembly {
            size := extcodesize(_address)
        }
        return (size > 0);
    }
}