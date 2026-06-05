// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IUniswapV2Callee} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Callee.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

import {Errors} from "./lib/Errors.sol";

/// @title Uniswap V2 Flashloan 模板
/// @notice 处理 Uniswap V2 flash swap 的借款、回调校验和还款；中间获利逻辑留给 `_executeFlashloan` 扩展。
contract UniswapV2Flashloan is IUniswapV2Callee {
    using SafeERC20 for IERC20;

    struct FlashloanContext {
        address pair;
        address initiator;
    }

    address public immutable PROFIT_RECIPIENT;

    FlashloanContext private context;

    /// @notice 部署 flashloan 模板。
    /// @param profitRecipient_ flashloan 结束后接收盈利 token 的地址。
    constructor(address profitRecipient_) {
        require(profitRecipient_ != address(0), Errors.ZeroAddress());
        PROFIT_RECIPIENT = profitRecipient_;
    }

    /// @notice 发起 Uniswap V2 flash swap。
    /// @dev `token` 必须是 pair 的 token0 或 token1；合约需要在回调结束前持有足够 token 偿还本金和手续费。
    /// @param pair Uniswap V2 pair 地址。
    /// @param token 要借出的 token 地址。
    /// @param tokenAmount 要借出的 token 数量。
    function startFlashloan(address pair, address token, uint256 tokenAmount) external {
        require(pair != address(0), Errors.ZeroAddress());
        require(token != address(0), Errors.ZeroAddress());
        require(tokenAmount > 0, Errors.InvalidFlashloanAmount());
        require(context.pair == address(0), Errors.FlashloanInProgress());

        address token0 = IUniswapV2Pair(pair).token0();
        address token1 = IUniswapV2Pair(pair).token1();
        require(token == token0 || token == token1, Errors.InvalidParameter());

        uint256 amount0Out;
        uint256 amount1Out;
        if (token == token0) {
            amount0Out = tokenAmount;
        } else {
            amount1Out = tokenAmount;
        }

        context = FlashloanContext({pair: pair, initiator: msg.sender});
        IUniswapV2Pair(pair).swap(amount0Out, amount1Out, address(this), abi.encode(token, tokenAmount));
        delete context;
    }

    /// @notice Uniswap V2 pair 在 flash swap 中调用的回调。
    /// @dev 只接受本合约通过 `startFlashloan` 发起的当前 pair 回调。
    /// @param sender pair 记录的 swap 调用者，必须是本合约。
    /// @param amount0 借出的 token0 数量。
    /// @param amount1 借出的 token1 数量。
    /// @param data `abi.encode(address token, uint256 tokenAmount)` 编码的自定义参数示例。
    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external override {
        FlashloanContext memory currentContext = context;
        require(msg.sender == currentContext.pair && sender == address(this), Errors.UnexpectedCallback());
        require(data.length > 0, Errors.InvalidParameter());
        require((amount0 > 0 && amount1 == 0) || (amount0 == 0 && amount1 > 0), Errors.InvalidFlashloanAmount());

        (address token, uint256 tokenAmount) = abi.decode(data, (address, uint256));
        address token0 = IUniswapV2Pair(msg.sender).token0();
        address token1 = IUniswapV2Pair(msg.sender).token1();
        require(token == token0 || token == token1, Errors.InvalidParameter());
        require(
            (token == token0 && amount0 == tokenAmount) || (token == token1 && amount1 == tokenAmount),
            Errors.InvalidFlashloanAmount()
        );

        uint256 repayment = getRepaymentAmount(tokenAmount);
        uint256 fee = repayment - tokenAmount;

        _executeFlashloan(msg.sender, token, tokenAmount, fee, currentContext.initiator);

        require(IERC20(token).balanceOf(address(this)) >= repayment, Errors.InsufficientRepaymentBalance());
        IERC20(token).safeTransfer(msg.sender, repayment);

        uint256 profit = IERC20(token).balanceOf(address(this));
        if (profit > 0) {
            IERC20(token).safeTransfer(PROFIT_RECIPIENT, profit);
        }
    }

    /// @notice 计算单 token 闪电贷需要归还的数量。
    /// @dev Uniswap V2 对输入数量收 0.3% fee，同币种借还时需要满足 `repayment * 997 >= amount * 1000`。
    /// @param amount 借出的 token 数量。
    /// @return repayment 需要转回 pair 的本金加手续费。
    function getRepaymentAmount(uint256 amount) public pure returns (uint256 repayment) {
        require(amount > 0, Errors.InvalidFlashloanAmount());
        return Math.ceilDiv(amount * 1000, 997);
    }

    /// @dev 自定义获利逻辑入口。默认留空；后续可在这里做套利、清算、跨协议操作等。
    function _executeFlashloan(
        address pair,
        address token,
        uint256 tokenAmount,
        uint256 fee,
        address initiator
    ) internal virtual {}
}
