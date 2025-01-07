// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVaultFactory} from "../interfaces/vaults/IVaultFactory.sol";
import {ITreasury} from "../interfaces/vaults/ITreasury.sol";
import {IStaking} from "../interfaces/vaults/IStaking.sol";

contract Staking is IStaking {
    IERC20 public immutable STAKING_TOKEN;
    IERC20 public immutable REWARD_TOKEN;

    IVaultFactory public immutable VAULT_FACTORY;
    ITreasury public immutable TREASURY;

    uint256 public immutable STAKING_TOKEN_PRECISION;

    uint256 public rewardPerBlock;
    uint256 public totalStaked; 
    uint256 public accRewardPerShare;

    uint256 public lastRewardBlock;
    uint256 public endStakingBlock;

    uint256 public totalReward;

    mapping(address => UserStake) public userStakes;

    modifier onlyVault() {
        if (!VAULT_FACTORY.getIsValidVault(msg.sender)) revert OnlyVault();
        _;
    }

    constructor(
        address _vaultFactory,
        address _treasury,
        address _stakingToken,
        address _rewardToken,
        uint256 _endStakingBlock
    ) {
        if (!_isContract(_vaultFactory)) revert VaultFactoryMustBeContract();
        if (!_isContract(_treasury)) revert TreasuryMustBeContract();
        if (!_isContract(_stakingToken)) revert StakingTokenMustBeContract();
        if (!_isContract(_rewardToken)) revert RewardTokenMustBeContract();
        if (block.number >= _endStakingBlock) revert EndStakingBlockMustBeInTheFuture();

        VAULT_FACTORY = IVaultFactory(_vaultFactory);
        TREASURY = ITreasury(_treasury);
        STAKING_TOKEN_PRECISION = 10 ** IERC20Metadata(_stakingToken).decimals();
        STAKING_TOKEN = IERC20(_stakingToken);
        REWARD_TOKEN = IERC20(_rewardToken);
        endStakingBlock = _endStakingBlock;
    }

    function stakeTokens(uint256 _amount) external {
        if (_amount == 0) revert StakeAmountCannotBeZero();

        _updateRewards();
        UserStake storage user = userStakes[msg.sender];
        
        if (user.stakedAmount > 0) {
            uint256 reward = (user.stakedAmount * accRewardPerShare / STAKING_TOKEN_PRECISION) - user.rewardDebt;
            if (reward > 0) {
                REWARD_TOKEN.transfer(msg.sender, reward);
            }
        }

        totalStaked += _amount;
        user.stakedAmount += _amount;
        user.rewardDebt = user.stakedAmount * accRewardPerShare / STAKING_TOKEN_PRECISION;
        STAKING_TOKEN.transferFrom(msg.sender, address(TREASURY), _amount);

        emit Staked(msg.sender, _amount);
    }

    function unstakeTokens(address _to) external {
        UserStake storage user = userStakes[msg.sender];

        uint256 stakedAmount = user.stakedAmount;
        if (stakedAmount == 0) revert NoStakedTokens();

        _updateRewards();
        if (stakedAmount > 0) {
            uint256 reward = stakedAmount * accRewardPerShare / STAKING_TOKEN_PRECISION - user.rewardDebt;
            if (reward > 0) {
                REWARD_TOKEN.transfer(msg.sender, reward);
            }
        }

        totalStaked -= stakedAmount;
        user.stakedAmount = 0;
        user.rewardDebt = 0;
        TREASURY.unstakeTokens(_to, stakedAmount);

        emit Unstaked(msg.sender, stakedAmount);
    }

    function claimReward(address _to) external {
        UserStake storage user = userStakes[msg.sender];

        _updateRewards();
        uint256 reward = (user.stakedAmount * accRewardPerShare / STAKING_TOKEN_PRECISION) - user.rewardDebt;

        if (reward == 0) {
            user.rewardDebt = user.stakedAmount * accRewardPerShare / STAKING_TOKEN_PRECISION;
            return;
        }

        user.rewardDebt = user.stakedAmount * accRewardPerShare / STAKING_TOKEN_PRECISION;
        REWARD_TOKEN.transfer(_to, reward);

        emit ClaimReward(msg.sender, reward);
    }

    function transferReward(uint256 _amount) external onlyVault {
        _updateRewards();
        REWARD_TOKEN.transferFrom(msg.sender, address(this), _amount);
        // TODO: update rewardPerBlock or implement other feature

        emit RewardTransferred(msg.sender, _amount);
    }

    function getPendingRewardByUser(address _user) public view returns (uint256) {
        UserStake memory user = userStakes[_user];

        uint256 currentAccRewardPerShare = accRewardPerShare;
        uint256 currentBlock = block.number;

        if (currentBlock > lastRewardBlock && totalStaked != 0) {
            uint256 elapsedBlocks = currentBlock - lastRewardBlock;
            uint256 rewards = elapsedBlocks * rewardPerBlock;
            currentAccRewardPerShare += (rewards * STAKING_TOKEN_PRECISION) / totalStaked;
        }

        return (user.stakedAmount * currentAccRewardPerShare / STAKING_TOKEN_PRECISION) - user.rewardDebt;
    }

    function getPendingRewardByUsers(address[] memory _users) public view returns (uint256[] memory rewards) {
        rewards = new uint256[](_users.length);

        for (uint256 i = 0; i < _users.length; i++) {
            rewards[i] = getPendingRewardByUser(_users[i]);
        }
    }

    function _updateRewards() private {
        uint256 currentBlock = block.number;

        if (currentBlock <= lastRewardBlock) {
            return;
        }

        if (totalStaked == 0) {
            lastRewardBlock = block.number;
            return;
        }

        uint256 elapsedBlocks = currentBlock - lastRewardBlock;
        uint256 rewards = elapsedBlocks * rewardPerBlock;

        accRewardPerShare += (rewards * STAKING_TOKEN_PRECISION) / totalStaked;
        lastRewardBlock = currentBlock;
    }

    function _isContract(address _address) private view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_address)
        }
        return (size > 0);
    }
}