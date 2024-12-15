// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OracleLibrary} from "../libraries/OracleLibrary.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {ITokenVesting} from "../interfaces/vesting/ITokenVesting.sol";
import {IWETH} from "../interfaces/common/IWETH.sol";
import {ITokenSale} from "../interfaces/sale/ITokenSale.sol";

contract TokenSale is ITokenSale, Ownable, Pausable {
    using SafeERC20 for IERC20;

    uint24 public constant DEFAULT_POOL_FEE = 5_00; // 0.05%
    uint256 public constant DEFAULT_TRANSACTION_TIMEOUT = 1000;

    uint256 public constant MAX_BIPS = 100_00;
    uint256 public constant SLIPPAGE_MULTIPLIER = MAX_BIPS - 1_00; // 1%

    uint32 public constant SECONDS_AGO = 2 hours;

    IERC20 public immutable SALE_TOKEN;
    IERC20 public immutable USDC_TOKEN;
    IERC20 public immutable USDT_TOKEN;
    IWETH public immutable WETH_TOKEN;
    IUniswapV3Factory public immutable FACTORY_V3;
    ISwapRouter public immutable SWAP_ROUTER;

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
        address _factoryV3,
        address _swapRouter,
        address _owner
    ) Ownable(_owner) {
        if (!_isContract(_saleToken)) revert IsNotContract(_saleToken);
        if (!_isContract(_factoryV3)) revert IsNotContract(_factoryV3);
        if (!_isContract(_swapRouter)) revert IsNotContract(_swapRouter);

        FACTORY_V3 = IUniswapV3Factory(_factoryV3);
    
        if (FACTORY_V3.getPool(_usdtToken, _usdcToken, DEFAULT_POOL_FEE) == address(0)) revert PoolForUSDTNotFound();
        if (FACTORY_V3.getPool(_wethToken, _usdcToken, DEFAULT_POOL_FEE) == address(0)) revert PoolForWETHNotFound();

        SALE_TOKEN = IERC20(_saleToken);
        USDC_TOKEN = IERC20(_usdcToken);
        USDT_TOKEN = IERC20(_usdtToken);
        WETH_TOKEN = IWETH(_wethToken);
        SWAP_ROUTER = ISwapRouter(_swapRouter);
        SALE_TOKEN_PRECISION = 10 ** IERC20Metadata(_saleToken).decimals();
    }

    modifier roundExists(uint256 _roundId) {
        if (_roundId == 0 || _roundId > rounds.length) revert InvalidRoundId();
        _;
    }
    
    modifier paymentTokenIsAllowed(address _paymentToken) {
        if (_paymentToken != address(WETH_TOKEN) && _paymentToken != address(USDC_TOKEN) && _paymentToken != address(USDT_TOKEN)) revert InvalidPaymentToken();
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

    // transactionTimeout & poolFee are optional parameters, it can be set to 0 then default values will be used
    function buyTokens(
        uint256 _roundId,
        uint256 _amount,
        uint256 _transactionTimeout,
        uint24 _poolFee,
        address _paymentToken
    )
        external
        payable
        whenNotPaused
        roundExists(_roundId)
        paymentTokenIsAllowed(_paymentToken)
    {
        Round memory round = roundsById[_roundId];
        if (_amount == 0) revert NoTokensToBuy();
        if (block.timestamp < round.startTime || block.timestamp > round.endTime) revert RoundNotActive();
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

            _swap(_paymentToken, paymentAmount, _transactionTimeout, _poolFee);
        } else if (_paymentToken == address(USDT_TOKEN)) {
            if (msg.value != 0) revert EthNotAllowedForErc20Purchase();
            _swap(_paymentToken, paymentAmount, _transactionTimeout, _poolFee);
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
        return _tokenAmount * price / SALE_TOKEN_PRECISION;
    }

    function getTokensForStable(uint256 _roundId, uint256 _stableAmount) public view roundExists(_roundId) returns (uint256) {
        uint256 price = roundsById[_roundId].price;
        return _stableAmount * SALE_TOKEN_PRECISION / price;
    }

    function getNativeForTokens(uint256 _roundId, uint256 _tokenAmount) public view roundExists(_roundId) returns (uint256) {
        uint256 stableAmount = getStableForTokens(_roundId, _tokenAmount);
        return getAmountOut(stableAmount, DEFAULT_POOL_FEE, address(USDT_TOKEN), address(WETH_TOKEN));
    }

    function getTokensForNative(uint256 _roundId, uint256 _nativeAmount) public view roundExists(_roundId) returns (uint256) {
        uint256 stableAmount = getAmountOut(_nativeAmount, DEFAULT_POOL_FEE, address(WETH_TOKEN), address(USDT_TOKEN));
        return getTokensForStable(_roundId, stableAmount);
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

    function getAmountOut(uint256 _amountIn, uint24 _fee, address _tokenIn, address _tokenOut) public view returns (uint256 amountOut) {
        uint24 fee = _fee != 0 ? _fee : DEFAULT_POOL_FEE;
        address pool = FACTORY_V3.getPool(_tokenIn, _tokenOut, fee);

        int24 tick = OracleLibrary.consult(pool, SECONDS_AGO);
        amountOut = OracleLibrary.getQuoteAtTick(tick, uint128(_amountIn), _tokenIn, _tokenOut);
    }

    function _swap(address _tokenIn, uint256 _amountIn, uint256 _transactionTimeout, uint24 _fee) private returns (uint256 amountOut) {
        uint256 transactionTimeout = _transactionTimeout != 0 ? _transactionTimeout : DEFAULT_TRANSACTION_TIMEOUT;
        uint24 fee = _fee != 0 ? _fee : DEFAULT_POOL_FEE;

        uint256 amountOutMinimum = getAmountOut(_amountIn, fee, _tokenIn, address(USDC_TOKEN)) * SLIPPAGE_MULTIPLIER / MAX_BIPS;

        IERC20(_tokenIn).approve(address(SWAP_ROUTER), _amountIn);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: _tokenIn,
            tokenOut: address(USDT_TOKEN),
            fee: fee,
            recipient: address(this),
            deadline: block.timestamp + transactionTimeout,
            amountIn: _amountIn,
            amountOutMinimum: amountOutMinimum,
            sqrtPriceLimitX96: 0
        });

        amountOut = SWAP_ROUTER.exactInputSingle(params);
    }

    function _isContract(address _address) private view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_address)
        }
        return (size > 0);
    }
}