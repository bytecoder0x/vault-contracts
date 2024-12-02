// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

interface IVaultFactory {
    struct VaultInfo {
        address owner;
        address depositToken;
        uint256 interestRate;
        uint256 desiredCap;
        uint256 startTime;
        uint256 endTime;
    }

    function vaults(address _vault) external view returns (address, address, uint256, uint256, uint256, uint256);

    function getIsValidVault(address _vault) external view returns (bool);
}
