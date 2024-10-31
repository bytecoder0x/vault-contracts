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
    error StartTimeMustBeInTheFuture();
    error EndTimeMustBeInTheFuture();
    error VaultNotStarted();
    error VaultExpired();
    error VaultNotExpired();
    error ExpirationPeriodCannotBeZero();
    error ExceedsVaultSize();
    error InsufficientBalance();

    uint256 public interestRate;
    uint256 public desiredCap;
    uint256 public startTime;
    uint256 public endTime;

    event InterestDeposited(uint256 amount);
    event InterestWithdrawn(uint256 amount);

    function initialize(
        address _depositToken,
        uint256 _interestRate,
        uint256 _desiredCap,
        uint256 _startTime,
        uint256 _expirationPeriod
    ) external initializer {
        if (_depositToken == address(0)) revert InvalidTokenAddress();
        if (_desiredCap == 0) revert DesiredCapCannotBeZero();
        if (_interestRate == 0) revert InterestRateCannotBeZero();
        if (_startTime <= block.timestamp) revert StartTimeMustBeInTheFuture();
        if (_expirationPeriod == 0) revert ExpirationPeriodCannotBeZero();

        __ERC4626_init(IERC20Upgradeable(_depositToken));
        __Ownable_init();

        interestRate = _interestRate;
        desiredCap = _desiredCap;
        startTime = _startTime;
        endTime = _startTime + _expirationPeriod;
    }

    function deposit(uint256 assets, address receiver) public override returns (uint256) {
        if (block.timestamp < startTime) revert VaultNotStarted();
        if (block.timestamp > endTime) revert VaultExpired();
        if (totalAssets() + assets > desiredCap) revert ExceedsVaultSize();

        return super.deposit(assets, receiver);
    }

    function withdraw(uint256 assets, address receiver, address ownerAddr) public override returns (uint256) {
        if (block.timestamp < endTime) revert VaultNotExpired();
        return super.withdraw(assets, receiver, ownerAddr);
    }

    function depositInterest() external onlyOwner {
        IERC20Upgradeable assetToken = IERC20Upgradeable(asset());
        assetToken.safeTransferFrom(msg.sender, address(this), desiredCap);
        endTime = block.timestamp;
        emit InterestDeposited(desiredCap);
    }

    function withdrawInterest(uint256 amount) external onlyOwner {
        if (block.timestamp < endTime) revert VaultNotExpired();
        IERC20Upgradeable assetToken = IERC20Upgradeable(asset());
        assetToken.safeTransfer(owner(), amount);
        emit InterestWithdrawn(amount);
    }
}