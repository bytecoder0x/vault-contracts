// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

contract MockFactory {
    mapping(address => mapping(address => mapping(uint24 => address))) public getPool;

    constructor() { }

    function setPool(address tokenA, address tokenB, uint24 fee, address pool) public {
        getPool[tokenA][tokenB][fee] = pool;
        getPool[tokenB][tokenA][fee] = pool;
    }
}