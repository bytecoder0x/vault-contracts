// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {IERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC4626Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IVaultFactory} from "./IVaultFactory.sol";
import {IScoring} from "./IScoring.sol";

interface IVault {
    enum VaultState {
        NOT_STARTED,
        FUNDING,
        NOT_RAISED,
        LOCKED,
        SUCCESS,
        LIQUIDATED
    }

    struct DexParams {
        address routerV2;
        address routerV3;
        address quoter;
    }

    struct VaultParams {
        address entity;
        address scoring;
        address treasury;
        address staking;
        address goilToken;
        address depositToken;
        uint256 desiredCap;
        uint256 promisedCap;
        uint256 startTime;
        uint256 fundingEndTime;
        uint256 unlockEndTime;
        uint256 amountForStaking;
        uint256 refundableAmount;
    }

    error EntityCannotBeZeroAddress();
    error StartTimeCannotBeInThePast();
    error FundingEndTimeCannotBeBeforeStartTime();
    error UnlockEndTimeCannotBeBeforeFundingEndTime();
    error WithdrawMoreThanMax();
    error VaultNotStarted();
    error VaultFundingTimeIsEnded();
    error VaultNotExpired();
    error ExceedsVaultSize();
    error InsufficientBalance();
    error FundingEndTimeIsNotReached();
    error VaultIsNotUnlocked();
    error VaultIsUnlocked();
    error VaultIsNotFailed();
    error VaultIsNotLiquidatable();
    error OnlyEntityCanCall();

    event DepositFromEntity(uint256 amount);
    event WithdrawToEntity(uint256 amount);

    function SCORING() external view returns (IScoring);
    function GOIL_TOKEN() external view returns (IERC20Upgradeable);
    function ENTITY() external view returns (address);

    function isVaultSuccess() external view returns (bool);

    function desiredCap() external view returns (uint256);
    function promisedCap() external view returns (uint256);
    function startTime() external view returns (uint256);
    function fundingEndTime() external view returns (uint256);
    function unlockEndTime() external view returns (uint256);
    function amountForStaking() external view returns (uint256);

    function totalDepositsFromUsers() external view returns (uint256);
    function totalDepositsFromEntity() external view returns (uint256);

    function initialize(VaultParams memory _vaultParams, DexParams memory _dexParams) external;

    function deposit(uint256 _amountToDeposit) external returns (uint256);
    function withdraw(uint256 _amountToWithdraw) external returns (uint256);
    function depositFromEntity(uint256 _amountToDeposit) external;
    function withdrawToEntity() external;
    
    function getVaultState() external view returns (VaultState);
    function getCurrentRefundableAmount() external view returns (uint256);
    function getPromisedAndUnpaidAmount() external view returns (uint256 promisedAmount, uint256 unpaidAmount);
    function isLiquidatable() external view returns (bool);
    function isNotRaisedDesiredCap() external view returns (bool);
}