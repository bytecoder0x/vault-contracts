// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVaultFactory} from "../interfaces/vaults/IVaultFactory.sol";
import {ITreasury} from "../interfaces/vaults/ITreasury.sol";
import {ILicense} from "../interfaces/vaults/ILicense.sol";

contract Treasury is AccessControl, ITreasury {
    using SafeERC20 for IERC20;
    bytes32 MANAGER_ROLE = keccak256("MANAGER_ROLE");

    IVaultFactory public immutable VAULT_FACTORY;
    IERC20 public immutable GOIL_TOKEN;
    ILicense public immutable LICENSE;
    address public immutable SCORING;
    address public immutable STAKING;

    mapping(address => uint256) public collateralDeposited;

    modifier onlyScoring() {
        if (msg.sender != SCORING) revert OnlyScoringAllowed();
        _;
    }

    modifier onlyStaking() {
        if (msg.sender != STAKING) revert OnlyStakingAllowed();
        _;
    }

    constructor(address _goilToken, address _scoring, address _staking, address _license, address _vaultFactory, address _admin) {
        if (!_isContract(_goilToken)) revert GoilTokenMustBeContract();
        if (!_isContract(_scoring)) revert ScoringMustBeContract();
        if (!_isContract(_staking)) revert StakingMustBeContract();
        if (!_isContract(_license)) revert LicenseMustBeContract();
        if (!_isContract(_vaultFactory)) revert VaultFactoryMustBeContract();
        if (_admin == address(0)) revert AdminCannotBeZeroAddress();

        VAULT_FACTORY = IVaultFactory(_vaultFactory);
        LICENSE = ILicense(_license);
        GOIL_TOKEN = IERC20(_goilToken);
        SCORING = _scoring;
        STAKING = _staking;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(MANAGER_ROLE, _admin);
    }

    function depositCollateral(address _entity, uint256 _amount) public {
        if (_amount == 0) revert ZeroAmountToDeposit();

        collateralDeposited[_entity] += _amount;
        GOIL_TOKEN.transferFrom(msg.sender, address(this), _amount);

        emit CollateralDeposited(msg.sender, _entity, _amount);
    }

    function withdrawCollateral(uint256 _amount) external {
        if (_amount == 0) revert ZeroAmountToWithdraw();
        if (LICENSE.getLicenseIsActive(msg.sender)) revert CannotWithdrawDuringActiveLicense();
        if (collateralDeposited[msg.sender] < _amount) revert InsufficientCollateral();

        collateralDeposited[msg.sender] -= _amount;
        GOIL_TOKEN.transfer(msg.sender, _amount);

        emit CollateralWithdrawn(msg.sender, _amount);
    }

    function fundVault(address _vault, uint256 _amount) external onlyScoring {
        if (!VAULT_FACTORY.getIsValidVault(_vault)) revert VaultIsNotValid();
        if (_amount == 0) revert ZeroAmountToFundVault();

        (address owner, , , , , ) = VAULT_FACTORY.vaults(_vault);
        uint256 collateralAmountByOwner = collateralDeposited[owner];

        if (collateralAmountByOwner < _amount) {
            collateralDeposited[owner] = 0;
        } else {
            collateralDeposited[owner] -= _amount;
        }

        GOIL_TOKEN.transfer(_vault, _amount);
        emit VaultFunded(_vault, _amount);
    }

    function transferStakingTokens(address _recipient, uint256 _amount) external onlyStaking {
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

    function _isContract(address _address) private view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_address)
        }
        return (size > 0);
    }
}