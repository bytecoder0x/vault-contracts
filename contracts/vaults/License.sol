// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IQuadReader} from "@quadrata/contracts/interfaces/IQuadReader.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IScoring} from "../interfaces/vaults/IScoring.sol";
import {ILicense} from "../interfaces/vaults/ILicense.sol";
import {ITreasury} from "../interfaces/vaults/ITreasury.sol";

contract License is AccessControl, ILicense {
    bytes32 public constant LICENSE_MANAGER_ROLE = keccak256("LICENSE_MANAGER_ROLE");
    bytes32 public constant REQUIRED_KYB = keccak256("IS_BUSINESS");
    
    uint256 public constant ONE_MONTH_IN_SECONDS = 2628000; // ~ 30.42 days it is more accurate in seconds

    IQuadReader public immutable QADRATA_READER;
    IERC20 public immutable GOIL_TOKEN;
    ITreasury public immutable TREASURY;
    IScoring public SCORING;

    uint256 public votingPeriod = 7 days;
    uint256 public licenseExpirationLimit = 12 * ONE_MONTH_IN_SECONDS; // 1 year

    uint256 public applicationFee;
    uint256 public licenseMonthlyFee;

    LicenseInfo[] public pendingLicenses;

    mapping(address => LicenseInfo) public licenses;
    mapping(address => LicenseFeeAndCollateral) public licenseFeeAndCollateralPaid;

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

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(LICENSE_MANAGER_ROLE, _admin);
    }

    function submitLicense(uint256 _months, uint256 _collateralAmount) external withSetupScoringContract {
        uint256 licenseStartTime = block.timestamp + votingPeriod;

        if (getLicenseIsActive(msg.sender)) {
            licenseStartTime = licenses[msg.sender].endTime + votingPeriod;
        }

        uint256 licenseEndTime = licenseStartTime + _months * ONE_MONTH_IN_SECONDS;
        uint256 licensePeriod = licenseEndTime - licenseStartTime;

        if (QADRATA_READER.balanceOf(msg.sender, REQUIRED_KYB) == 0) revert ApplicantMustHaveQadrataKYB();
        if (licensePeriod < ONE_MONTH_IN_SECONDS) revert LicensePeriodTooShort();
        if (licenseExpirationLimit < licensePeriod) revert LicensePeriodTooLong();
        if (getLicenseIsPending(msg.sender)) revert LicenseAlreadySubmitted();

        uint256 licenseFee = _months * licenseMonthlyFee;
        uint256 licenseFeeAndCollateral = licenseFee + _collateralAmount;

        GOIL_TOKEN.transferFrom(msg.sender, address(TREASURY), applicationFee);
        GOIL_TOKEN.transferFrom(msg.sender, address(this), licenseFeeAndCollateral);

        licenseFeeAndCollateralPaid[msg.sender].licenseFee = licenseFee;
        licenseFeeAndCollateralPaid[msg.sender].collateral = _collateralAmount;

        licenses[msg.sender].startTime = licenseStartTime;
        licenses[msg.sender].endTime = licenseEndTime;
        licenses[msg.sender].approved = false;
        licenses[msg.sender].confirmedByAdmin = false;

        pendingLicenses.push(LicenseInfo({
            entity: msg.sender,
            startTime: licenseStartTime,
            endTime: licenseEndTime,
            approved: false,
            confirmedByAdmin: false
        }));

        emit SubmittedLicense(msg.sender, licenseStartTime, licenseEndTime, licenseFee, _collateralAmount);
    }

    function approveLicense(address _entity, bool _approved) public onlyRole(LICENSE_MANAGER_ROLE) {
        if (!getLicenseIsPending(_entity)) revert LicenseIsNotPending();

        uint256 licenseFee = licenseFeeAndCollateralPaid[_entity].licenseFee;
        uint256 collateral = licenseFeeAndCollateralPaid[_entity].collateral;

        if (_approved) {
            GOIL_TOKEN.transfer(address(TREASURY), licenseFee);
            GOIL_TOKEN.approve(address(TREASURY), collateral);
            TREASURY.depositCollateral(_entity, collateral);

            licenseFeeAndCollateralPaid[_entity].collateral = 0;
            licenseFeeAndCollateralPaid[_entity].licenseFee = 0;

            licenses[_entity].approved = true;

            if (SCORING.isReadyToSetInitialScore(_entity)) SCORING.setInitialScore(_entity);
        } else {
            GOIL_TOKEN.transfer(_entity, licenseFee + collateral);
        }

        licenses[_entity].confirmedByAdmin = true;
        _removePendingLicense(_entity);

        emit LicenseApproved(_entity, _approved);
    }

    function approveLicenseBatch(
        address[] calldata _entities,
        bool[] calldata _approved
    ) public onlyRole(LICENSE_MANAGER_ROLE) {
        if (_entities.length != _approved.length) revert EntitiesAndApprovedLengthsMustBeTheSame();

        for (uint256 i = 0; i < _entities.length; i++) {
            approveLicense(_entities[i], _approved[i]);
        }
    }

    function setApplicationFee(uint256 _applicationFee) external onlyRole(LICENSE_MANAGER_ROLE) {
        if (applicationFee == _applicationFee) revert FeeCannotBeTheSame();

        applicationFee = _applicationFee;
        emit ApplicationFeeUpdated(_applicationFee);
    }

    function setLicenseMonthlyFee(uint256 _licenseMonthlyFee) external onlyRole(LICENSE_MANAGER_ROLE) {
        if (licenseMonthlyFee == _licenseMonthlyFee) revert FeeCannotBeTheSame();

        licenseMonthlyFee = _licenseMonthlyFee;
        emit LicenseMonthlyFeeUpdated(_licenseMonthlyFee);
    }

    function setVotingPeriod(uint256 _votingPeriod) external onlyRole(LICENSE_MANAGER_ROLE) {
        if (votingPeriod == _votingPeriod) revert VotingPeriodCannotBeTheSame();
        if (_votingPeriod == 0) revert VotingPeriodCannotBeZero();

        votingPeriod = _votingPeriod;
        emit VotingPeriodUpdated(_votingPeriod);
    }

    function setScoringContract(address _scoringContract) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!_isContract(_scoringContract)) revert ScoringContractMustBeContract();
        if (address(SCORING) != address(0)) revert ScoringContractAlreadySet();

        SCORING = IScoring(_scoringContract);
        emit ScoringContractUpdated(_scoringContract);
    }

    function setLicenseExpirationLimit(uint256 _months) external onlyRole(LICENSE_MANAGER_ROLE) {
        uint256 newLicenseExpirationLimit = _months * ONE_MONTH_IN_SECONDS;

        if (licenseExpirationLimit == newLicenseExpirationLimit) revert LicenseExpirationLimitCannotBeTheSame();
        if (newLicenseExpirationLimit == 0) revert LicenseExpirationLimitCannotBeZero();

        licenseExpirationLimit = newLicenseExpirationLimit;
        emit LicenseExpirationLimitUpdated(newLicenseExpirationLimit);
    }

    function getLicenseMonthlyAndApplicationFee() public view returns (uint256, uint256) {
        return (licenseMonthlyFee, applicationFee);
    }

    function getLicenseStatus(address _entity) public view returns (LicenseState) {
        LicenseInfo memory license = licenses[_entity];
        uint256 currentTime = block.timestamp;

        if (license.startTime == 0) return LicenseState.UNINITIALIZED;
        if ((license.startTime > currentTime && !license.approved) || !license.confirmedByAdmin) return LicenseState.PENDING;
        if (!license.approved && license.confirmedByAdmin) return LicenseState.REJECTED;
        if (license.endTime < currentTime) return LicenseState.EXPIRED;

        return LicenseState.ACTIVE;
    }

    function getLicenseIsActive(address _entity) public view returns (bool) {
        return getLicenseStatus(_entity) == LicenseState.ACTIVE;
    }

    function getLicenseIsPending(address _entity) public view returns (bool) {
        return getLicenseStatus(_entity) == LicenseState.PENDING;
    }

    function getLicenseExpirationTime(address _entity) public view returns (uint256) {
        return licenses[_entity].endTime;
    }

    function getLicenseByEntity(address _entity) public view returns (uint8, uint256, uint256, bool, bool) {
        LicenseInfo memory license = licenses[_entity];
        uint8 status = uint8(getLicenseStatus(_entity));

        return (status, license.startTime, license.endTime, license.approved, license.confirmedByAdmin);
    }

    function getAllPendingLicenses() public view returns (LicenseInfo[] memory) {
        return pendingLicenses;
    }

    function getCountsPendingLicenses() public view returns (uint256) {
        return pendingLicenses.length;
    }

    function _removePendingLicense(address _entity) private {
        uint256 totalPendingLicenses = pendingLicenses.length;
        for (uint256 i = 0; i < totalPendingLicenses; i++) {
            if (pendingLicenses[i].entity == _entity) {
                pendingLicenses[i] = pendingLicenses[totalPendingLicenses - 1];
                pendingLicenses.pop();
                break;
            }
        }
    }

    function _isContract(address _address) private view returns (bool) {
        uint32 size;

        assembly {
            size := extcodesize(_address)
        }
        return (size > 0);
    }
}