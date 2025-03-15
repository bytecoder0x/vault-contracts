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
        address entity;
        uint256 startTime;
        uint256 endTime;
        bool approved;
        bool confirmedByAdmin;
    }

    struct LicenseFeeAndCollateral {
        uint256 licenseFee;
        uint256 collateral;
    }

    event SubmittedLicense(address indexed entity, uint256 startTime, uint256 endTime, uint256 licenseFee, uint256 collateral);
    event LicenseApproved(address indexed entity, bool approved);
    event ApplicationFeeUpdated(uint256 amount);
    event LicenseMonthlyFeeUpdated(uint256 amount);
    event VotingPeriodUpdated(uint256 period);
    event LicenseExpirationLimitUpdated(uint256 limit);
    event ScoringContractUpdated(address indexed scoringContract);

    error ScoringContractNotSet();
    error ScoringContractAlreadySet();
    error ScoringContractMustBeContract();
    error LicenseIsNotPending();
    error FeesCannotBeZero();
    error AdminAddressCannotBeZero();
    error QadrataAddressMustBeContract();
    error GOILTokenAddressMustBeContract();
    error TreasuryAddressMustBeContract();
    error LicensePeriodTooShort();
    error LicensePeriodTooLong();
    error ApplicantMustHaveQadrataKYB();
    error LicenseAlreadySubmitted();
    error EntitiesAndApprovedLengthsMustBeTheSame();
    error FeeCannotBeTheSame();
    error VotingPeriodCannotBeTheSame();
    error VotingPeriodCannotBeZero();
    error LicenseExpirationLimitCannotBeTheSame();
    error LicenseExpirationLimitCannotBeZero();

    function submitLicense(uint256 _licenseEndTime, uint256 _collateralAmount) external;
    function approveLicense(address _entity, bool _approved) external;
    function approveLicenseBatch(address[] calldata _entities, bool[] calldata _approved) external;
    function setApplicationFee(uint256 _applicationFee) external;
    function setLicenseMonthlyFee(uint256 _licenseMonthlyFee) external;
    function setVotingPeriod(uint256 _votingPeriod) external;
    function setLicenseExpirationLimit(uint256 _licenseExpirationLimit) external;
    function getLicenseStatus(address _entity) external view returns (LicenseState);
    function getLicenseIsActive(address _entity) external view returns (bool);
    function getLicenseIsPending(address _entity) external view returns (bool);
    function getLicenseExpirationTime(address _entity) external view returns (uint256);
    function getLicenseByEntity(address _entity) external view returns (uint8, uint256, uint256, bool, bool);
}