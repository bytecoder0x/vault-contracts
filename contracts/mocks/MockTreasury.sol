// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MockTreasury is Ownable {
    mapping(address => uint256) public balanceOf;

    constructor() Ownable(msg.sender) {}

    function deposit(uint256 _amount) public {
        balanceOf[msg.sender] += _amount;
    }

    function withdraw(uint256 _amount) public onlyOwner {
        balanceOf[msg.sender] -= _amount;
    }
}