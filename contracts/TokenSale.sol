// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ITokenVesting} from "./interface/ITokenVesting.sol";
import {IWETH} from"./interface/IWETH.sol";
import {ITokenSale} from "./interface/ITokenSale.sol";

contract TokenSale is ITokenSale, Ownable, Pausable {
    using SafeERC20 for IERC20;

    IERC20 public immutable SALE_TOKEN;
    IWETH public immutable WETH_TOKEN;
    uint256 public immutable SALE_TOKEN_PRECISION;

    address public vestingContract;

    Round[] rounds;

    mapping(uint256 => Round) public roundsById;
    mapping(address => Purchase[]) public userPurchases;

    constructor(address _saleToken, address _wethToken, address _owner) Ownable(_owner) {
        if (!_isContract(_saleToken)) revert IsNotContract(_saleToken);
        if (!_isContract(_wethToken)) revert IsNotContract(_wethToken);

        SALE_TOKEN = IERC20(_saleToken);
        WETH_TOKEN = IWETH(_wethToken);
        SALE_TOKEN_PRECISION = 10 ** IERC20Metadata(_saleToken).decimals();
    }

    function createRound(
        RoundType _roundType,
        address _paymentToken,
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
        if (!_isContract(_paymentToken)) revert IsNotContract(_paymentToken);

        Round memory newRound = Round({
            roundType: _roundType,
            paymentToken: _paymentToken,
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

        rounds.push(newRound);
        roundsById[rounds.length] = newRound;

        emit RoundCreated(rounds.length, _roundType, _paymentToken, _tokenAmount, _price, _startTime, _endTime);
    }

    function buyTokens(uint256 _roundId, uint256 _amount) external payable whenNotPaused {
        if (_roundId == 0 || _roundId > rounds.length) revert InvalidRoundId();
        Round storage round = roundsById[_roundId];
        if (block.timestamp < round.startTime || block.timestamp > round.endTime) revert RoundNotActive();
        if (round.soldAmount + _amount > round.tokenAmount) revert InsufficientTokensInRound();

        uint256 paymentAmount = getPaymentAmountForTokens(_roundId, _amount);

        if (round.paymentToken == address(WETH_TOKEN)) {
            if (msg.value < paymentAmount) revert InsufficientEthSent();

            WETH_TOKEN.deposit{value: paymentAmount}();
            uint256 excess = msg.value - paymentAmount;

            if (excess > 0) payable(msg.sender).transfer(excess);
        } else {
            if (msg.value != 0) revert EthNotAllowedForErc20Purchase();
            IERC20(round.paymentToken).safeTransferFrom(msg.sender, address(this), paymentAmount);
        }

        SALE_TOKEN.approve(vestingContract, _amount);
        ITokenVesting(vestingContract).createVesting(
            msg.sender,
            round.vestingStartTime,
            round.vestingEndTime,
            round.vestingCliffPeriod,
            round.vestingSlicePeriod,
            _amount,
            ITokenVesting.VestingType(uint8(round.roundType))
        );

        Purchase memory newPurchase = Purchase({
            roundId: _roundId,
            tokenAmount: _amount
        });

        userPurchases[msg.sender].push(newPurchase);
        round.soldAmount += _amount;

        emit TokensPurchased(msg.sender, _roundId, _amount, paymentAmount);
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

    function getPaymentAmountForTokens(uint256 _roundId, uint256 _tokenAmount) public view returns (uint256) {
        if (_roundId == 0 || _roundId > rounds.length) revert InvalidRoundId();
        Round storage round = roundsById[_roundId];

        return _tokenAmount * round.price / SALE_TOKEN_PRECISION;
    }

    function getTokenAmountForPayment(uint256 _roundId, uint256 _paymentAmount) public view returns (uint256) {
        if (_roundId == 0 || _roundId > rounds.length) revert InvalidRoundId();
        Round storage round = roundsById[_roundId];

        return _paymentAmount * SALE_TOKEN_PRECISION / round.price;
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