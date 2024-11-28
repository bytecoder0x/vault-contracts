// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ILicense {
    enum LicenseState {
        UNINITIALIZED,
        PENDING,
        REJECTED,
        ACTIVE,
        EXPIRED
    }

    struct LicenseInfo {
        uint256 totalVotes;
        uint256 startTime;
        uint256 endTime;
        bool approved;
        mapping(address => uint256) voters;
    }

    event Voted(address indexed entity, address indexed voter, uint256 indexed licenseId, uint256 votes);
    event AppliedForLicense(address indexed entity, uint256 indexed licenseId, uint256 startTime, uint256 endTime);
    event RefundedLicenseFee(address indexed entity, uint256 amount);
    event ApplicationFeeUpdated(uint256 amount);
    event LicenseMonthlyFeeUpdated(uint256 amount);
    event RequiredVotesPercentageUpdated(uint256 percentage);
    event VotingPeriodUpdated(uint256 period);
    event LicenseExpirationLimitUpdated(uint256 limit);

    error FeesCannotBeZero();
    error AdminAddressCannotBeZero();
    error QadrataAddressMustBeContract();
    error GOILTokenAddressMustBeContract();
    error TreasuryAddressMustBeContract();
    error LicensePeriodTooShort();
    error LicensePeriodTooLong();
    error ApplicantMustHaveQadrataKYB();
    error LicenseAlreadySubmitted();
    error NoLicenseFeeToRefund();
    error CannotRefundActiveOrPendingLicense();
    error NoGOILTokensToVote();
    error LicenseIsNotPending();
    error AlreadyVoted();
    error LicenseIsNotRejected();
    error FeeCannotBeTheSame();
    error PercentageCannotBeTheSame();
    error InvalidPercentage();
    error VotingPeriodCannotBeTheSame();
    error VotingPeriodCannotBeZero();
    error LicenseExpirationLimitCannotBeTheSame();
    error LicenseExpirationLimitCannotBeZero();

    function submitLicense(uint256 _licenseEndTime) external;
    function vote(address _applicant) external;
    function refundLicenseFee() external;
    function setApplicationFee(uint256 _applicationFee) external;
    function setLicenseMonthlyFee(uint256 _licenseMonthlyFee) external;
    function setRequiredVotesPercentage(uint256 _requiredVotesPercentage) external;
    function setVotingPeriod(uint256 _votingPeriod) external;
    function setLicenseExpirationLimit(uint256 _licenseExpirationLimit) external;
    function getLicenseStatus(address _entity) external view returns (LicenseState);
    function getLicenseIsActive(address _entity) external view returns (bool);
    function getLicenseVotingPercentage(address _entity) external view returns (uint256);
    function getLicenseByEntity(address _entity) external view returns (uint256, uint256, bool);
    function getLicenseVotesByUser(address _entity, uint256 _licenseId, address _voter) external view returns (uint256);
}