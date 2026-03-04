// SPDX-License-Identifier: MIT
pragma solidity =0.6.6;

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/lib/contracts/libraries/FixedPoint.sol";

import "./v2-periphery/libraries/UniswapV2OracleLibrary.sol";

interface IERC20Decimals {
    function decimals() external view returns (uint8);
}

/// @title Uniswap V2 两小时 TWAP 预言机（简化版）
/// @notice 部署时记录一次累计价格与时间戳，之后每 2 小时更新一次平均价。
/// @dev 固定窗口模型，不使用滑窗桶（无 granularity/periodSize）。
contract UniswapV2TwapOracle2H {
    using FixedPoint for *;

    // 固定 TWAP 窗口：2 小时
    uint32 public constant PERIOD = 2 hours;

    IUniswapV2Pair public immutable pair;
    address public immutable token0;
    address public immutable token1;
    uint8 public immutable token0Decimals;
    uint8 public immutable token1Decimals;
    uint256 public immutable token0Unit;
    uint256 public immutable token1Unit;

    // 上一次快照时的累计价格与时间戳
    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint32 public blockTimestampLast;

    // 最近一次成功更新得到的 2 小时平均价格
    FixedPoint.uq112x112 public price0Average;
    FixedPoint.uq112x112 public price1Average;
    bool public hasPrice;

    event OracleUpdated(uint32 timestamp, uint32 timeElapsed, uint256 price0Cumulative, uint256 price1Cumulative);

    /// @param pair_ Uniswap V2 交易对合约地址。
    constructor(address pair_) public {
        require(pair_ != address(0), "TWAP: ZERO_PAIR");

        IUniswapV2Pair pairContract = IUniswapV2Pair(pair_);
        address token0_ = pairContract.token0();
        address token1_ = pairContract.token1();
        require(token0_ != address(0) && token1_ != address(0), "TWAP: BAD_PAIR");
        uint8 token0Decimals_ = _readDecimals(token0_);
        uint8 token1Decimals_ = _readDecimals(token1_);

        pair = pairContract;
        token0 = token0_;
        token1 = token1_;
        token0Decimals = token0Decimals_;
        token1Decimals = token1Decimals_;
        token0Unit = _pow10(token0Decimals_);
        token1Unit = _pow10(token1Decimals_);

        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast_) = pairContract.getReserves();
        require(reserve0 > 0 && reserve1 > 0, "TWAP: NO_RESERVES");

        price0CumulativeLast = pairContract.price0CumulativeLast();
        price1CumulativeLast = pairContract.price1CumulativeLast();
        blockTimestampLast = blockTimestampLast_;
    }

    /// @notice 是否达到可更新条件（距离上次快照至少 2 小时）。
    function canUpdate() external view returns (bool) {
        uint32 elapsed = _currentBlockTimestamp() - blockTimestampLast; // 允许 uint32 回绕（与 Uniswap 设计一致）
        return elapsed >= PERIOD;
    }

    /// @notice 是否已有可用价格（至少成功执行过一次 update）。
    function isConsultable() external view returns (bool) {
        return hasPrice;
    }

    /// @notice 更新 2 小时 TWAP 价格。
    function update() external {
        _requireReserves();

        (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) =
            UniswapV2OracleLibrary.currentCumulativePrices(address(pair));

        uint32 elapsed = blockTimestamp - blockTimestampLast; // 允许 uint32 回绕（与 Uniswap 设计一致）
        require(elapsed >= PERIOD, "TWAP: PERIOD_NOT_ELAPSED");

        // 累计价格单位是 (UQ112x112 * 秒)，除以时间差后得到平均价格（UQ112x112）
        price0Average = FixedPoint.uq112x112(uint224((price0Cumulative - price0CumulativeLast) / elapsed));
        price1Average = FixedPoint.uq112x112(uint224((price1Cumulative - price1CumulativeLast) / elapsed));

        price0CumulativeLast = price0Cumulative;
        price1CumulativeLast = price1Cumulative;
        blockTimestampLast = blockTimestamp;
        hasPrice = true;

        emit OracleUpdated(blockTimestamp, elapsed, price0Cumulative, price1Cumulative);
    }

    /// @notice 查询两小时 TWAP 报价，统一按 1e18 精度返回。
    /// @param tokenIn 只能是 token0 或 token1。
    /// @return priceE18 1 个 tokenIn 对应多少 tokenOut（1e18 精度）。
    function consult(address tokenIn) external view returns (uint256 priceE18) {
        require(hasPrice, "TWAP: NOT_READY");
        _requireReserves();

        // 防止读到过旧价格：要求在一个周期内有更新
        require(_currentBlockTimestamp() - blockTimestampLast <= PERIOD, "TWAP: STALE");

        if (tokenIn == token0) {
            // 先计算 1 个 token0（token0Unit）可兑换的 token1 最小单位数量，再归一化到 1e18 精度
            uint256 amountOut = price0Average.mul(token0Unit).decode144();
            return (amountOut * 1e18) / token1Unit;
        }
        require(tokenIn == token1, "TWAP: INVALID_TOKEN");
        // 先计算 1 个 token1（token1Unit）可兑换的 token0 最小单位数量，再归一化到 1e18 精度
        uint256 amountOut = price1Average.mul(token1Unit).decode144();
        return (amountOut * 1e18) / token0Unit;
    }

    function _requireReserves() internal view {
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        require(reserve0 > 0 && reserve1 > 0, "TWAP: NO_RESERVES");
    }

    function _currentBlockTimestamp() internal view returns (uint32) {
        return uint32(block.timestamp % 2 ** 32);
    }

    function _pow10(uint8 exponent) internal pure returns (uint256) {
        require(exponent <= 77, "TWAP: DECIMALS_TOO_LARGE");
        return 10 ** uint256(exponent);
    }

    function _readDecimals(address token) internal view returns (uint8 d) {
        try IERC20Decimals(token).decimals() returns (uint8 decimals_) {
            require(decimals_ <= 77, "TWAP: DECIMALS_TOO_LARGE");
            return decimals_;
        } catch {
            revert("TWAP: NO_DECIMALS");
        }
    }
}
