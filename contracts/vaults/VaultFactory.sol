// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Vault} from "./Vault.sol";

contract VaultFactory is Ownable {
    using Clones for address;

    error ScoringContractAlreadySet();
    error ScoringContractNotSet();
    error TreasuryContractCannotBeZeroAddress();
    error TreasuryContractAlreadySet();
    error TreasuryContractNotSet();
    error ScoringContractMustBeContract();
    error TreasuryContractMustBeContract();

    event ScoringContractSet(address indexed scoringContract);
    event TreasuryContractSet(address indexed treasuryContract);

    struct VaultInfo {
        address entity;
        uint256 interestRate;
        uint256 desiredCap;
        uint256 startTime;
        uint256 fundingEndTime;
        uint256 unlockEndTime;
    }

    address public immutable DEPOSIT_TOKEN;
    address public immutable VAULT_IMPLEMENTATION;

    address public treasuryContract;
    address public scoringContract;

    VaultInfo[] public allVaults;
    mapping(address => VaultInfo) public vaults;

    event VaultCreated(address indexed vault, address indexed owner);

    modifier withSetupScoringAndTreasuryContracts() {
        if (scoringContract == address(0)) revert ScoringContractNotSet();
        if (treasuryContract == address(0)) revert TreasuryContractNotSet();
        _;
    }

    constructor(address _owner, address _depositToken) Ownable(_owner) {
        DEPOSIT_TOKEN = _depositToken;
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

        Vault vault = Vault(VAULT_IMPLEMENTATION.clone());
        vault.initialize(
            msg.sender,
            scoringContract,
            treasuryContract,
            DEPOSIT_TOKEN,
            _interestRate,
            _desiredCap,
            _startTime,
            fundingEndTime,
            unlockEndTime
        );

        VaultInfo memory newVault = VaultInfo({
            entity: msg.sender,
            interestRate: _interestRate,
            desiredCap: _desiredCap,
            startTime: _startTime,
            fundingEndTime: fundingEndTime,
            unlockEndTime: unlockEndTime
        });

        allVaults.push(newVault);
        vaults[address(vault)] = newVault;

        emit VaultCreated(address(vault), msg.sender);
    }

    function getIsValidVault(address _vault) public view returns (bool) {
        return vaults[_vault].entity != address(0);
    }

    function getAllVaults() public view returns (VaultInfo[] memory) {
        return allVaults;
    }

    function getVaultsCount() public view returns (uint256) {
        return allVaults.length;
    }

    function setScoringContract(address _scoringContract) public onlyOwner {
        if (!_isContract(_scoringContract)) revert ScoringContractMustBeContract();
        if (scoringContract != address(0)) revert ScoringContractAlreadySet();

        scoringContract = _scoringContract;
        emit ScoringContractSet(_scoringContract);
    }

    function setTreasuryContract(address _treasuryContract) public onlyOwner {
        if (!_isContract(_treasuryContract)) revert TreasuryContractMustBeContract();
        if (treasuryContract != address(0)) revert TreasuryContractAlreadySet();

        treasuryContract = _treasuryContract;
        emit TreasuryContractSet(_treasuryContract);
    }

    function _isContract(address _address) private view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_address)
        }
        return (size > 0);
    }
}
