// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {Errors} from "./lib/Errors.sol";

/// @title Uniswap V2 TWAP 价格预言机
/// @notice 为配置过的 token 返回以 QUOTE_TOKEN 计价、1e18 精度的价格。
/// @dev 首次设置 pair 时会先记录当前现价，后续可按 `PERIOD` 更新为 12 小时 TWAP。
contract UniswapV2TwapOracle is IPriceOracle, Ownable {
    uint256 private constant PRICE_PRECISION = 1e18;
    uint256 private constant Q112 = 2 ** 112;
    uint256 public constant PERIOD = 12 hours;

    /// @notice 单个 token 的 TWAP 观测状态。
    /// @param pair token/QUOTE_TOKEN 的 Uniswap V2 pair 地址。
    /// @param priceCumulativeLast 上次更新时记录的目标累计价格。
    /// @param blockTimestampLast 上次更新时的 pair 时间戳。
    /// @param priceAverage 最近一次记录的价格，初始化为当前现价，后续更新为 TWAP，按 1e18 精度表示。
    /// @param tokenIsToken0 token 是否为 pair 的 token0，用于选择 price0 或 price1 累计值。
    struct Observation {
        address pair;
        uint256 priceCumulativeLast;
        uint32 blockTimestampLast;
        uint256 priceAverage;
        bool tokenIsToken0;
    }

    address public immutable QUOTE_TOKEN;

    mapping(address token => Observation observation) public observations;

    /// @notice token 的 TWAP pair 被设置或重置后触发。
    /// @param token 被配置价格源的 token。
    /// @param pair token/QUOTE_TOKEN 的 Uniswap V2 pair。
    /// @param tokenIsToken0 token 是否为 pair 的 token0。
    event PairSet(address indexed token, address indexed pair, bool tokenIsToken0);
    /// @notice token 的 TWAP 价格更新成功后触发。
    /// @param token 被更新价格的 token。
    /// @param priceAverage 以 QUOTE_TOKEN 计价的平均价格，按 1e18 精度表示。
    /// @param blockTimestamp 本次更新采用的区块时间戳，截断为 uint32。
    event PriceUpdated(address indexed token, uint256 priceAverage, uint32 blockTimestamp);

    /// @notice 部署 TWAP 预言机。
    /// @param quoteToken_ 所有价格使用的计价 token 地址。
    constructor(address quoteToken_) Ownable(msg.sender) {
        require(quoteToken_ != address(0), Errors.ZeroAddress());

        QUOTE_TOKEN = quoteToken_;
    }

    /// @notice 为 token 设置或重置 Uniswap V2 pair。
    /// @dev pair 必须恰好由 `token` 和 `QUOTE_TOKEN` 组成；设置后会立即记录当前现价，后续需等待至少 `PERIOD` 才能更新 TWAP。
    /// @param token 要配置价格源的 token。
    /// @param pair token/QUOTE_TOKEN 的 Uniswap V2 pair。
    function setPair(address token, address pair) external onlyOwner {
        require(token != address(0) && pair != address(0), Errors.ZeroAddress());
        require(token != QUOTE_TOKEN, Errors.InvalidParameter());

        address token0 = IUniswapV2Pair(pair).token0();
        address token1 = IUniswapV2Pair(pair).token1();
        bool tokenIsToken0;
        if (token0 == token && token1 == QUOTE_TOKEN) {
            tokenIsToken0 = true;
        } else if (token1 == token && token0 == QUOTE_TOKEN) {
            tokenIsToken0 = false;
        } else {
            revert Errors.InvalidParameter();
        }

        (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) = _currentCumulativePrices(pair);

        observations[token] = Observation({
            pair: pair,
            priceCumulativeLast: tokenIsToken0 ? price0Cumulative : price1Cumulative,
            blockTimestampLast: blockTimestamp,
            priceAverage: _currentSpotPrice(pair, tokenIsToken0),
            tokenIsToken0: tokenIsToken0
        });

        emit PairSet(token, pair, tokenIsToken0);
    }

    /// @notice 更新 token 的 TWAP 价格。
    /// @dev 距离上次观测必须至少经过 `PERIOD`；任何账号都可触发更新。
    /// @param token 要更新价格的 token。
    function update(address token) external {
        require(_update(token, true), Errors.InvalidParameter());
    }

    /// @notice 如果距离上次观测已满 `PERIOD`，则更新 token 的 TWAP 价格。
    /// @dev 未满 `PERIOD` 时不回退并返回 false；未配置 token 仍会回退。
    /// @param token 要尝试更新价格的 token。
    /// @return updated 本次是否实际更新了 TWAP 观测。
    function tryUpdate(address token) external returns (bool updated) {
        return _update(token, false);
    }

    /// @dev 共享 TWAP 更新逻辑；`revertIfTooEarly` 为 true 时保持 `update` 的严格行为。
    function _update(address token, bool revertIfTooEarly) internal returns (bool updated) {
        Observation storage observation = observations[token];
        require(observation.pair != address(0), Errors.InvalidParameter());

        (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) =
            _currentCumulativePrices(observation.pair);

        uint32 timeElapsed;
        unchecked {
            timeElapsed = blockTimestamp - observation.blockTimestampLast;
        }
        if (timeElapsed < PERIOD) {
            require(!revertIfTooEarly, Errors.InvalidParameter());
            return false;
        }

        uint256 priceCumulative = observation.tokenIsToken0 ? price0Cumulative : price1Cumulative;
        uint256 priceCumulativeDelta;
        unchecked {
            priceCumulativeDelta = priceCumulative - observation.priceCumulativeLast;
        }

        uint256 priceAverageUq112 = priceCumulativeDelta / timeElapsed;
        observation.priceAverage = Math.mulDiv(priceAverageUq112, PRICE_PRECISION, Q112);
        observation.priceCumulativeLast = priceCumulative;
        observation.blockTimestampLast = blockTimestamp;

        require(observation.priceAverage > 0, Errors.InvalidParameter());
        emit PriceUpdated(token, observation.priceAverage, blockTimestamp);
        return true;
    }

    /// @notice 读取 token 最近一次成功更新的 TWAP 价格。
    /// @param token 要查询价格的 token。
    /// @return priceAverage 以 QUOTE_TOKEN 计价的平均价格，按 1e18 精度表示。
    function getPrice(address token) external view returns (uint256) {
        uint256 priceAverage = observations[token].priceAverage;
        require(priceAverage > 0, Errors.InvalidParameter());
        return priceAverage;
    }

    /// @dev 基于 pair 当前储备计算 token 相对 QUOTE_TOKEN 的现价，按 1e18 精度表示。
    /// @param pair token/QUOTE_TOKEN 的 Uniswap V2 pair。
    /// @param tokenIsToken0 token 是否为 pair 的 token0。
    /// @return 以 QUOTE_TOKEN 计价的现价，按 1e18 精度表示。
    function _currentSpotPrice(address pair, bool tokenIsToken0) internal view returns (uint256) {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        require(reserve0 > 0 && reserve1 > 0, Errors.InvalidParameter());

        if (tokenIsToken0) {
            return Math.mulDiv(uint256(reserve1), PRICE_PRECISION, reserve0);
        }

        return Math.mulDiv(uint256(reserve0), PRICE_PRECISION, reserve1);
    }

    /// @dev 读取 pair 当前累计价格；若 pair 时间戳早于当前区块，则用当前储备补算到当前时间。
    /// @param pair Uniswap V2 pair 地址。
    /// @return price0Cumulative token0 的当前累计价格。
    /// @return price1Cumulative token1 的当前累计价格。
    /// @return blockTimestamp 当前区块时间戳，截断为 uint32。
    function _currentCumulativePrices(address pair)
        internal
        view
        returns (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp)
    {
        blockTimestamp = uint32(block.timestamp);
        price0Cumulative = IUniswapV2Pair(pair).price0CumulativeLast();
        price1Cumulative = IUniswapV2Pair(pair).price1CumulativeLast();

        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = IUniswapV2Pair(pair).getReserves();
        require(reserve0 > 0 && reserve1 > 0, Errors.InvalidParameter());

        if (blockTimestampLast != blockTimestamp) {
            uint32 timeElapsed;
            unchecked {
                timeElapsed = blockTimestamp - blockTimestampLast;
                price0Cumulative += Math.mulDiv(uint256(reserve1) * Q112, timeElapsed, reserve0);
                price1Cumulative += Math.mulDiv(uint256(reserve0) * Q112, timeElapsed, reserve1);
            }
        }
    }

    function getRealtimeAndTwapPrice(address token) external view returns (uint256 realtimePrice, uint256 twapPrice) {
        Observation storage observation = observations[token];
        require(observation.pair != address(0), Errors.InvalidParameter());

        realtimePrice = _currentSpotPrice(observation.pair, observation.tokenIsToken0);
        twapPrice = observation.priceAverage;
    }
}
