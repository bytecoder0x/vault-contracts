// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IStaking {
    struct UserStake {
        uint256 stakedAmount;
        uint256 rewardDebt;
    }

    error StakingTokenMustBeContract();
    error RewardTokenMustBeContract();
    error TreasuryMustBeContract();
    error StakeAmountCannotBeZero();
    error NoStakedTokens();
    error NoRewardToClaim();
    error InsufficientRewardPool();
    error EndStakingBlockMustBeInTheFuture();

    event Staked(address indexed staker, uint256 amount);
    event Unstaked(address indexed staker, uint256 amount);
    event ClaimReward(address indexed staker, uint256 amount);
    event RewardDeposited(address indexed depositor, uint256 amount);

    
    function stakeTokens(uint256 _amount) external;
    function unstakeTokens() external;
    function claimReward() external;
    function unstakeTokens(address _to) external;
    function claimReward(address _to) external;
    function depositReward(uint256 _amount) external;
    function getCurrentAPY() external view returns (uint256);
    function getRewardPerBlock() external view returns (uint256);
    function getStakedAmount(address _user) external view returns (uint256);
    function getPendingRewardByUser(address _user) external view returns (uint256);
    function getPendingRewardByUsers(address[] memory _users) external view returns (uint256[] memory);
}