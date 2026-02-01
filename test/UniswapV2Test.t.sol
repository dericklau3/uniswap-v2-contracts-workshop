// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
pragma abicoder v2;

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

    function testAddLiquidity() public {
        vm.startPrank(account);

        _addLiquidityTokenToken();

        vm.stopPrank();
    }

    function testSwapEthForToken() public {
        vm.startPrank(account);
        _addLiquidityEthToken();

        address[] memory pathEthToToken = new address[](2);
        pathEthToToken[0] = router.WETH(); // router helper: WETH address
        pathEthToToken[1] = address(tokenA);
        uint256 ethIn = 0.05 ether;
        uint256 amountOutMinEthToToken =
            (router.getAmountsOut(ethIn, pathEthToToken))[pathEthToToken.length - 1] * 99 / 100; // router quote for output amount
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: ethIn}(
            amountOutMinEthToToken, // minimum tokens out (1% slippage buffer)
            pathEthToToken, // swap path: WETH -> tokenA
            account, // recipient of output tokens
            _deadline() // transaction deadline (now + 30 min)
        );

        vm.stopPrank();
    }

    function testSwapTokenForToken() public {
        vm.startPrank(account);
        _addLiquidityTokenToken();

        uint256 amountIn = 1_000 ether;
        address[] memory pathTokenToToken = new address[](2);
        pathTokenToToken[0] = address(tokenA);
        pathTokenToToken[1] = address(tokenB);
        uint256 amountOutMinTokenToToken =
            (router.getAmountsOut(amountIn, pathTokenToToken))[pathTokenToToken.length - 1] * 99 / 100; // router quote for output amount
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, // exact tokenIn amount to swap
            amountOutMinTokenToToken, // minimum tokenOut (1% slippage buffer)
            pathTokenToToken, // swap path: tokenA -> tokenB
            account, // recipient of output tokens
            _deadline() // transaction deadline (now + 30 min)
        );

        vm.stopPrank();
    }

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

    function _addLiquidityEthToken() internal {
        uint256 tokenAForEthPool = 2_000 ether;
        uint256 ethForPool = 1 ether;
        tokenA.approve(address(router), type(uint256).max);
        router.addLiquidityETH{value: ethForPool}(
            address(tokenA), // token paired with ETH (WETH)
            tokenAForEthPool, // desired token amount to deposit
            (tokenAForEthPool * 995) / 1000, // minimum token amount (1% slippage buffer)
            (ethForPool * 995) / 1000, // minimum ETH amount (1% slippage buffer)
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
