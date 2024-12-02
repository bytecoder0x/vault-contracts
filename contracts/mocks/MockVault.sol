// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

contract MockVault {
    address public immutable DEPOSIT_TOKEN;

    constructor(address _depositToken) {
        DEPOSIT_TOKEN = _depositToken;
    }
}