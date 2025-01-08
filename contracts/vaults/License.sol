// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IQuadReader} from "@quadrata/contracts/interfaces/IQuadReader.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IScoring} from "../interfaces/vaults/IScoring.sol";
import {ILicense} from "../interfaces/vaults/ILicense.sol";
import {ITreasury} from "../interfaces/vaults/ITreasury.sol";

contract License is AccessControl, ILicense {
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant REQUIRED_KYB = keccak256("IS_BUSINESS");

    uint256 public constant PERCENTAGE_DENOMINATOR = 100_00;

    IQuadReader public immutable QADRATA_READER;
    IERC20 public immutable GOIL_TOKEN;
    ITreasury public immutable TREASURY;
    IScoring public SCORING;

    uint256 public immutable GOIL_SUPPLY;

    uint256 public requiredVotesPercentage = 66_00;
    uint256 public votingPeriod = 7 days;
    uint256 public licenseExpirationLimit = 365 days; // 12 months

    uint256 public requiredVotesThreshold;
    uint256 public applicationFee;
    uint256 public licenseMonthlyFee;

    mapping(address => LicenseFeeAndCollateral) public licenseFeeAndCollateralPaid;
    mapping(address => mapping(uint256 => LicenseInfo)) public licenses;
    mapping(address => uint256) public licenseCount;

    modifier withSetupScoringContract() {
        if (address(SCORING) == address(0)) revert ScoringContractNotSet();
        _;
    }

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
        TREASURY = ITreasury(_treasury);
        applicationFee = _applicationFee;
        licenseMonthlyFee = _licenseMonthlyFee;
        GOIL_SUPPLY = GOIL_TOKEN.totalSupply();
        requiredVotesThreshold = (GOIL_SUPPLY * requiredVotesPercentage) / PERCENTAGE_DENOMINATOR;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(MANAGER_ROLE, _admin);
    }

    function submitLicense(uint256 _licenseEndTime, uint256 _collateralAmount) external withSetupScoringContract {
        LicenseState state = getLicenseStatus(msg.sender);
        uint256 licenseStartTime = block.timestamp + votingPeriod;
        uint256 licensePeriod = _licenseEndTime - licenseStartTime;

        if (QADRATA_READER.balanceOf(msg.sender, REQUIRED_KYB) == 0) revert ApplicantMustHaveQadrataKYB();
        if (licensePeriod < 30 days) revert LicensePeriodTooShort();
        if (licenseExpirationLimit < licensePeriod) revert LicensePeriodTooLong();
        if (state == LicenseState.ACTIVE || state == LicenseState.PENDING) revert LicenseAlreadySubmitted();
        
        LicenseFeeAndCollateral memory licenseFeeAndCollateral = licenseFeeAndCollateralPaid[msg.sender];

        uint256 licenseFeePaid = licenseFeeAndCollateral.licenseFee;
        uint256 licenseFee = (licensePeriod / 30 days) * licenseMonthlyFee;

        licenseFee > licenseFeePaid ? licenseFee -= licenseFeePaid : licenseFee = 0;

        GOIL_TOKEN.transferFrom(msg.sender, address(TREASURY), applicationFee);
        if (licenseFee + _collateralAmount > 0) GOIL_TOKEN.transferFrom(msg.sender, address(this), licenseFee + _collateralAmount);

        licenseFeeAndCollateralPaid[msg.sender].licenseFee += licenseFee;
        licenseFeeAndCollateralPaid[msg.sender].collateral += _collateralAmount;

        licenseCount[msg.sender] += 1;
        uint256 licenseId = licenseCount[msg.sender];
        LicenseInfo storage license = licenses[msg.sender][licenseId];

        license.startTime = licenseStartTime;
        license.endTime = _licenseEndTime;

        emit AppliedForLicense(msg.sender, licenseId, licenseStartTime, _licenseEndTime, licenseFee, _collateralAmount);
    }

    function vote(address _applicant) external withSetupScoringContract {
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
            uint256 collateralAmount = licenseFeeAndCollateralPaid[_applicant].collateral;

            GOIL_TOKEN.transfer(address(TREASURY), licenseFee);
            GOIL_TOKEN.approve(address(TREASURY), collateralAmount);
            TREASURY.depositCollateral(_applicant, collateralAmount);

            licenseFeeAndCollateralPaid[_applicant].licenseFee -= licenseFee;
            licenseFeeAndCollateralPaid[_applicant].collateral = 0;
            license.approved = true;

            if (!SCORING.getIsInitialScoreSet(_applicant)) SCORING.setInitialScore(_applicant);
            emit LicenseApproved(_applicant, licenseId);
        }

        emit Voted(_applicant, msg.sender, licenseId, votes);
    }

    function refundLicenseFeeAndCollateral() external {
        uint256 refundableAmount = getRefundableAmount(msg.sender);
        if (refundableAmount == 0) revert NoTokensToRefund();

        licenseFeeAndCollateralPaid[msg.sender].licenseFee = 0;
        licenseFeeAndCollateralPaid[msg.sender].collateral = 0;

        GOIL_TOKEN.transfer(msg.sender, refundableAmount);
        emit RefundedLicenseFeeAndCollateral(msg.sender, refundableAmount);
    }

    function setScoringContract(address _scoringContract) external onlyRole(MANAGER_ROLE) {
        if (!_isContract(_scoringContract)) revert ScoringContractMustBeContract();
        if (address(SCORING) != address(0)) revert ScoringContractAlreadySet();

        SCORING = IScoring(_scoringContract);
        emit ScoringContractUpdated(_scoringContract);
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

    function getLicenseIsPending(address _entity) public view returns (bool) {
        return getLicenseStatus(_entity) == LicenseState.PENDING;
    }

    function getLicenseExpirationTime(address _entity) public view returns (uint256) {
        uint256 licenseId = licenseCount[_entity];
        LicenseInfo storage license = licenses[_entity][licenseId];
        return license.endTime;
    }

    function getLicenseByEntity(address _entity) public view returns (uint8, uint256, uint256, uint256, uint256, uint256) {
        uint256 licenseId = licenseCount[_entity];
        LicenseInfo storage license = licenses[_entity][licenseId];
        
        uint256 totalVotesAgainst = GOIL_SUPPLY - license.totalVotes;
        uint256 votingPercentage = getLicenseVotingPercentage(_entity);
        uint8 status = uint8(getLicenseStatus(_entity));

        return (status, license.totalVotes, totalVotesAgainst, votingPercentage, license.startTime, license.endTime);
    }

    function getLastLicenseVotesByUser(address _entity, address _voter) public view returns (uint256) {
        uint256 licenseId = licenseCount[_entity];
        return getLicenseVotesByUser(_entity, licenseId, _voter);
    }

    function getLicenseVotesByUser(address _entity, uint256 _licenseId, address _voter) public view returns (uint256) {
        LicenseInfo storage license = licenses[_entity][_licenseId];
        return license.voters[_voter];
    }

    function getLicenseVotingPercentage(address _entity) public view returns (uint256) {
        uint256 licenseId = licenseCount[_entity];
        LicenseInfo storage license = licenses[_entity][licenseId];

        return (license.totalVotes * PERCENTAGE_DENOMINATOR) / GOIL_SUPPLY;
    }

    function getRefundableAmount(address _entity) public view returns (uint256) {
        LicenseState state = getLicenseStatus(_entity);
        uint256 licenseFee = licenseFeeAndCollateralPaid[_entity].licenseFee;
        uint256 collateral = licenseFeeAndCollateralPaid[_entity].collateral;

        return state == LicenseState.PENDING ? 0 : licenseFee + collateral;
    }

    function _isContract(address _address) private view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_address)
        }
        return (size > 0);
    }
}