// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IUniswapV2Router02} from "../contracts/v2-periphery/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "../contracts/v2-core/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "../contracts/v2-core/interfaces/IUniswapV2Pair.sol";

contract UniswapV2Test is Test {

    IUniswapV2Router02 router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    address account = makeAddr("account");
    MockERC20 tokenA;
    MockERC20 tokenB;

    function setUp() public {
        vm.createSelectFork("mainnet", 24361930);

        tokenA = new MockERC20("Mock Token A", "MTA");
        tokenB = new MockERC20("Mock Token B", "MTB");

        tokenA.mint(account, 1_000_000 ether);
        tokenB.mint(account, 1_000_000 ether);
        vm.deal(account, 10 ether);
    }

    // 验证添加流动性流程可以成功执行（创建/获取池子并铸造LP）
    function testAddLiquidity() public {
        vm.startPrank(account);

        _addLiquidityTokenToken();

        vm.stopPrank();
    }

    // 验证移除流动性时按照比例赎回且满足最小领取数量约束
    function testRemoveLiquidity() public {
        vm.startPrank(account);
        _addLiquidityTokenToken();

        address pair = IUniswapV2Factory(router.factory()).getPair(address(tokenA), address(tokenB)); // router helper: factory address
        require(pair != address(0), "pair-not-found");
        uint256 liquidity = IUniswapV2Pair(pair).balanceOf(account);
        IERC20(pair).approve(address(router), type(uint256).max);

        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        address token0 = IUniswapV2Pair(pair).token0();
        uint256 reserveA = address(tokenA) == token0 ? reserve0 : reserve1;
        uint256 reserveB = address(tokenA) == token0 ? reserve1 : reserve0;
        uint256 totalSupply = IUniswapV2Pair(pair).totalSupply();
        uint256 liquidityToRemove = liquidity / 2;
        uint256 amountAMin = ((liquidityToRemove * reserveA) / totalSupply) * 99 / 100;
        uint256 amountBMin = ((liquidityToRemove * reserveB) / totalSupply) * 99 / 100;

        router.removeLiquidity(
            address(tokenA), // tokenA address in the pair
            address(tokenB), // tokenB address in the pair
            liquidityToRemove, // LP tokens to burn
            amountAMin, // minimum tokenA to receive
            amountBMin, // minimum tokenB to receive
            account, // recipient of withdrawn tokens
            _deadline() // transaction deadline (now + 30 min)
        );

        vm.stopPrank();
    }

    // 验证quote按储备比例给出正确的无滑点兑换报价
    function testQuote() public {
        vm.startPrank(account);
        _addLiquidityTokenToken();

        address pair = IUniswapV2Factory(router.factory()).getPair(address(tokenA), address(tokenB));
        require(pair != address(0), "pair-not-found");

        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        address token0 = IUniswapV2Pair(pair).token0();
        uint256 reserveA = address(tokenA) == token0 ? reserve0 : reserve1;
        uint256 reserveB = address(tokenA) == token0 ? reserve1 : reserve0;

        uint256 amountAIn = 100 ether;
        uint256 amountBQuote = router.quote(amountAIn, reserveA, reserveB);
        uint256 expected = (amountAIn * reserveB) / reserveA;

        assertEq(amountBQuote, expected);
        assertGt(amountBQuote, 0);

        vm.stopPrank();
    }

    // 验证getAmountsOut返回正确路径长度且输出金额为正
    function testGetAmountsOut() public {
        vm.startPrank(account);
        _addLiquidityTokenToken();

        uint256 amountIn = 1_000 ether;
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        uint256[] memory amounts = router.getAmountsOut(amountIn, path);
        assertEq(amounts.length, 2);
        assertEq(amounts[0], amountIn);
        assertGt(amounts[1], 0);

        vm.stopPrank();
    }

    // 验证getAmountsIn返回正确路径长度且输入金额为正
    function testGetAmountsIn() public {
        vm.startPrank(account);
        _addLiquidityTokenToken();

        uint256 amountOut = 0.1 ether;
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        uint256[] memory amounts = router.getAmountsIn(amountOut, path);
        assertEq(amounts.length, 2);
        assertEq(amounts[1], amountOut);
        assertGt(amounts[0], 0);

        vm.stopPrank();
    }

    // 验证精确输入数量兑换能够成功执行且满足最小输出
    function testSwapExactTokensForTokens() public {
        vm.startPrank(account);
        _addLiquidityTokenToken();

        uint256 amountIn = 1_000 ether;
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        uint256 amountOutMin = (router.getAmountsOut(amountIn, path))[path.length - 1] * 99 / 100;
        router.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            account,
            _deadline()
        );

        vm.stopPrank();
    }

    // 验证精确输出数量兑换能够成功执行且不超过最大输入
    function testSwapTokensForExactTokens() public {
        vm.startPrank(account);
        _addLiquidityTokenToken();

        uint256 amountOut = 0.1 ether;
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        uint256 amountInMax = (router.getAmountsIn(amountOut, path))[0] * 101 / 100;
        router.swapTokensForExactTokens(
            amountOut,
            amountInMax,
            path,
            account,
            _deadline()
        );

        vm.stopPrank();
    }

    function _addLiquidityTokenToken() internal {
        uint256 amountADesired = 4_000 ether;
        uint256 amountBDesired = 1 ether;
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
        router.addLiquidity(
            address(tokenA), // tokenA address in the pair
            address(tokenB), // tokenB address in the pair
            amountADesired, // desired amount of tokenA to deposit
            amountBDesired, // desired amount of tokenB to deposit
            (amountADesired * 995) / 1000, // minimum tokenA (1% slippage buffer)
            (amountBDesired * 995) / 1000, // minimum tokenB (1% slippage buffer)
            account, // recipient of LP tokens
            _deadline() // transaction deadline (now + 30 min)
        );
    }

    function _deadline() internal view returns (uint256) {
        return block.timestamp + 1800;
    }
}

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1_000_000_000 ether);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
