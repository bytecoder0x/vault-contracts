// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Vault} from "./Vault.sol";

import {IVaultFactory} from "../interfaces/vaults/IVaultFactory.sol";
import {ITreasury} from "../interfaces/vaults/ITreasury.sol";
import {IScoring} from "../interfaces/vaults/IScoring.sol";
import {IOracle} from "../interfaces/vaults/IOracle.sol";

contract VaultFactory is Ownable, IVaultFactory {
    using Clones for address;

    uint256 public constant MAX_BIPS = 100_00;
    uint256 public constant COLLATERAL_PERCENTAGE = 10_00;

    IOracle public immutable ORACLE;
    address public immutable DEPOSIT_TOKEN;
    address public immutable GOIL_TOKEN;
    address public immutable VAULT_IMPLEMENTATION;

    address public immutable ROUTER_V3;
    address public immutable ROUTER_V2;
    address public immutable QUOTER;

    ITreasury public TREASURY;
    IScoring public SCORING;

    VaultInfo[] public allVaults;
    mapping(address => VaultInfo) public vaults;

    modifier withSetupScoringAndTreasuryContracts() {
        if (address(SCORING) == address(0)) revert ScoringContractNotSet();
        if (address(TREASURY) == address(0)) revert TreasuryContractNotSet();
        _;
    }

    constructor(
        address _owner,
        address _depositToken,
        address _goilToken,
        address _oracle,
        address _routerV2,
        address _routerV3,
        address _quoter
    ) Ownable(_owner) {
        if (!_isContract(_oracle)) revert OracleMustBeContract();
        if (!_isContract(_depositToken)) revert DepositTokenMustBeContract();
        if (!_isContract(_routerV2)) revert RouterV2MustBeContract();
        if (!_isContract(_routerV3)) revert RouterV3MustBeContract();
        if (!_isContract(_quoter)) revert QuoterMustBeContract();

        ORACLE = IOracle(_oracle);
        DEPOSIT_TOKEN = _depositToken;
        GOIL_TOKEN = _goilToken;
        ROUTER_V2 = _routerV2;
        ROUTER_V3 = _routerV3;
        QUOTER = _quoter;
        VAULT_IMPLEMENTATION = address(new Vault());
    }

    function createVault(
        uint256 _interestRate,
        uint256 _desiredCap,
        uint256 _startTime,
        uint256 _fundingPeriod,
        uint256 _unlockPeriod
    ) external withSetupScoringAndTreasuryContracts {
        uint256 fundingEndTime = _startTime + _fundingPeriod;
        uint256 unlockEndTime = _startTime + _unlockPeriod;

        if (_desiredCap == 0) revert DesiredCapCannotBeZero();
        if (_interestRate == 0) revert InterestRateCannotBeZero();
        if (_startTime <= block.timestamp) revert StartTimeMustBeInFuture();
        if (fundingEndTime <= _startTime) revert StartTimeMustBeBeforeFundingEndTime();
        if (unlockEndTime <= fundingEndTime) revert FundingEndTimeMustBeBeforeUnlockEndTime();

        uint256 maxPoolSize = SCORING.getMaxPoolSize(msg.sender);
        uint256 maxAllowedPoolSize = maxPoolSize + (_interestRate * _unlockPeriod) / MAX_BIPS;
        uint256 promisedCap = (_desiredCap * (MAX_BIPS + _interestRate)) / MAX_BIPS;

        if (_desiredCap > maxAllowedPoolSize) revert NooAllowedPoolSize();

        Vault vault = Vault(VAULT_IMPLEMENTATION.clone());
        vault.initialize(
            msg.sender,
            address(SCORING),
            address(TREASURY),
            GOIL_TOKEN,
            DEPOSIT_TOKEN,
            ROUTER_V2,
            ROUTER_V3,
            QUOTER,
            _desiredCap,
            promisedCap,
            _startTime,
            fundingEndTime,
            unlockEndTime
        );

        uint256 refundableAmount = ORACLE.getPaymentAmountForTokens(_desiredCap);
        uint256 requiredCollateral = TREASURY.getRequiredCollateral(_desiredCap);

        VaultInfo memory newVault = VaultInfo({
            entity: msg.sender,
            interestRate: _interestRate,
            desiredCap: _desiredCap,
            startTime: _startTime,
            fundingEndTime: fundingEndTime,
            unlockEndTime: unlockEndTime,
            collateralAmount: requiredCollateral,
            refundableAmount: refundableAmount
        });

        vaults[address(vault)] = newVault;
        allVaults.push(newVault);
        TREASURY.depositCollateral(address(vault));

        emit VaultCreated(address(vault), msg.sender, newVault);
    }

    function setScoringContract(address _scoringContract) public onlyOwner {
        if (!_isContract(_scoringContract)) revert ScoringContractMustBeContract();
        if (address(SCORING) != address(0)) revert ScoringContractAlreadySet();

        SCORING = IScoring(_scoringContract);
        emit ScoringContractSet(_scoringContract);
    }

    function setTreasuryContract(address _treasuryContract) public onlyOwner {
        if (!_isContract(_treasuryContract)) revert TreasuryContractMustBeContract();
        if (address(TREASURY) != address(0)) revert TreasuryContractAlreadySet();

        TREASURY = ITreasury(_treasuryContract);
        emit TreasuryContractSet(_treasuryContract);
    }

    function getIsValidVault(address _vault) public view returns (bool) {
        return vaults[_vault].entity != address(0);
    }

    function getVaultEntity(address _vault) public view returns (address) {
        return vaults[_vault].entity;
    }

    function getCollateralAmount(address _vault) public view returns (uint256) {
        return vaults[_vault].collateralAmount;
    }

    function getRefundableAmount(address _vault) public view returns (uint256) {
        return vaults[_vault].refundableAmount;
    }

    function getVault(address _vault) public view returns (VaultInfo memory) {
        return vaults[_vault];
    }

    function getAllVaults() public view returns (VaultInfo[] memory) {
        return allVaults;
    }

    function getVaultsCount() public view returns (uint256) {
        return allVaults.length;
    }

    function _isContract(address _address) private view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_address)
        }
        return (size > 0);
    }
}
