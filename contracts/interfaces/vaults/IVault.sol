// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {IERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC4626Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IScoring} from "./IScoring.sol";

interface IVault is IERC4626Upgradeable {
    enum Swap {
        V2,
        V3_500,
        V3_3000,
        V3_10000
    }

    error WithdrawMoreThanMax();
    error VaultNotStarted();
    error VaultFundingTimeIsEnded();
    error VaultNotExpired();
    error ExceedsVaultSize();
    error InsufficientBalance();
    error FundingEndTimeIsNotReached();
    error VaultIsNotUnlocked();
    error VaultIsNotFailed();

    event DepositFromEntity(uint256 amount);
    event WithdrawToEntity(uint256 amount);

    function SCORING() external view returns (IScoring);
    function GOIL_TOKEN() external view returns (IERC20Upgradeable);
    function isVaultFailed() external view returns (bool);
    function goilRate() external view returns (uint256);
    function desiredCap() external view returns (uint256);
    function promisedCap() external view returns (uint256);
    function startTime() external view returns (uint256);
    function fundingEndTime() external view returns (uint256);
    function unlockEndTime() external view returns (uint256);
    function owner() external view returns (address);

    function initialize(
        address _entity,
        address _scoring,
        address _treasury,
        address _goilToken,
        address _depositToken, 
        address _routerV2,
        address _routerV3,
        address _quoter,
        uint256 _desiredCap,
        uint256 _promisedCap,
        uint256 _startTime,
        uint256 _fundingEndTime,
        uint256 _unlockEndTime
    ) external;
    function depositToVault(uint256 _amountToDeposit) external;
    function withdrawFromVault(uint256 _amountToWithdraw) external;
    function depositToVault(uint256 _amountToDeposit, address _receiverShares) external;
    function withdrawFromVault(uint256 _amountToWithdraw, address _receiver, address _holderShares) external;
    function depositFromEntity() external;
    function withdrawToEntity() external;
}