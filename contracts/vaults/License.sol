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
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant REQUIRED_KYB = keccak256("IS_BUSINESS");
    
    uint256 public constant PERCENTAGE_DENOMINATOR = 100_00;

    IQuadReader public immutable QADRATA_READER;
    IERC20 public immutable GOIL_TOKEN;
    ITreasury public immutable TREASURY;
    IScoring public SCORING;

    uint256 public votingPeriod = 7 days;
    uint256 public licenseExpirationLimit = 365 days; // 12 months

    uint256 public applicationFee;
    uint256 public licenseMonthlyFee;

    LicenseInfo[] public allPendingLicenses;

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
        _grantRole(MANAGER_ROLE, _admin);
    }

    function submitLicense(uint256 _licenseEndTime, uint256 _collateralAmount) external withSetupScoringContract {
        uint256 licenseStartTime = block.timestamp + votingPeriod;

        if (getLicenseIsActive(msg.sender)) {
            licenseStartTime = licenses[msg.sender].endTime + votingPeriod;
        }

        uint256 licensePeriod = _licenseEndTime - licenseStartTime;

        if (QADRATA_READER.balanceOf(msg.sender, REQUIRED_KYB) == 0) revert ApplicantMustHaveQadrataKYB();
        if (licensePeriod < 30 days) revert LicensePeriodTooShort();
        if (licenseExpirationLimit < licensePeriod) revert LicensePeriodTooLong();
        if (getLicenseIsPending(msg.sender)) revert LicenseAlreadySubmitted();

        uint256 licenseFee = (licensePeriod / 30 days) * licenseMonthlyFee;
        uint256 licenseFeeAndCollateral = licenseFee + _collateralAmount;

        GOIL_TOKEN.transferFrom(msg.sender, address(TREASURY), applicationFee);
        GOIL_TOKEN.transferFrom(msg.sender, address(this), licenseFeeAndCollateral);

        licenseFeeAndCollateralPaid[msg.sender].licenseFee = licenseFee;
        licenseFeeAndCollateralPaid[msg.sender].collateral = _collateralAmount;

        licenses[msg.sender].startTime = licenseStartTime;
        licenses[msg.sender].endTime = _licenseEndTime;
        licenses[msg.sender].approved = false;
        licenses[msg.sender].confirmedByAdmin = false;

        allPendingLicenses.push(LicenseInfo({
            entity: msg.sender,
            startTime: licenseStartTime,
            endTime: _licenseEndTime,
            approved: false,
            confirmedByAdmin: false
        }));

        emit SubmittedLicense(msg.sender, licenseStartTime, _licenseEndTime, licenseFee, _collateralAmount);
    }

    function approveLicense(address _entity, bool _approved) external onlyRole(LICENSE_MANAGER_ROLE) {
        if (!getLicenseIsPending(_entity)) revert LicenseIsNotPending();

        LicenseFeeAndCollateral memory licenseFeeAndCollateral = licenseFeeAndCollateralPaid[_entity];

        if (_approved) {
            GOIL_TOKEN.transfer(address(TREASURY), licenseFeeAndCollateral.licenseFee);
            GOIL_TOKEN.approve(address(TREASURY), licenseFeeAndCollateral.collateral);
            TREASURY.depositCollateral(_entity, licenseFeeAndCollateral.collateral);

            licenseFeeAndCollateralPaid[_entity].collateral = 0;
            licenseFeeAndCollateralPaid[_entity].licenseFee = 0;

            licenses[_entity].approved = true;

            if (SCORING.getIsReadyToSetInitialScore(_entity)) SCORING.setInitialScore(_entity);
        } else {
            GOIL_TOKEN.transfer(_entity, licenseFeeAndCollateral.licenseFee + licenseFeeAndCollateral.collateral);
        }

        licenses[_entity].confirmedByAdmin = true;

        uint256 totalPendingLicenses = allPendingLicenses.length; // for gas optimization
        for (uint256 i = 0; i < totalPendingLicenses; i++) {
            if (allPendingLicenses[i].entity == _entity) {
                allPendingLicenses[i] = allPendingLicenses[totalPendingLicenses - 1];
                allPendingLicenses.pop();
                break;
            }
        }

        emit LicenseApproved(_entity, _approved);
    }

    function setScoringContract(address _scoringContract) external onlyRole(DEFAULT_ADMIN_ROLE) {
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
        return allPendingLicenses;
    }

    function getTotalPendingLicenses() public view returns (uint256) {
        return allPendingLicenses.length;
    }


    function _isContract(address _address) private view returns (bool) {
        uint32 size;

        assembly {
            size := extcodesize(_address)
        }
        return (size > 0);
    }
}