// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {ERC4626Upgradeable} from "./ERC4626/ERC4626Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {SwapHandler} from "../components/SwapHandler.sol";

import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IScoring} from "../interfaces/vaults/IScoring.sol";
import {IVault} from "../interfaces/vaults/IVault.sol";
import {IStaking} from "../interfaces/vaults/IStaking.sol";

contract Vault is Initializable, ERC4626Upgradeable, SwapHandler, IVault {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint256 public constant MAX_BIPS = 100_00;
    uint24 public constant FAILURE_RATE_PRECISION = 100_000;

    IScoring public SCORING;
    IStaking public STAKING;
    IERC20Upgradeable public GOIL_TOKEN;
    address public TREASURY;
    address public DEPOSIT_TOKEN;
    address public ENTITY;

    bool public isVaultSuccess;
    bool public isVaultLiquidated;

    uint24 public failureRate; // it can be 0 to 100_000

    uint256 public desiredCap;
    uint256 public promisedCap;
    uint256 public startTime;
    uint256 public fundingEndTime;
    uint256 public unlockEndTime;
    uint256 public totalDeposits;
    uint256 public refundableAmountInGoil;
    uint256 public amountForStaking;

    modifier onlyEntity() {
        if (msg.sender != ENTITY) revert OnlyEntityCanCall();
        _;
    }

    function initialize(VaultParams calldata _vaultParams, DexParams calldata _dexParams) external initializer {
        if (_vaultParams.entity == address(0)) revert EntityCannotBeZeroAddress();
        if (_vaultParams.startTime < block.timestamp) revert StartTimeCannotBeInThePast();
        if (_vaultParams.fundingEndTime < _vaultParams.startTime) revert FundingEndTimeCannotBeBeforeStartTime();
        if (_vaultParams.unlockEndTime < _vaultParams.fundingEndTime) revert UnlockEndTimeCannotBeBeforeFundingEndTime();
        
        __ERC4626_init(IERC20Upgradeable(_vaultParams.depositToken));
        __SwapHandler_init(_dexParams.routerV2, _dexParams.routerV3, _dexParams.quoter);
        
        SCORING = IScoring(_vaultParams.scoring);
        STAKING = IStaking(_vaultParams.staking);
        GOIL_TOKEN = IERC20Upgradeable(_vaultParams.goilToken);
        DEPOSIT_TOKEN = _vaultParams.depositToken;
        TREASURY = _vaultParams.treasury;
        ENTITY = _vaultParams.entity;
        desiredCap = _vaultParams.desiredCap;
        promisedCap = _vaultParams.promisedCap;
        startTime = _vaultParams.startTime;
        fundingEndTime = _vaultParams.fundingEndTime;
        unlockEndTime = _vaultParams.unlockEndTime;
        refundableAmountInGoil = _vaultParams.refundableAmountInGoil;
        amountForStaking = _vaultParams.amountForStaking;
    }

    function deposit(uint256 _amountToDeposit) public returns (uint256) {
        return deposit(_amountToDeposit, msg.sender);
    }

    function withdraw(uint256 _amountToWithdraw) public returns (uint256) {
        return withdraw(_amountToWithdraw, msg.sender, msg.sender);
    }

    function depositFromEntity() external onlyEntity {
        if (block.timestamp <= fundingEndTime) revert FundingEndTimeIsNotReached();
        if (!isVaultLiquidated) isVaultSuccess = true;

        IERC20Upgradeable token = IERC20Upgradeable(asset());
        token.safeTransferFrom(msg.sender, address(this), promisedCap);

        if (isVaultSuccess) {
            _handleSuccessfulVault();
        } else {
            _handleFailedVault();
        }

        unlockEndTime = block.timestamp;
        emit DepositFromEntity(promisedCap);
    }

    function withdrawToEntity() external onlyEntity {
        uint256 currentTime = block.timestamp;

        if (currentTime <= fundingEndTime) revert FundingEndTimeIsNotReached();
        if (currentTime >= unlockEndTime) revert VaultIsUnlocked();
        if (totalAssets() < desiredCap) revert InsufficientBalance();

        IERC20Upgradeable(asset()).safeTransfer(msg.sender, totalAssets());
        emit WithdrawToEntity(totalAssets());
    }

    function liquidate() external {
        if (!isLiquidatable()) revert VaultIsNotLiquidatable();

        _liquidate();
    }

    // explanation why we can't move that to internal "_withdraw" function:
    // In these functions "withdraw" and "redeem" check on possible amount of assets to withdraw
    // In example when vault is liquidatable we firstly check amount of assets to withdraw and
    // user can't withdraw more since amount of assets 0 and we need to liquidate vault first
    function withdraw(uint256 _assets, address _receiver, address _owner) public override returns (uint256) {
        if (isLiquidatable()) _liquidate();
        return super.withdraw(_assets, _receiver, _owner);
    }

    function redeem(uint256 _shares, address _receiver, address _owner) public override returns (uint256) {
        if (isLiquidatable()) _liquidate();
        return super.redeem(_shares, _receiver, _owner);
    }

    function getVaultState() public view returns (VaultState) {
        uint256 currentTime = block.timestamp;
        
        if (currentTime < startTime) return VaultState.NOT_STARTED;
        if (currentTime > startTime && currentTime < fundingEndTime) return VaultState.FUNDING;
        if (isNotRaisedDesiredCap()) return VaultState.NOT_RAISED;
        if (isLiquidatable()) return VaultState.LIQUIDATED;
        if (isVaultSuccess) return VaultState.SUCCESS;

        return VaultState.LOCKED;
    }

    function isLiquidatable() public view returns (bool) {
        uint256 currentTime = block.timestamp;

        return !isVaultLiquidated 
            && !isVaultSuccess 
            && currentTime > unlockEndTime 
            && totalAssets() < promisedCap;
    }

    function isNotRaisedDesiredCap() public view returns (bool) {
        uint256 currentTime = block.timestamp;

        return currentTime < unlockEndTime
            && currentTime > fundingEndTime
            && totalAssets() < desiredCap;
    }

    function _handleSuccessfulVault() private {
        SCORING.updateEntityScore();

        uint256 stakingAmountInGoil = _swap(amountForStaking, address(this), address(GOIL_TOKEN), DEPOSIT_TOKEN);
        GOIL_TOKEN.approve(address(STAKING), stakingAmountInGoil);
        STAKING.depositReward(stakingAmountInGoil);
    }

    function _handleFailedVault() private {
        uint256 currentBalanceGoil = totalAssets();
        _updateAsset(DEPOSIT_TOKEN);

        if (refundableAmountInGoil > currentBalanceGoil) {
            uint256 notWithdrawnGoil = refundableAmountInGoil - currentBalanceGoil;
            uint256 notWithdrawnPercentage = (notWithdrawnGoil * MAX_BIPS) / refundableAmountInGoil;

            uint256 depositAmount = (promisedCap * notWithdrawnPercentage) / MAX_BIPS;
            uint256 amountToTreasury = promisedCap - depositAmount;

            _swap(amountToTreasury, TREASURY, address(GOIL_TOKEN), DEPOSIT_TOKEN);
            GOIL_TOKEN.transfer(TREASURY, notWithdrawnGoil);
        } else {
            GOIL_TOKEN.transfer(TREASURY, currentBalanceGoil);
        }
    }

    function _deposit(
        address _caller,
        address _receiver,
        uint256 _assets,
        uint256 _shares
    ) internal virtual override {
        uint256 currentTime = block.timestamp;

        if (currentTime < startTime) revert VaultNotStarted();
        if (currentTime > fundingEndTime) revert VaultFundingTimeIsEnded();
        if (totalAssets() + _assets > desiredCap) revert ExceedsVaultSize();

        super._deposit(_caller, _receiver, _assets, _shares);
    }

    function _withdraw(
        address _caller,
        address _receiver,
        address _owner,
        uint256 _assets,
        uint256 _shares
    ) internal virtual override {
        uint256 currentTime = block.timestamp;

        if (isNotRaisedDesiredCap()) {
            return super._withdraw(_caller, _receiver, _owner, _assets, _shares);
        }
        
        if (currentTime < unlockEndTime) revert VaultIsNotUnlocked();

        super._withdraw(_caller, _receiver, _owner, _assets, _shares);
    }

    function _updateAsset(address _newAsset) private {
        //! _tryGetAssetDecimals, _asset and _underlyingDecimals in ERC4626Upgradeable must be internal for this case
        (bool success, uint8 assetDecimals) = _tryGetAssetDecimals(IERC20Upgradeable(_newAsset));
        _underlyingDecimals = success ? assetDecimals : 18;
        _asset = IERC20Upgradeable(_newAsset);
    }

    function _liquidate() private {
        isVaultLiquidated = true;
        failureRate = FAILURE_RATE_PRECISION;
        _updateAsset(address(GOIL_TOKEN));

        SCORING.updateEntityScore();
    }

    function _isContract(address _address) private view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_address)
        }
        return (size > 0);
    }
}