// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Vault} from "./Vault.sol";

contract VaultFactory is Ownable {
    using Clones for address;

    struct VaultInfo {
        address vault;
        bool isNativeToken;
        address depositToken;
        uint256 interestRate;
        uint256 desiredCap;
        uint256 startTime;
        uint256 fundingEndTime;
        uint256 unlockEndTime;
    }

    address public vaultImplementation;

    VaultInfo[] public allVaults;
    mapping(uint256 => VaultInfo) public vaultById;

    event VaultCreated(address indexed vault, uint256 id);

    constructor(address _owner) Ownable(_owner) {
        vaultImplementation = address(new Vault());
    }

    function createVault(
        bool _isNativeToken,
        address _depositToken,
        uint256 _interestRate,
        uint256 _desiredCap,
        uint256 _startTime,
        uint256 _fundingPeriod,
        uint256 _unlockPeriod
    ) public onlyOwner returns (address) {
        uint256 fundingEndTime = _startTime + _fundingPeriod;
        uint256 unlockEndTime = _startTime + _unlockPeriod;

        Vault vault = Vault(vaultImplementation.clone());
        vault.initialize(_isNativeToken, _depositToken, _interestRate, _desiredCap, _startTime, fundingEndTime, unlockEndTime);
        VaultInfo memory newVault = VaultInfo({
            vault: address(vault),
            isNativeToken: _isNativeToken,
            depositToken: _depositToken,
            interestRate: _interestRate,
            desiredCap: _desiredCap,
            startTime: _startTime,
            fundingEndTime: fundingEndTime,
            unlockEndTime: unlockEndTime
        });

        allVaults.push(newVault);
        uint256 vaultId = allVaults.length;
        vaultById[vaultId] = newVault;

        emit VaultCreated(address(vault), vaultId);

        return address(vault);
    }

    function getAllVaults() public view returns (VaultInfo[] memory) {
        return allVaults;
    }

    function getVaultsCount() public view returns (uint256) {
        return allVaults.length;
    }
}
