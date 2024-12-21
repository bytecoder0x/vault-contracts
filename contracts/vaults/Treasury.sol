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
    bytes32 MANAGER_ROLE = keccak256("MANAGER_ROLE");

    uint256 public constant MAX_COLLATERAL_PERCENTAGE = 100_00;
    uint256 public constant REQUIRED_COLLATERAL_PERCENTAGE = 10_00;

    IVaultFactory public immutable VAULT_FACTORY;
    IERC20 public immutable GOIL_TOKEN;
    IOracle public immutable ORACLE;
    ILicense public immutable LICENSE;
    address public immutable SCORING;
    address public immutable STAKING;

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

    modifier onlyLicense() {
        if (msg.sender != address(LICENSE)) revert OnlyLicenseAllowed();
        _;
    }

    constructor(
        address _goilToken,
        address _scoring,
        address _staking,
        address _license,
        address _oracle,
        address _vaultFactory,
        address _admin
    ) {
        if (!_isContract(_goilToken)) revert GoilTokenMustBeContract();
        if (!_isContract(_oracle)) revert OracleMustBeContract();
        if (!_isContract(_scoring)) revert ScoringMustBeContract();
        if (!_isContract(_staking)) revert StakingMustBeContract();
        if (!_isContract(_license)) revert LicenseMustBeContract();
        if (!_isContract(_vaultFactory)) revert VaultFactoryMustBeContract();
        if (_admin == address(0)) revert AdminCannotBeZeroAddress();

        VAULT_FACTORY = IVaultFactory(_vaultFactory);
        LICENSE = ILicense(_license);
        ORACLE = IOracle(_oracle);
        GOIL_TOKEN = IERC20(_goilToken);
        SCORING = _scoring;
        STAKING = _staking;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(MANAGER_ROLE, _admin);
    }

    function depositCollateral(address _entity, uint256 _amount) public onlyLicense {
        if (_amount == 0) revert ZeroAmountToDeposit();

        collateral[_entity].collateralLocked += _amount;
        GOIL_TOKEN.transferFrom(msg.sender, address(this), _amount);

        emit CollateralDeposited(msg.sender, _entity, address(0), _amount);
    }

    function depositCollateral(address _vault) external onlyVaultFactory {
        IVault vault = IVault(_vault);
        address entity = vault.owner();

        uint256 requiredCollateral = VAULT_FACTORY.getCollateralAmount(_vault);
        uint256 refundableAmount = VAULT_FACTORY.getRefundableAmount(_vault);

        collateral[entity].collateralLocked += requiredCollateral;
        totalRefundableAmount += refundableAmount;

        GOIL_TOKEN.transferFrom(entity, address(this), requiredCollateral);
        emit CollateralDeposited(entity, entity, _vault, requiredCollateral);
    }

    function withdrawCollateral(uint256 _amount) external {
        if (_amount == 0) revert ZeroAmountToWithdraw();

        address entity = msg.sender;

        if (LICENSE.getLicenseIsActive(entity)) {
            if (collateral[entity].collateralUnlocked < _amount) revert InsufficientCollateral();
            collateral[entity].collateralUnlocked -= _amount;
        }

        if (collateral[entity].collateralLocked < _amount) revert InsufficientCollateral();
        collateral[entity].collateralLocked -= _amount;

        GOIL_TOKEN.transfer(entity, _amount);
        emit CollateralWithdrawn(entity, _amount);
    }

    function unlockCollateral(address _vault) external onlyScoring {
        IVault vault = IVault(_vault);
        address entity = vault.owner();
        uint256 collateralAmount = VAULT_FACTORY.getCollateralAmount(_vault);

        collateral[entity].collateralUnlocked += collateralAmount;
        emit CollateralUnlocked(entity, collateralAmount);
    }

    function fundVault(address _vault) external onlyScoring {
        if (!VAULT_FACTORY.getIsValidVault(_vault)) revert VaultIsNotValid();

        address entity = VAULT_FACTORY.getVaultEntity(_vault);
        uint256 refundableAmount = VAULT_FACTORY.getRefundableAmount(_vault);
        uint256 collateralAmountByEntity = collateral[entity].collateralLocked;

        if (collateralAmountByEntity < refundableAmount) {
            collateral[entity].collateralLocked = 0;
        } else {
            collateral[entity].collateralLocked -= refundableAmount;
        }

        GOIL_TOKEN.transfer(_vault, refundableAmount);
        emit VaultFunded(_vault, refundableAmount);
    }

    function unstakeTokens(address _recipient, uint256 _amount) external onlyStaking {
        if (_recipient == address(0)) revert RecipientCannotBeZeroAddress();
        if (_amount == 0) revert ZeroAmountToTransfer();

        GOIL_TOKEN.transfer(_recipient, _amount);
        emit StakingTokensTransferred(_recipient, _amount);
    }

    function withdrawTokens(address _recipient, address _token, uint256 _amount) external onlyRole(MANAGER_ROLE) {
        IERC20(_token).safeTransfer(_recipient, _amount);
    }

    function withdrawAllTokens(address _token) external onlyRole(MANAGER_ROLE) {
        uint256 balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, balance);
    }

    function getRequiredCollateral(uint256 _poolSize) public view returns (uint256) {
        uint256 poolSizeInGoil = ORACLE.getTokenAmountForPayment(_poolSize);
        uint256 defaultCollateral = poolSizeInGoil * REQUIRED_COLLATERAL_PERCENTAGE / MAX_COLLATERAL_PERCENTAGE;
        uint256 totalBalanceGoil = GOIL_TOKEN.balanceOf(address(this));

        if (totalBalanceGoil < totalRefundableAmount + poolSizeInGoil) {
            return poolSizeInGoil - (totalBalanceGoil - totalRefundableAmount);
        }

        return defaultCollateral;        
    }

    function _isContract(address _address) private view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_address)
        }
        return (size > 0);
    }
}