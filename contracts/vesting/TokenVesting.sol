// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ITokenVesting} from "../interfaces/vesting/ITokenVesting.sol";

contract TokenVesting is ITokenVesting, Ownable {
    IERC20 public immutable TOKEN;

    address public presaleContract;
    uint256 public vestingTotalAmount;

    mapping(address => VestingSchedule[]) public vestings;

    constructor(address _owner, address _token) Ownable(_owner) {
        if (!_isContract(_token)) revert TokenIsNotContract();

        TOKEN = IERC20(_token);
    }

    modifier onlyOwnerOrPresale() {
        if (msg.sender != owner() && msg.sender != presaleContract) {
            revert OnlyOwnerOrPresaleAllowed();
        }
        _;
    }

    function createVesting(
        address recipient,
        uint256 startTime,
        uint256 endTime,
        uint256 cliffPeriod,
        uint256 slicePeriod,
        uint256 amount,
        VestingType vestingType
    ) external onlyOwnerOrPresale {
        if (recipient == address(0)) revert RecipientIsZeroAddress();
        if (slicePeriod == 0) revert SlicePeriodIsZero();
        if (startTime == 0) revert StartTimeIsZero();
        if (amount == 0) revert NoTokensToVesting();
        if (endTime < block.timestamp) revert EndTimeInPast();
        if (endTime <= startTime) revert EndTimeBeforeStartTime();
        if (cliffPeriod + slicePeriod > endTime - startTime) revert CliffAndSlicePeriodTooLong();

        VestingSchedule memory vesting = VestingSchedule({
            recipient: recipient,
            startTime: startTime,
            cliffTime: startTime + cliffPeriod,
            endTime: endTime,
            slicePeriod: slicePeriod,
            amount: amount,
            claimed: 0,
            vestingType: vestingType
        });

        vestings[recipient].push(vesting);
        vestingTotalAmount += amount;
        TOKEN.transferFrom(msg.sender, address(this), amount);

        emit VestingScheduleCreated(
            msg.sender,
            recipient,
            startTime,
            startTime + cliffPeriod,
            endTime,
            slicePeriod,
            amount,
            vestingType
        );
    }

    function claimTokens() external {
        VestingSchedule[] storage recipientVestings = vestings[msg.sender];

        uint256 totalClaimableAmount;
        for (uint256 i = 0; i < recipientVestings.length; i++) {
            VestingSchedule storage vesting = recipientVestings[i];

            uint256 claimableAmount = _calculateClaimableAmount(vesting);
            if (claimableAmount > 0) {
                vesting.claimed += claimableAmount;
                totalClaimableAmount += claimableAmount;
            }
        }

        if (totalClaimableAmount == 0) revert NoTokensToClaim();

        vestingTotalAmount -= totalClaimableAmount;
        TOKEN.transfer(msg.sender, totalClaimableAmount);

        emit TokensClaimed(msg.sender, totalClaimableAmount);
    }

    function setPresaleContract(address _presaleContract) external onlyOwner {
        if (presaleContract != address(0)) revert PresaleAlreadySet();
        if (!_isContract(_presaleContract)) revert PresaleIsNotContract();

        presaleContract = _presaleContract;
        emit PresaleContractSet(_presaleContract);
    }


    function getClaimableAmount(address _recipient) external view returns (uint256) {
        VestingSchedule[] storage recipientVestings = vestings[_recipient];

        uint256 totalClaimable = 0;
        for (uint256 i = 0; i < recipientVestings.length; i++) {
            VestingSchedule storage vesting = recipientVestings[i];
            totalClaimable += _calculateClaimableAmount(vesting);
        }

        return totalClaimable;
    }

    function getVestings(address _recipient) external view returns (VestingSchedule[] memory) {
        return vestings[_recipient];
    }

    function getVestingsCount(address _recipient) external view returns (uint256) {
        return vestings[_recipient].length;
    }

    /// C = (At * Sc / St) - Ca
    ///
    /// Where
    /// C — Claimable Amount: the amount of tokens that can be claimed at the current time.
    /// At — Tokens Total: the total amount of tokens for vesting (amount).
    /// Sc — Slices Completed: the number of completed slices at the current time. (Current Time - Cliff Time) / Slice Period
    /// St — Slices Total: the total number of slices over the entire vesting period. (End Time - Cliff Time) / Slice Period
    /// Ca — Claimed Already Tokens: the amount of tokens that have already been released (claimed).
    /// *Cliff Time = (Start Time + Cliff Period)
    function _calculateClaimableAmount(VestingSchedule memory _vesting) private view returns (uint256) {
        uint256 currentTime = block.timestamp;

        if (currentTime < _vesting.cliffTime) {
            return 0;
        }

        if (currentTime >= _vesting.endTime) {
            return _vesting.amount - _vesting.claimed;
        }

        uint256 timeAfterCliff = currentTime - _vesting.cliffTime;

        uint256 completedSlices = timeAfterCliff / _vesting.slicePeriod;
        uint256 totalSlices = (_vesting.endTime - _vesting.cliffTime) / _vesting.slicePeriod;

        uint256 claimableAmount = (_vesting.amount * completedSlices) / totalSlices;

        return claimableAmount - _vesting.claimed;
    }

    function _isContract(address _address) private view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_address)
        }
        return (size > 0);
    }
}