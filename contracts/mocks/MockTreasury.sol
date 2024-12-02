// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockTreasury is Ownable {
    mapping(address => uint256) public balanceOf;

    constructor() Ownable(msg.sender) {}

    function deposit(uint256 _amount, address _token) public {
        IERC20(_token).transferFrom(msg.sender, address(this), _amount);
    }

    function withdraw(uint256 _amount, address _token) public onlyOwner {
        IERC20(_token).transfer(msg.sender, _amount);
    }
}