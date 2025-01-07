// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import {IUniswapV2Router01} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IQuoterV2} from "@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";

import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IScoring} from "../interfaces/vaults/IScoring.sol";
import {IVault} from "../interfaces/vaults/IVault.sol";
import {IStaking} from "../interfaces/vaults/IStaking.sol";

contract Vault is Initializable, ERC4626Upgradeable, OwnableUpgradeable, IVault {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint256 public constant MAX_BIPS = 100_00;
    uint256 public constant STAKING_PERCENTAGE = 1_00; // 1%

    uint256 public constant SLIPPAGE_MULTIPLIER = MAX_BIPS - 2_00; // slippage == 2%
    uint256 public constant TRANSACTION_TIMEOUT = 15 minutes;

    IUniswapV2Router01 public ROUTER_V2;
    ISwapRouter public ROUTER_V3;
    IQuoterV2 public QUOTER;

    IScoring public SCORING;
    IStaking public STAKING;
    IERC20Upgradeable public GOIL_TOKEN;
    address public TREASURY;

    bool public isVaultSuccess;
    bool public isVaultLiquidated;

    uint256 public goilRate;
    uint256 public desiredCap;
    uint256 public promisedCap;
    uint256 public startTime;
    uint256 public fundingEndTime;
    uint256 public unlockEndTime;
    uint256 public totalDeposits;

    function initialize(
        address _entity,
        address _scoring,
        address _treasury,
        address _staking,
        address _goilToken,
        address _depositToken,
        address _routerV2,
        address _routerV3,
        address _quoter,
        uint256 _desiredCap,
        uint256 _promisedCap,
        uint256 _startTime,
        uint256 _fundingEndTime,
        uint256 _unlockEndTime
    ) external initializer {
        __ERC4626_init(IERC20Upgradeable(_depositToken));
        __Ownable_init();
        transferOwnership(_entity);

        SCORING = IScoring(_scoring);
        STAKING = IStaking(_staking);
        GOIL_TOKEN = IERC20Upgradeable(_goilToken);
        TREASURY = _treasury;
        ROUTER_V2 = IUniswapV2Router01(_routerV2);
        ROUTER_V3 = ISwapRouter(_routerV3);
        QUOTER = IQuoterV2(_quoter);
        desiredCap = _desiredCap;
        promisedCap = _promisedCap;
        startTime = _startTime;
        fundingEndTime = _fundingEndTime;
        unlockEndTime = _unlockEndTime;
    }

    function deposit(uint256 _amountToDeposit) public returns (uint256) {
        return deposit(_amountToDeposit, msg.sender);
    }

    function withdraw(uint256 _amountToWithdraw) public returns (uint256) {
        return withdraw(_amountToWithdraw, msg.sender, msg.sender);
    }

    function deposit(uint256 _amountToDeposit, address _receiverShares) public override returns (uint256) {
        uint256 currentTime = block.timestamp;

        if (currentTime < startTime) revert VaultNotStarted();
        if (currentTime > fundingEndTime) revert VaultFundingTimeIsEnded();
        if (totalAssets() + _amountToDeposit > desiredCap) revert ExceedsVaultSize();

        return super.deposit(_amountToDeposit, _receiverShares);
    }

    function withdraw(uint256 _amountToWithdraw, address _receiver, address _holderShares) public override returns (uint256) {
        uint256 currentTime = block.timestamp;
        bool isNotRaisedDesiredCap = currentTime < unlockEndTime && currentTime > fundingEndTime && totalAssets() < desiredCap;

        if (isNotRaisedDesiredCap) {
            return super.withdraw(_amountToWithdraw, _receiver, _holderShares);
        }

        if (currentTime < unlockEndTime) revert VaultIsNotUnlocked();
        
        if (isLiquidatable()) {
            isVaultLiquidated = true;
        
            //! _tryGetAssetDecimals, _asset and _underlyingDecimals in ERC4626Upgradeable must be internal for this case
            (bool success, uint8 assetDecimals) = _tryGetAssetDecimals(GOIL_TOKEN);
            _underlyingDecimals = success ? assetDecimals : 18;
            _asset = GOIL_TOKEN;

            SCORING.updateEntityScore();
        }

        return super.withdraw(_amountToWithdraw, _receiver, _holderShares);
    }

    function depositFromEntity() external onlyOwner {
        uint256 currentTime = block.timestamp;

        if (currentTime <= fundingEndTime) revert FundingEndTimeIsNotReached();
        
        uint256 stakingAmount = (desiredCap * STAKING_PERCENTAGE) / MAX_BIPS;
        IERC20Upgradeable(asset()).safeTransferFrom(msg.sender, address(this), promisedCap);

        if (currentTime <= unlockEndTime) isVaultSuccess = true;

        if (isVaultSuccess) {
            SCORING.updateEntityScore();

            uint256 stakingAmountInGoil = _swap(stakingAmount, address(this));
            GOIL_TOKEN.approve(address(STAKING), stakingAmountInGoil);
            STAKING.transferReward(stakingAmountInGoil);
        } else {
            _swap(promisedCap, address(TREASURY));
        }

        unlockEndTime = currentTime;
        emit DepositFromEntity(promisedCap);
    }

    function withdrawToEntity() external onlyOwner {
        uint256 currentTime = block.timestamp;

        if (currentTime <= fundingEndTime) revert FundingEndTimeIsNotReached();
        if (currentTime >= unlockEndTime) revert VaultIsUnlocked();
        if (totalAssets() < desiredCap) revert InsufficientBalance();

        IERC20Upgradeable(asset()).safeTransfer(msg.sender, totalAssets());
        emit WithdrawToEntity(totalAssets());
    }

    function isLiquidatable() public view returns (bool) {
        uint256 currentTime = block.timestamp;

        return !isVaultLiquidated 
            && !isVaultSuccess 
            && currentTime > unlockEndTime 
            && totalAssets() < promisedCap;
    }

    function owner() public view override(IVault, OwnableUpgradeable) returns (address) {
        return super.owner();
    }

    function _swap(uint256 _amountIn, address _recipient) private returns (uint256 amountOut) {
        address tokenOut = address(GOIL_TOKEN);
        address tokenIn = address(asset());
        (Swap decision, uint24 fee, uint256 maxAmount) = _decider(_amountIn, tokenIn, tokenOut);

        if (decision == Swap.V2) {
            address[] memory path = new address[](2);
            path[0] = tokenIn;
            path[1] = tokenOut;

            amountOut = _swapV2(path, _amountIn, maxAmount, _recipient);
        } else {
            amountOut = _swapV3(tokenIn, tokenOut, fee, _amountIn, maxAmount, _recipient);
        }
    }

    function _decider(uint256 _amountIn, address _tokenIn, address _tokenOut) private returns (Swap, uint24, uint256) {
        uint256 amount1 = _getQuote(_tokenIn, _tokenOut, _amountIn, 5_00); //fee 0.05%
        uint256 amount2 = _getQuote(_tokenIn, _tokenOut, _amountIn, 3_000); //fee 0.3%
        uint256 amount3 = _getQuote(_tokenIn, _tokenOut, _amountIn, 10_000); //fee 1%
        uint256 amount4;

        address[] memory path = new address[](2);
        path[0] = _tokenIn;
        path[1] = _tokenOut;

        try ROUTER_V2.getAmountsOut(_amountIn, path) returns (uint256[] memory result) {
            amount4 = result[1];
        } catch {
            amount4 = 0;
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
            decision = Swap.V3_10000;
            fee = 10_000;
        }

        if (amount4 > maxAmount) {
            maxAmount = amount4;
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

    function _swapV2(
        address[] memory _path,
        uint256 _amountIn,
        uint256 _amountOut,
        address _recipient
    ) private returns (uint256 amountOut) {
        uint256 amountOutMin = (_amountOut * SLIPPAGE_MULTIPLIER) / MAX_BIPS;
        uint256 deadline = block.timestamp + TRANSACTION_TIMEOUT;

        IERC20Upgradeable(_path[0]).approve(address(ROUTER_V2), _amountIn);
        uint256[] memory amounts = ROUTER_V2.swapExactTokensForTokens(
            _amountIn,
            amountOutMin,
            _path,
            _recipient,
            deadline
        );

        amountOut = amounts[amounts.length - 1];
    }

    function _swapV3(
        address _tokenIn,
        address _tokenOut,
        uint24 _fee,
        uint256 _amountIn,
        uint256 _amountOut,
        address _recipient
    ) private returns (uint256 amountOut) {
        uint256 amountOutMin = (_amountOut * SLIPPAGE_MULTIPLIER) / MAX_BIPS;
        uint256 deadline = block.timestamp + TRANSACTION_TIMEOUT;

        IERC20Upgradeable(_tokenIn).approve(address(ROUTER_V3), _amountIn);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: _tokenIn,
                tokenOut: _tokenOut,
                fee: _fee,
                recipient: _recipient,
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