// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

interface IVault {
    function totalAssets() external view returns (uint256);
    function promisedCap() external view returns (uint256);
    function desiredCap() external view returns (uint256);
    function owner() external view returns (address);
    function isVaultFailed() external view returns (bool);
}

