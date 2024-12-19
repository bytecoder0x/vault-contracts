// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

interface IOracle {
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
    function getPaymentAmountForTokens(uint256 _tokenAmount) external view returns (uint256);
    function getTokenAmountForPayment(uint256 _paymentAmount) external view returns (uint256);
    function setSecondsAgo(uint32 _secondsAgo) external;
    function setPoolForTrackingPrice(address _purchaseToken, uint24 _poolFee) external;
}