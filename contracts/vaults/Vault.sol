// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IScoring} from "../interfaces/vaults/IScoring.sol";

contract Vault is Initializable, ERC4626Upgradeable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    error DesiredCapCannotBeZero();
    error InterestRateCannotBeZero();
    error StartTimeMustBeInFuture();
    error WithdrawMoreThanMax();
    error VaultNotStarted();
    error VaultFundingTimeIsEnded();
    error VaultNotExpired();
    error ExceedsVaultSize();
    error InsufficientBalance();
    error FundingEndTimeMustBeBeforeUnlockEndTime();
    error StartTimeMustBeBeforeFundingEndTime();
    error ScoringContractMustBeContract();
    error DepositTokenMustBeContract();
    error GoilTokenMustBeContract();
    error AmountToDepositCannotBeZero();
    error AmountToWithdrawCannotBeZero();
    error FundingEndTimeIsNotReached();
    error VaultIsNotUnlocked();
    error VaultIsNotFailed();

    uint256 public constant MAX_BIPS = 100_00;

    IScoring public SCORING;
    IERC20Upgradeable public GOIL_TOKEN;

    bool public isVaultFailed;

    uint256 public goilRate;
    uint256 public desiredCap;
    uint256 public promisedCap;
    uint256 public interestRate;
    uint256 public startTime;
    uint256 public fundingEndTime;
    uint256 public unlockEndTime;
    uint256 public totalDeposits;

    event DepositFromEntity(uint256 amount);
    event WithdrawToEntity(uint256 amount);

    function initialize(
        address _entity,
        address _scoring,
        address _depositToken,
        address _goilToken,
        uint256 _interestRate, 
        uint256 _desiredCap,
        uint256 _startTime,
        uint256 _fundingEndTime,
        uint256 _unlockEndTime
    ) external initializer {
        if (!_isContract(_scoring)) revert ScoringContractMustBeContract();
        if (!_isContract(_depositToken)) revert DepositTokenMustBeContract();
        if (!_isContract(_goilToken)) revert GoilTokenMustBeContract();
        if (_desiredCap == 0) revert DesiredCapCannotBeZero();
        if (_interestRate == 0) revert InterestRateCannotBeZero();
        if (_startTime <= block.timestamp) revert StartTimeMustBeInFuture();
        if (_fundingEndTime <= _startTime) revert StartTimeMustBeBeforeFundingEndTime();
        if (_unlockEndTime <= _fundingEndTime) revert FundingEndTimeMustBeBeforeUnlockEndTime();

        uint256 maxPoolSize = IScoring(_scoring).getMaxPoolSize(_entity);
        uint256 unlockPeriod = _unlockEndTime - _fundingEndTime;
        uint256 _promisedCap = _desiredCap + interestRate * unlockPeriod / MAX_BIPS;
        
        if (_desiredCap > maxPoolSize || promisedCap > maxPoolSize) revert ExceedsVaultSize();

        __ERC4626_init(IERC20Upgradeable(_depositToken));
        __Ownable_init();
        transferOwnership(_entity);

        SCORING = IScoring(_scoring);
        GOIL_TOKEN = IERC20Upgradeable(_goilToken);
        desiredCap = _desiredCap;
        promisedCap = _promisedCap;
        interestRate = _interestRate;
        startTime = _startTime;
        fundingEndTime = _fundingEndTime;
        unlockEndTime = _unlockEndTime;
    }

    function depositToVault(uint256 _amountToDeposit) public {
        depositToVault(_amountToDeposit, msg.sender);
    }

    function withdrawFromVault(uint256 _amountToWithdraw) public {
        withdrawFromVault(_amountToWithdraw, msg.sender, msg.sender);
    }

    function depositToVault(uint256 _amountToDeposit, address _receiverShares) public {
        uint256 currentTime = block.timestamp;

        if (currentTime < startTime) revert VaultNotStarted();
        if (currentTime > fundingEndTime) revert VaultFundingTimeIsEnded();
        if (totalAssets() + _amountToDeposit > desiredCap) revert ExceedsVaultSize();

        super.deposit(_amountToDeposit, _receiverShares);
    }

    function withdrawFromVault(uint256 _amountToWithdraw, address _receiver, address _holderShares) public {
        uint256 currentTime = block.timestamp;
        bool isNotRaisedDesiredCap = currentTime > fundingEndTime && totalAssets() < desiredCap;

        if (isNotRaisedDesiredCap) {
            super.withdraw(_amountToWithdraw, _receiver, _holderShares);
        }

        if (currentTime <= unlockEndTime) {
            revert VaultIsNotUnlocked();
        }

        if (!isVaultFailed && currentTime > unlockEndTime && totalAssets() < promisedCap) {
            isVaultFailed = true;
            _asset = GOIL_TOKEN;
            SCORING.updateEntityScore();
        }

        super.withdraw(_amountToWithdraw, _receiver, _holderShares);
    }

    function depositFromEntity() external onlyOwner {
        uint256 currentTime = block.timestamp;

        if (currentTime <= fundingEndTime) revert FundingEndTimeIsNotReached();
        IERC20Upgradeable(asset()).safeTransferFrom(msg.sender, address(this), promisedCap);
        
        if (!isVaultFailed) {
            SCORING.updateEntityScore();
        } else {
            // TODO: swap stable to goil and send to treasury
        }

        unlockEndTime = currentTime;
        emit DepositFromEntity(promisedCap);
    }

    function withdrawToEntity() external onlyOwner {
        uint256 currentTime = block.timestamp;

        if (currentTime <= fundingEndTime) revert FundingEndTimeIsNotReached();
        if (totalAssets() < desiredCap) revert InsufficientBalance();

        IERC20Upgradeable(asset()).safeTransfer(msg.sender, totalAssets());
        emit WithdrawToEntity(totalAssets());
    }

    function _isContract(address _address) private view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_address)
        }
        return (size > 0);
    }
}