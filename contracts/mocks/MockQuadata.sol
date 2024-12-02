// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

contract MockQuadata {
    bytes32 public constant REQUIRED_KYB = keccak256("IS_BUSINESS");
    mapping(address => mapping(bytes32 => uint256)) public _balanceOf;

    constructor() {}

    function mint(address _entity, uint256 _amount) public {
        _balanceOf[_entity][REQUIRED_KYB] += _amount;
    }

    function balanceOf(address _entity, bytes32 _attribute) public view returns (uint256) {
        return _balanceOf[_entity][_attribute];
    }
}