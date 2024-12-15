// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV2Router01} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IQuoterV2} from "@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";
import {ITokenVesting} from "../interfaces/vesting/ITokenVesting.sol";
import {ITokenSale} from "../interfaces/sale/ITokenSale.sol";
import {IWETH} from "../interfaces/common/IWETH.sol";

contract TokenSale is ITokenSale, Ownable, Pausable {
    using SafeERC20 for IERC20;

    uint256 public constant MAX_BIPS = 100_00;
    uint256 public constant SLIPPAGE_MULTIPLIER = MAX_BIPS - 2_00; // 2%
    uint256 public constant TRANSACTION_TIMEOUT = 15 minutes;
    uint32 public constant SECONDS_AGO = 2 hours;

    IERC20 public immutable SALE_TOKEN;
    IERC20 public immutable USDC_TOKEN;
    IERC20 public immutable USDT_TOKEN;
    IWETH public immutable WETH_TOKEN;

    ISwapRouter public immutable ROUTER_V3;
    IUniswapV2Router01 public immutable ROUTER_V2;
    IQuoterV2 public immutable QUOTER;

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
        address _routerV2,
        address _routerV3,
        address _quoter,
        address _owner
    ) Ownable(_owner) {
        if (!_isContract(_saleToken)) revert IsNotContract(_saleToken);
        if (!_isContract(_routerV2)) revert IsNotContract(_routerV2);
        if (!_isContract(_routerV3)) revert IsNotContract(_routerV3);
        if (!_isContract(_quoter)) revert IsNotContract(_quoter);

        SALE_TOKEN = IERC20(_saleToken);
        USDC_TOKEN = IERC20(_usdcToken);
        USDT_TOKEN = IERC20(_usdtToken);
        WETH_TOKEN = IWETH(_wethToken);
        ROUTER_V2 = IUniswapV2Router01(_routerV2);
        ROUTER_V3 = ISwapRouter(_routerV3);
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

        emit RoundCreated(rounds.length, _tokenAmount, _price, _startTime, _endTime);
    }

    function buyTokens(uint256 _roundId, uint256 _amount, address _paymentToken) external payable whenNotPaused roundExists(_roundId) {
        Round memory round = roundsById[_roundId];
        uint256 currentTime = block.timestamp;

        if (_amount == 0) revert NoTokensToBuy();
        if (_paymentToken != address(WETH_TOKEN) && _paymentToken != address(USDC_TOKEN) && _paymentToken != address(USDT_TOKEN)) revert InvalidPaymentToken();
        if (currentTime < round.startTime || currentTime > round.endTime) revert RoundNotActive();
        if (round.soldAmount + _amount > round.tokenAmount) revert InsufficientTokensInRound();

        uint256 paymentAmount = _amount * round.price / SALE_TOKEN_PRECISION;
        if (paymentAmount == 0) revert PaymentAmountIsZero();
        

        if (_paymentToken == address(WETH_TOKEN)) {
            paymentAmount = getNativeForTokens(_roundId, _amount);
            if (msg.value < paymentAmount) revert InsufficientEthSent();

            uint256 wethBalanceBefore = WETH_TOKEN.balanceOf(address(this));
            WETH_TOKEN.deposit{value: msg.value}();

            uint256 excess = WETH_TOKEN.balanceOf(address(this)) - (wethBalanceBefore + paymentAmount);
            if (excess > 0) WETH_TOKEN.transfer(msg.sender, excess);

            _swap(_paymentToken, paymentAmount);
        } else if (_paymentToken == address(USDT_TOKEN)) {
            if (msg.value != 0) revert EthNotAllowedForErc20Purchase();
            _swap(_paymentToken, paymentAmount);
        } else {
            if (msg.value != 0) revert EthNotAllowedForErc20Purchase();
            IERC20(_paymentToken).safeTransferFrom(msg.sender, address(this), paymentAmount);
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

    function getStableForTokens(uint256 _roundId, uint256 _tokenAmount) public view roundExists(_roundId) returns (uint256) {
        uint256 price = roundsById[_roundId].price;
        uint256 stableAmount = _tokenAmount * price / SALE_TOKEN_PRECISION;
        return stableAmount;
    }

    function getTokensForStable(uint256 _roundId, uint256 _stableAmount) public view roundExists(_roundId) returns (uint256) {
        uint256 price = roundsById[_roundId].price;
        uint256 tokenAmount = _stableAmount * SALE_TOKEN_PRECISION / price;
        return tokenAmount;
    }

    function getNativeForTokens(uint256 _roundId, uint256 _tokenAmount) public roundExists(_roundId) returns (uint256) {
        uint256 stableAmount = getStableForTokens(_roundId, _tokenAmount);
        (, , uint256 nativeAmount) = _decider(stableAmount, address(USDT_TOKEN), address(WETH_TOKEN));
        return nativeAmount;
    }

    function getTokensForNative(uint256 _roundId, uint256 _nativeAmount) public roundExists(_roundId) returns (uint256) {
        (, , uint256 stableAmount) = _decider(_nativeAmount, address(WETH_TOKEN), address(USDT_TOKEN));
        uint256 tokenAmount = getTokensForStable(_roundId, stableAmount);
        return tokenAmount;
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

    function _swap(address _tokenIn, uint256 _amountIn) private returns (uint256 amountOut) {
        address tokenOut = address(USDC_TOKEN);
        (Swap decision, uint24 fee, uint256 maxAmount) = _decider(_amountIn, _tokenIn, tokenOut);

        if (decision == Swap.V2) {
            address[] memory path = new address[](2);
            path[0] = _tokenIn;
            path[1] = tokenOut;

            amountOut = _swapV2(path, _amountIn, maxAmount);
        } else {
            amountOut = _swapV3(_tokenIn, fee, _amountIn, maxAmount);
        }
    }

    function _decider(uint256 _amountIn, address _tokenIn, address _tokenOut) private returns (Swap, uint24, uint256) {
        uint256 amount1 = _getQuote(_tokenIn, _tokenOut, _amountIn, 5_00); //fee 0.05%
        uint256 amount2 = _getQuote(_tokenIn, _tokenOut, _amountIn, 3_000); //fee 0.3%
        uint256 amount3;

        address[] memory path = new address[](2);
        path[0] = _tokenIn;
        path[1] = _tokenOut;

        try ROUTER_V2.getAmountsOut(_amountIn, path) returns (uint256[] memory result) {
            amount3 = result[1];
        } catch {
            amount3 = 0;
        }

        uint256 maxAmount = amount1;
        uint24 fee = 5_00;
        Swap decision = Swap.V3_500;

        if (amount2 > maxAmount) {
            maxAmount = amount2;
            decision = Swap.V3_3000;
            fee = 30_00;
        }

        if (amount3 > maxAmount) {
            maxAmount = amount3;
            decision = Swap.V2;
            fee = 0;
        }

        return (decision, fee, maxAmount);
    }

    function _getQuote(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        uint24 _fee
    ) private returns (uint256) {
        uint256 amountOut;

        IQuoterV2.QuoteExactInputSingleParams memory params = IQuoterV2
            .QuoteExactInputSingleParams({
                tokenIn: _tokenIn,
                tokenOut: _tokenOut,
                amountIn: _amountIn,
                fee: _fee,
                sqrtPriceLimitX96: 0
            });

        try QUOTER.quoteExactInputSingle(params) returns (uint256 out, uint160 , uint32, uint256) {
            amountOut = out;
        } catch {
            amountOut = 0;
        }

        return amountOut;
    }

    function _swapV2(address[] memory _path, uint256 _amountIn, uint256 _amountOut) private returns (uint256 amountOut) {
        uint256 amountOutMin = _amountOut * SLIPPAGE_MULTIPLIER / MAX_BIPS;
        uint256 deadline = block.timestamp + TRANSACTION_TIMEOUT;

        uint256[] memory amounts = ROUTER_V2.swapExactTokensForTokens(_amountIn, amountOutMin, _path, address(this), deadline);
        return amounts[amounts.length - 1];
    }

    function _swapV3(address _tokenIn, uint24 _fee, uint256 _amountIn, uint256 _amountOut) private returns (uint256 amountOut) {
        uint256 amountOutMin = _amountOut * SLIPPAGE_MULTIPLIER / MAX_BIPS;
        uint256 deadline = block.timestamp + TRANSACTION_TIMEOUT;

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: _tokenIn,
            tokenOut: address(USDC_TOKEN),
            fee: _fee,
            recipient: address(this),
            deadline: deadline,
            amountIn: _amountIn,
            amountOutMinimum: amountOutMin,
            sqrtPriceLimitX96: 0 
        });

        amountOut = ROUTER_V3.exactInputSingle(params);
    }

    function _isContract(address _address) private view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_address)
        }
        return (size > 0);
    }
}