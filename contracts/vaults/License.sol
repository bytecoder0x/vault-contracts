// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {QuadReaderUtils} from "@quadrata/contracts/utility/QuadReaderUtils.sol";
import {IQuadPassportStore} from "@quadrata/contracts/interfaces/IQuadPassportStore.sol";
import {IQuadReader} from "@quadrata/contracts/interfaces/IQuadReader.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILicense} from "../interfaces/vaults/ILicense.sol";
import "hardhat/console.sol";
contract License is AccessControl, ILicense {
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant REQUIRED_KYB = keccak256("IS_BUSINESS");

    uint256 public constant PERCENTAGE_DENOMINATOR = 100_00;

    IQuadReader public immutable QADRATA_READER;
    IERC20 public immutable GOIL_TOKEN;
    address public immutable TREASURY;

    uint256 public requiredVotesPercentage = 66_00;
    uint256 public votingPeriod = 7 days;
    uint256 public licenseExpirationLimit = 365 days; // 12 months

    uint256 public requiredVotesThreshold;
    uint256 public applicationFee;
    uint256 public licenseMonthlyFee;

    mapping(address => mapping(uint256 => LicenseInfo)) public licenses;
    mapping(address => uint256) public licenseCount;
    mapping(address => uint256) public licenseFeePaid;

    constructor(
        address _admin,
        address _qadrataReader,
        address _goilToken,
        address _treasury,
        uint256 _applicationFee,
        uint256 _licenseMonthlyFee
    ) {
        if (_applicationFee == 0 || _licenseMonthlyFee == 0) revert FeesCannotBeZero();
        if (_admin == address(0)) revert AdminAddressCannotBeZero();
        if (!_isContract(_qadrataReader)) revert QadrataAddressMustBeContract();
        if (!_isContract(_goilToken)) revert GOILTokenAddressMustBeContract();
        if (!_isContract(_treasury)) revert TreasuryAddressMustBeContract();

        QADRATA_READER = IQuadReader(_qadrataReader);
        GOIL_TOKEN = IERC20(_goilToken);
        TREASURY = _treasury;
        applicationFee = _applicationFee;
        licenseMonthlyFee = _licenseMonthlyFee;
        requiredVotesThreshold = (GOIL_TOKEN.totalSupply() * requiredVotesPercentage) / PERCENTAGE_DENOMINATOR;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(MANAGER_ROLE, _admin);
    }

    function submitLicense(uint256 _licenseEndTime) external {
        LicenseState state = getLicenseStatus(msg.sender);
        uint256 licenseStartTime = block.timestamp + votingPeriod;
        uint256 licensePeriod = _licenseEndTime - licenseStartTime;

        if (QADRATA_READER.balanceOf(msg.sender, REQUIRED_KYB) == 0) revert ApplicantMustHaveQadrataKYB();
        if (licensePeriod < 30 days) revert LicensePeriodTooShort();
        if (licenseExpirationLimit < licensePeriod) revert LicensePeriodTooLong();
        if (state == LicenseState.ACTIVE || state == LicenseState.PENDING) revert LicenseAlreadySubmitted();
        
        licenseCount[msg.sender] += 1;
        uint256 licenseId = licenseCount[msg.sender];
        LicenseInfo storage license = licenses[msg.sender][licenseId];

        uint256 licenseFee = (licensePeriod / 30 days) * licenseMonthlyFee;

        GOIL_TOKEN.transferFrom(msg.sender, TREASURY, applicationFee);
        GOIL_TOKEN.transferFrom(msg.sender, address(this), licenseFee);

        licenseFeePaid[msg.sender] += licenseFee;
        license.startTime = licenseStartTime;
        license.endTime = _licenseEndTime;

        emit AppliedForLicense(msg.sender, licenseId, licenseStartTime, _licenseEndTime);
    }

    function vote(address _applicant) external {
        uint256 votes = GOIL_TOKEN.balanceOf(msg.sender);
        uint256 licenseId = licenseCount[_applicant];

        LicenseInfo storage license = licenses[_applicant][licenseId];
        LicenseState state = getLicenseStatus(_applicant);

        if (votes == 0) revert NoGOILTokensToVote();
        if (state != LicenseState.PENDING) revert LicenseIsNotPending();
        if (license.voters[msg.sender] > 0) revert AlreadyVoted();

        license.voters[msg.sender] = votes;
        license.totalVotes += votes;

        if (license.totalVotes >= requiredVotesThreshold) {
            uint256 licenseFee = (license.endTime - license.startTime) / 30 days * licenseMonthlyFee;
            GOIL_TOKEN.transfer(TREASURY, licenseFee);

            licenseFeePaid[_applicant] -= licenseFee;
            license.approved = true;
        }

        emit Voted(_applicant, msg.sender, licenseId, votes);
    }

    function refundLicenseFee() external {
        uint256 licenseFee = getRefundableLicenseFee(msg.sender);
        if (licenseFee == 0) revert NoLicenseFeeToRefund();

        licenseFeePaid[msg.sender] -= licenseFee;
        GOIL_TOKEN.transfer(msg.sender, licenseFee);
        emit RefundedLicenseFee(msg.sender, licenseFee);
    }

    function setApplicationFee(uint256 _applicationFee) external onlyRole(MANAGER_ROLE) {
        if (applicationFee == _applicationFee) revert FeeCannotBeTheSame();

        applicationFee = _applicationFee;
        emit ApplicationFeeUpdated(_applicationFee);
    }

    function setLicenseMonthlyFee(uint256 _licenseMonthlyFee) external onlyRole(MANAGER_ROLE) {
        if (licenseMonthlyFee == _licenseMonthlyFee) revert FeeCannotBeTheSame();

        licenseMonthlyFee = _licenseMonthlyFee;
        emit LicenseMonthlyFeeUpdated(_licenseMonthlyFee);
    }

    function setRequiredVotesPercentage(uint256 _requiredVotesPercentage) external onlyRole(MANAGER_ROLE) {
        if (requiredVotesPercentage == _requiredVotesPercentage) revert PercentageCannotBeTheSame();
        if (_requiredVotesPercentage == 0 || _requiredVotesPercentage > PERCENTAGE_DENOMINATOR) revert InvalidPercentage();

        requiredVotesPercentage = _requiredVotesPercentage;
        requiredVotesThreshold = (GOIL_TOKEN.totalSupply() * requiredVotesPercentage) / PERCENTAGE_DENOMINATOR;
        emit RequiredVotesPercentageUpdated(_requiredVotesPercentage);
    }

    function setVotingPeriod(uint256 _votingPeriod) external onlyRole(MANAGER_ROLE) {
        if (votingPeriod == _votingPeriod) revert VotingPeriodCannotBeTheSame();
        if (_votingPeriod == 0) revert VotingPeriodCannotBeZero();

        votingPeriod = _votingPeriod;
        emit VotingPeriodUpdated(_votingPeriod);
    }

    function setLicenseExpirationLimit(uint256 _licenseExpirationLimit) external onlyRole(MANAGER_ROLE) {
        if (licenseExpirationLimit == _licenseExpirationLimit) revert LicenseExpirationLimitCannotBeTheSame();
        if (_licenseExpirationLimit == 0) revert LicenseExpirationLimitCannotBeZero();

        licenseExpirationLimit = _licenseExpirationLimit;
        emit LicenseExpirationLimitUpdated(_licenseExpirationLimit);
    }

    function getLicenseStatus(address _entity) public view returns (LicenseState) {
        uint256 licenseId = licenseCount[_entity];
        if (licenseId == 0) return LicenseState.UNINITIALIZED;

        LicenseInfo storage license = licenses[_entity][licenseId];
        uint256 currentTime = block.timestamp;

        if (license.startTime > currentTime && !license.approved) return LicenseState.PENDING;
        if (license.endTime < currentTime) return LicenseState.EXPIRED;
        if (!license.approved) return LicenseState.REJECTED;

        return LicenseState.ACTIVE;
    }

    function getLicenseIsActive(address _entity) public view returns (bool) {
        return getLicenseStatus(_entity) == LicenseState.ACTIVE;
    }

    function getLicenseByEntity(address _entity) public view returns (uint256, uint256, bool) {
        uint256 licenseId = licenseCount[_entity];
        LicenseInfo storage license = licenses[_entity][licenseId];

        return (license.startTime, license.endTime, license.approved);
    }

    function getLicenseVotesByUser(address _entity, uint256 _licenseId, address _voter) public view returns (uint256) {
        LicenseInfo storage license = licenses[_entity][_licenseId];
        return license.voters[_voter];
    }

    function getLicenseVotingPercentage(address _entity) public view returns (uint256) {
        uint256 licenseId = licenseCount[_entity];
        LicenseInfo storage license = licenses[_entity][licenseId];

        return (license.totalVotes * PERCENTAGE_DENOMINATOR) / GOIL_TOKEN.totalSupply();
    }

    function getRefundableLicenseFee(address _entity) public view returns (uint256) {
        LicenseState state = getLicenseStatus(_entity);
        uint256 licenseFee = licenseFeePaid[_entity];

        if (state == LicenseState.PENDING) {
            (uint256 startTime, uint256 endTime, ) = getLicenseByEntity(_entity);
            uint256 licensePeriod = endTime - startTime;
            uint256 currentLicenseFee = (licensePeriod / 30 days) * licenseMonthlyFee;
            licenseFee -= currentLicenseFee;
        }

        return licenseFee;
    }

    function _isContract(address _address) private view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_address)
        }
        return (size > 0);
    }
}