// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Vault} from "./Vault.sol";

contract VaultFactory is Ownable {
    using Clones for address;

    struct VaultInfo {
        address vault;
        address depositToken;
        uint256 interestRate;
        uint256 desiredCap;
        uint256 startTime;
        uint256 endTime;
    }

    address public vaultImplementation;

    VaultInfo[] public allVaults;
    mapping(uint256 => VaultInfo) public vaultById;

    event VaultCreated(address indexed vault, uint256 id);

    constructor(address _owner) Ownable(_owner) {
        vaultImplementation = address(new Vault());
    }

    function createVault(
        address _depositToken,
        uint256 _interestRate,
        uint256 _desiredCap,
        uint256 _startTime,
        uint256 _expirationPeriod
    ) public onlyOwner returns (address) {
        Vault vault = Vault(vaultImplementation.clone());

        vault.initialize(_depositToken, _interestRate, _desiredCap, _startTime, _expirationPeriod);

        uint256 vaultId = allVaults.length;
        VaultInfo memory newVault = VaultInfo({
            vault: address(vault),
            depositToken: _depositToken,
            interestRate: _interestRate,
            desiredCap: _desiredCap,
            startTime: _startTime,
            endTime: _startTime + _expirationPeriod
        });

        allVaults.push(newVault);
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
