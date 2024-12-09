// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract Vault is Initializable, ERC4626Upgradeable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    error InvalidTokenAddress();
    error StartDateAfterEndDate();
    error DesiredCapCannotBeZero();
    error InterestRateCannotBeZero();
    error StartTimeMustBeInFuture();
    error EndTimeMustBeInTheFuture();
    error VaultNotStarted();
    error VaultExpired();
    error VaultNotExpired();
    error FundingEndTimeCannotBeZero();
    error UnlockEndTimeCannotBeZero();
    error ExceedsVaultSize();
    error InsufficientBalance();
    error FundingEndTimeMustBeBeforeUnlockEndTime();
    error MustProvideDepositToken();
    error CannotBeTwoDepositTokens();
    error StartTimeMustBeBeforeFundingEndTime();

    uint256 public constant MAX_BIPS = 100_00;

    bool public isNativeToken;
    uint256 public desiredCap;
    uint256 public interestRate;
    uint256 public startTime;
    uint256 public fundingEndTime;
    uint256 public unlockEndTime;
    uint256 public totalDeposits;

    event InterestDeposited(uint256 amount);
    event InterestWithdrawn(uint256 amount);

    function initialize(
        bool _isNativeToken,
        address _depositToken,
        uint256 _interestRate, 
        uint256 _desiredCap,
        uint256 _startTime,
        uint256 _fundingEndTime,
        uint256 _unlockEndTime
    ) external initializer {
        if (!_isNativeToken && _depositToken == address(0)) revert MustProvideDepositToken();
        if (_isNativeToken && _depositToken != address(0)) revert CannotBeTwoDepositTokens();
        if (_desiredCap == 0) revert DesiredCapCannotBeZero();
        if (_interestRate == 0) revert InterestRateCannotBeZero();
        if (_startTime <= block.timestamp) revert StartTimeMustBeInFuture();
        if (_fundingEndTime <= _startTime) revert StartTimeMustBeBeforeFundingEndTime();
        if (_unlockEndTime <= _fundingEndTime) revert FundingEndTimeMustBeBeforeUnlockEndTime();

        __ERC4626_init(IERC20Upgradeable(_depositToken));
        __Ownable_init();

        isNativeToken = _isNativeToken;
        desiredCap = _desiredCap;
        interestRate = _interestRate;
        startTime = _startTime;
        fundingEndTime = _fundingEndTime;
        unlockEndTime = _unlockEndTime;
    }

    function deposit(uint256 assets, address receiver) public override returns (uint256) {
        if (block.timestamp < startTime) revert VaultNotStarted();
        if (block.timestamp > fundingEndTime) revert VaultExpired();
        if (totalAssets() + assets > desiredCap) revert ExceedsVaultSize();

        totalDeposits += assets;
        return super.deposit(assets, receiver);
    }

    function withdraw(uint256 assets, address receiver, address ownerAddr) public override returns (uint256) {
        if (block.timestamp >= fundingEndTime && totalDeposits < desiredCap) {
            return super.withdraw(assets, receiver, ownerAddr);
        }
        if (block.timestamp < unlockEndTime) revert VaultNotExpired();
        return super.withdraw(assets, receiver, ownerAddr);
    }

    function depositInterest() external onlyOwner {
        IERC20Upgradeable assetToken = IERC20Upgradeable(asset());
        uint256 interestAmount = (desiredCap * interestRate) / MAX_BIPS + desiredCap;
        assetToken.safeTransferFrom(msg.sender, address(this), interestAmount);
        unlockEndTime = block.timestamp;
        emit InterestDeposited(interestAmount);
    }

    function withdrawInterest() external onlyOwner {
        if (block.timestamp < fundingEndTime) revert VaultNotExpired();
        if (totalDeposits < desiredCap) revert InsufficientBalance();
        IERC20Upgradeable assetToken = IERC20Upgradeable(asset());
        assetToken.safeTransfer(owner(), totalDeposits);
        emit InterestWithdrawn(totalDeposits);
    }
}