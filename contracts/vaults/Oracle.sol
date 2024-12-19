// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {OracleLibrary} from '../libraries/OracleLibrary.sol';
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IOracle} from "../interfaces/vaults/IOracle.sol";

contract Oracle is AccessControl, IOracle {
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    IUniswapV3Factory public immutable FACTORY_V3;
    address public immutable GOIL_TOKEN;

    address public purchaseToken;
    address public pool;

    uint32 public secondsAgo = 30 minutes;

    constructor(address _goilToken, address _purchaseToken, uint24 _poolFee, address _factoryV3, address _admin) {
        if (_isContract(_purchaseToken)) revert PurchaseTokenMustBeContract();
        if (_isContract(_goilToken)) revert GoilTokenMustBeContract();
        if (_isContract(_factoryV3)) revert UniswapFactoryMustBeContract();

        FACTORY_V3 = IUniswapV3Factory(_factoryV3);

        pool = FACTORY_V3.getPool(_purchaseToken, _goilToken, _poolFee);
        if (pool == address(0)) revert PoolDoesNotExist();

        purchaseToken = _purchaseToken;
        GOIL_TOKEN = _goilToken;

        _grantRole(MANAGER_ROLE, _admin);
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    function getPricePerToken() external view returns (uint256) {
        uint256 oneToken = 10 ** IERC20Metadata(GOIL_TOKEN).decimals();

        int24 tick = OracleLibrary.consult(pool, secondsAgo);
        uint256 price = OracleLibrary.getQuoteAtTick(tick, uint128(oneToken), GOIL_TOKEN, purchaseToken);

        return price;
    }

    function getPaymentAmountForTokens(uint256 _tokenAmount) external view returns (uint256) {
        int24 tick = OracleLibrary.consult(pool, secondsAgo);
        uint256 price = OracleLibrary.getQuoteAtTick(tick, uint128(_tokenAmount), GOIL_TOKEN, purchaseToken);
        
        return price;
    }

    function getTokenAmountForPayment(uint256 _paymentAmount) external view returns (uint256) {
        int24 tick = OracleLibrary.consult(pool, secondsAgo);
        uint256 amount = OracleLibrary.getQuoteAtTick(tick, uint128(_paymentAmount), purchaseToken, GOIL_TOKEN);

        return amount;
    }

    function setSecondsAgo(uint32 _secondsAgo) external onlyRole(MANAGER_ROLE) {
        if (_secondsAgo == 0) revert ZeroSecondsAgo();
        if (_secondsAgo == secondsAgo) revert SecondsCannotBeTheSame();
        secondsAgo = _secondsAgo;

        emit SecondsAgoUpdated(_secondsAgo);
    }

    function setPoolForTrackingPrice(address _purchaseToken, uint24 _poolFee) external onlyRole(MANAGER_ROLE) {
        address newPool = FACTORY_V3.getPool(_purchaseToken, GOIL_TOKEN, _poolFee);
        if (newPool == address(0)) revert PoolDoesNotExist();
        if (newPool == pool) revert PoolCannotBeTheSame();
        
        pool = newPool;
        purchaseToken = _purchaseToken;

        emit PurchaseTokenUpdated(_purchaseToken);
    }


    function _isContract(address _address) private view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_address)
        }
        return (size > 0);
    }
}