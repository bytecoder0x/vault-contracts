// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

interface IOracale {
    event PurchaseTokenUpdated(address indexed purchaseToken);
    event SecondsAgoUpdated(uint32 indexed secondsAgo);

    error PurchaseTokenMustBeContract();
    error GoilTokenMustBeContract();
    error PoolMustBeContract();
    error ZeroSecondsAgo();
    error SecondsCannotBeTheSame();
    error UniswapFactoryMustBeContract();
    error PoolDoesNotExist();
    error PoolCannotBeTheSame();

    function purchaseToken() external view returns (address);
    function pool() external view returns (address);
    function secondsAgo() external view returns (uint32);

    function getPricePerToken() external view returns (uint256);
    function getPriceForTokens(uint256 _amount) external view returns (uint256);
    function getTokensPerPrice(uint256 _price) external view returns (uint256);
    function setSecondsAgo(uint32 _secondsAgo) external;
    function setPoolForTrackingPrice(address _purchaseToken, uint24 _poolFee) external;
}