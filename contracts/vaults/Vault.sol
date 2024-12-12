// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IScoring} from "../interfaces/vaults/IScoring.sol";
import {ITreasury} from "../interfaces/vaults/ITreasury.sol";

contract Vault is Initializable, ERC4626Upgradeable, OwnableUpgradeable {
    error DesiredCapCannotBeZero();
    error InterestRateCannotBeZero();
    error StartTimeMustBeInFuture();
    error VaultNotStarted();
    error VaultFundingTimeIsEnded();
    error VaultNotExpired();
    error ExceedsVaultSize();
    error InsufficientBalance();
    error FundingEndTimeMustBeBeforeUnlockEndTime();
    error StartTimeMustBeBeforeFundingEndTime();
    error ScoringContractMustBeContract();
    error DepositTokenMustBeContract();
    error AmountToFundCannotBeZero();
    error AmountToWithdrawCannotBeZero();
    error FundingEndTimeIsNotReached();
    error VaultIsNotUnlocked();
    error VaultIsNotFailed();

    uint256 public constant MAX_BIPS = 100_00;

    IScoring public immutable SCORING_CONTRACT;
    ITreasury public immutable TREASURY_CONTRACT;

    uint256 public desiredCap;
    uint256 public promisedCap;
    uint256 public interestRate;
    uint256 public startTime;
    uint256 public fundingEndTime;
    uint256 public unlockEndTime;
    uint256 public totalDeposits;

    event PartiallyDepositedFromEntity(uint256 amount);
    event FullyDepositedFromEntity();
    event WithdrawToEntity(uint256 amount);

    function initialize(
        address _entity,
        address _scoringContract,
        address _depositToken,
        uint256 _interestRate, 
        uint256 _desiredCap,
        uint256 _startTime,
        uint256 _fundingEndTime,
        uint256 _unlockEndTime
    ) external initializer {
        if (!_isContract(_scoringContract)) revert ScoringContractMustBeContract();
        if (!_isContract(_depositToken)) revert DepositTokenMustBeContract();
        if (_desiredCap == 0) revert DesiredCapCannotBeZero();
        if (_interestRate == 0) revert InterestRateCannotBeZero();
        if (_startTime <= block.timestamp) revert StartTimeMustBeInFuture();
        if (_fundingEndTime <= _startTime) revert StartTimeMustBeBeforeFundingEndTime();
        if (_unlockEndTime <= _fundingEndTime) revert FundingEndTimeMustBeBeforeUnlockEndTime();

        uint256 maxPoolSize = IScoring(_scoringContract).getMaxPoolSize(_entity);
        uint256 unlockPeriod = _unlockEndTime - _fundingEndTime;
        uint256 _promisedCap = _desiredCap + interestRate * unlockPeriod / MAX_BIPS;
        
        if (_desiredCap > maxPoolSize || promisedCap > maxPoolSize) revert ExceedsVaultSize();

        __ERC4626_init(IERC20(_depositToken));
        __Ownable_init(_entity);

        desiredCap = _desiredCap;
        promisedCap = _promisedCap;
        interestRate = _interestRate;
        startTime = _startTime;
        fundingEndTime = _fundingEndTime;
        unlockEndTime = _unlockEndTime;
    }

    function deposit(uint256 _amountToDeposit, address _receiverShares) public override returns (uint256) {
        uint256 currentTime = block.timestamp;

        if (currentTime < startTime) revert VaultNotStarted();
        if (currentTime > fundingEndTime) revert VaultFundingTimeIsEnded();
        if (totalAssets() + _amountToDeposit > desiredCap) revert ExceedsVaultSize();

        return super.deposit(_amountToDeposit, _receiverShares);
    }

    function withdraw(uint256 _amountToWithdraw, address _receiver, address _holderShares) public override returns (uint256) {
        uint256 currentTime = block.timestamp;
        bool isNotRaisedDesiredCap = currentTime > fundingEndTime && totalAssets() < desiredCap;
        bool isVaultFailed = currentTime > unlockEndTime && totalAssets() < promisedCap;

        if (_amountToWithdraw == 0) revert AmountToWithdrawCannotBeZero();
        if (isNotRaisedDesiredCap) return super.withdraw(_amountToWithdraw, _receiver, _holderShares);
        if (currentTime <= unlockEndTime) revert VaultIsNotUnlocked();
        // if (isVaultFailed) return super.withdraw(_amountToWithdraw, _receiver, _holderShares);

        return super.withdraw(_amountToWithdraw, _receiver, _holderShares);
    }

    // function refund() external {
    //     uint256 currentTime = block.timestamp;
    //     bool isVaultFailed = currentTime > unlockEndTime && totalAssets() < desiredCap;

    //     if (!isVaultFailed) revert VaultIsNotFailed();

    //     uint256 insufficientTokensAmount = totalAssets() - desiredCap;
    //     TREASURY_CONTRACT.fundVault(owner(), insufficientTokensAmount, true);
    // }

    function depositFromEntity(uint256 _amountToFund) external onlyOwner {
        uint256 currentTime = block.timestamp;

        if (currentTime <= fundingEndTime) revert FundingEndTimeIsNotReached();
        if (_amountToFund == 0) revert AmountToFundCannotBeZero();
        if (totalAssets() + _amountToFund > desiredCap) revert ExceedsVaultSize();

        IERC20(asset()).transferFrom(msg.sender, address(this), _amountToFund);

        if (totalAssets() + _amountToFund == desiredCap) {
            SCORING_CONTRACT.updateEntityScore(owner(), desiredCap, false);
            unlockEndTime = currentTime;

            emit FullyDepositedFromEntity();
        } else {
            emit PartiallyDepositedFromEntity(_amountToFund);
        }
    }

    function withdrawToEntity() external onlyOwner {
        uint256 currentTime = block.timestamp;

        if (currentTime <= fundingEndTime) revert FundingEndTimeIsNotReached();
        if (totalAssets() < desiredCap) revert InsufficientBalance();

        IERC20(asset()).transfer(msg.sender, totalAssets());
        emit WithdrawToEntity(totalAssets());
    }

    function getInsufficientTokensAmount() public view returns (uint256) {
        if (block.timestamp < unlockEndTime) return 0;
        return promisedCap - totalAssets();
    }

    function _isContract(address _address) private view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_address)
        }
        return (size > 0);
    }
}