// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {IVaultFactory} from "../interfaces/vaults/IVaultFactory.sol";
import {MockVault} from "./MockVault.sol";
contract MockVaultFactory is IVaultFactory {
    mapping(address => VaultInfo) public vaults;

    constructor() {}

    function createVault(address _token) external returns (address) {
        address vault = address(new MockVault(_token));
        vaults[vault] = VaultInfo({
            depositToken: _token,
            interestRate: 0,
            desiredCap: 0,
            startTime: 0,
            endTime: 0
        });

        return vault;
    }

    function getIsValidVault(address _vault) external view returns (bool) {
        return vaults[_vault].depositToken != address(0);
    }
}