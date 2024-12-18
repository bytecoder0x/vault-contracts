// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ITokenVesting} from "../interfaces/vesting/ITokenVesting.sol";
import {ITokenSale} from "../interfaces/sale/ITokenSale.sol";
import {IWETH} from "../interfaces/common/IWETH.sol";

contract TokenSale is ITokenSale, Ownable, Pausable {
    using SafeERC20 for IERC20;

    AggregatorV3Interface public immutable PRICE_FEED;
    IERC20 public immutable SALE_TOKEN;
    IERC20 public immutable USDC_TOKEN;
    IERC20 public immutable USDT_TOKEN;
    IWETH public immutable WETH_TOKEN;

    uint256 public immutable SALE_TOKEN_PRECISION;

    uint256 public totalTokensForSale;
    address public vestingContract;

    Round[] public rounds;
    mapping(uint256 => Round) public roundsById;
    mapping(address => Purchase[]) public userPurchases;

    constructor(
        address _saleToken,
        address _usdcToken,
        address _usdtToken,
        address _wethToken,
        address _priceFeed,
        address _owner
    ) Ownable(_owner) {
        if (!_isContract(_priceFeed)) revert IsNotContract(_priceFeed);
        if (!_isContract(_saleToken)) revert IsNotContract(_saleToken);
        if (!_isContract(_usdcToken)) revert IsNotContract(_usdcToken);
        if (!_isContract(_usdtToken)) revert IsNotContract(_usdtToken);
        if (!_isContract(_wethToken)) revert IsNotContract(_wethToken);

        PRICE_FEED = AggregatorV3Interface(_priceFeed);
        SALE_TOKEN = IERC20(_saleToken);
        USDC_TOKEN = IERC20(_usdcToken);
        USDT_TOKEN = IERC20(_usdtToken);
        WETH_TOKEN = IWETH(_wethToken);

        SALE_TOKEN_PRECISION = 10 ** IERC20Metadata(_saleToken).decimals();
    }

    modifier roundExists(uint256 _roundId) {
        if (_roundId == 0 || _roundId > rounds.length) revert InvalidRoundId();
        _;
    }

    function createRound(
        uint256 _price,
        uint256 _tokenAmount,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _vestingStartTime,
        uint256 _vestingEndTime,
        uint256 _vestingCliffPeriod,
        uint256 _vestingSlicePeriod
    ) external onlyOwner {
        if (vestingContract == address(0)) revert VestingContractIsNotSet();
        if (_startTime <= block.timestamp) revert StartTimeInPast();
        if (_endTime <= _startTime) revert EndTimeBeforeStartTime();
        if (_price == 0) revert InvalidPrice();
        if (_tokenAmount == 0) revert NoTokensToRound();
        if (_vestingStartTime < _endTime) revert EndTimeBeforeVestingStartTime();
        if (_vestingSlicePeriod == 0) revert VestingSlicePeriodIsZero();
        if (_vestingEndTime <= _vestingStartTime) revert VestingEndTimeBeforeVestingStartTime();
        if (_vestingCliffPeriod + _vestingSlicePeriod > _vestingEndTime - _vestingStartTime) revert VestingCliffAndSlicePeriodTooLong();
        if (_startTime <= roundsById[rounds.length].endTime) revert RoundStartTimeBeforePreviousRoundEndTime();

        Round memory newRound = Round({
            price: _price,
            tokenAmount: _tokenAmount,
            soldAmount: 0,
            startTime: _startTime,
            endTime: _endTime,
            vestingStartTime: _vestingStartTime,
            vestingEndTime: _vestingEndTime,
            vestingCliffPeriod: _vestingCliffPeriod,
            vestingSlicePeriod: _vestingSlicePeriod
        });

        totalTokensForSale += _tokenAmount;
        rounds.push(newRound);
        roundsById[rounds.length] = newRound;
        SALE_TOKEN.transferFrom(msg.sender, address(this), _tokenAmount);

        emit RoundCreated(rounds.length, newRound);
    }

    function buyTokens(uint256 _roundId, uint256 _amount, address _paymentToken) external payable whenNotPaused roundExists(_roundId) {
        Round memory round = roundsById[_roundId];
        uint256 currentTime = block.timestamp;

        if (_amount == 0) revert NoTokensToBuy();
        if (_paymentToken != address(WETH_TOKEN) && _paymentToken != address(USDC_TOKEN) && _paymentToken != address(USDT_TOKEN)) revert InvalidPaymentToken();
        if (currentTime < round.startTime || currentTime > round.endTime) revert RoundNotActive();
        if (round.soldAmount + _amount > round.tokenAmount) revert InsufficientTokensInRound();

        uint256 paymentAmount = getPaymentAmountForTokens(_roundId, _amount, _paymentToken);
        if (paymentAmount == 0) revert PaymentAmountIsZero();

        if (_paymentToken == address(WETH_TOKEN)) {
            if (msg.value < paymentAmount) revert InsufficientEthSent();

            uint256 wethBalanceBefore = WETH_TOKEN.balanceOf(address(this));
            WETH_TOKEN.deposit{value: msg.value}();

            uint256 excess = WETH_TOKEN.balanceOf(address(this)) - (wethBalanceBefore + paymentAmount);
            if (excess > 0) WETH_TOKEN.transfer(msg.sender, excess);
            IERC20(_paymentToken).safeTransfer(owner(), paymentAmount);
        } else {
            if (msg.value != 0) revert EthNotAllowedForErc20Purchase();
            IERC20(_paymentToken).safeTransferFrom(msg.sender, owner(), paymentAmount);
        }

        SALE_TOKEN.approve(vestingContract, _amount);
        ITokenVesting(vestingContract).createVesting(
            msg.sender,
            round.vestingStartTime,
            round.vestingEndTime,
            round.vestingCliffPeriod,
            round.vestingSlicePeriod,
            _amount,
            ITokenVesting.VestingType.PUBLIC
        );

        Purchase memory newPurchase = Purchase({
            roundId: _roundId,
            tokenAmount: _amount,
            paymentToken: _paymentToken
        });

        userPurchases[msg.sender].push(newPurchase);
        roundsById[_roundId].soldAmount += _amount;

        emit TokensPurchased(msg.sender, _roundId, _amount, _paymentToken);
    }

    function setVestingContract(address _vestingContract) external onlyOwner {
        if (vestingContract != address(0)) revert VestingAlreadySet();
        if (!_isContract(_vestingContract)) revert IsNotContract(_vestingContract);

        vestingContract = _vestingContract;
        emit VestingContractSet(_vestingContract);
    }

    function withdrawTokens(address _recipient, address _token, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(_recipient, _amount);
    }

    function withdrawAllTokens(address _token) external onlyOwner {
        uint256 balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, balance);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function getCurrentRoundId() external view returns (uint256) {
        uint256 currentTime = block.timestamp;
        for (uint256 i = 1; i <= rounds.length; i++) {
            Round memory round = roundsById[i];
            if (currentTime >= round.startTime && currentTime <= round.endTime) {
                return i;
            }
        }

        return 0;
    }

    function getLastFinishedRoundId() external view returns (uint256) {
        uint256 currentTime = block.timestamp;
        uint256 lastFinishedRound = 0;
        
        for (uint256 i = 1; i <= rounds.length; i++) {
            Round memory round = roundsById[i];
            if (currentTime > round.endTime) {
                lastFinishedRound = i;
            }
        }
        
        return lastFinishedRound;
    }

    function getPaymentAmountForTokens(uint256 _roundId, uint256 _tokenAmount, address _paymentToken) public view roundExists(_roundId) returns (uint256) {
        Round memory round = roundsById[_roundId];  
        uint256 price = _paymentToken == address(WETH_TOKEN) ? getPricePerTokenInNative(_roundId) : round.price;
        return _tokenAmount * price / SALE_TOKEN_PRECISION;
    }

    function getTokenAmountForPayment(uint256 _roundId, uint256 _paymentAmount, address _paymentToken) public view roundExists(_roundId) returns (uint256) {
        Round memory round = roundsById[_roundId];
        uint256 price = _paymentToken == address(WETH_TOKEN) ? getPricePerTokenInNative(_roundId) : round.price;
        return _paymentAmount * SALE_TOKEN_PRECISION / price;
    }

    function getPricePerTokenInNative(uint256 _roundId) public view roundExists(_roundId) returns (uint256) {
        uint256 priceInStable = roundsById[_roundId].price;
        (, int priceETH, , , ) = PRICE_FEED.latestRoundData();
        if (priceETH < 0) revert InvalidPrice();

        uint256 stablePrecision = 10 ** IERC20Metadata(address(USDC_TOKEN)).decimals();
        uint256 formatedPriceETH = uint256(priceETH) * stablePrecision / 10 ** PRICE_FEED.decimals();
        uint256 pricePerToken = priceInStable * 10 ** 18 / formatedPriceETH;
        
        return pricePerToken;
    }

    function getTotalEarnedForRound(uint256 _roundId) public view roundExists(_roundId) returns (uint256) {
        Round memory round = roundsById[_roundId];
        return round.soldAmount * round.price / SALE_TOKEN_PRECISION;
    }

    function getUserPurchases(address _user) public view returns (Purchase[] memory) {
        return userPurchases[_user];
    }

    function getUserPurchasesCount(address _user) public view returns (uint256) {
        return userPurchases[_user].length;
    }

    function getAllRounds() public view returns (Round[] memory) {
        return rounds;
    }

    function getRoundsCount() public view returns (uint256) {
        return rounds.length;
    }

    function _isContract(address _address) private view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_address)
        }
        return (size > 0);
    }
}