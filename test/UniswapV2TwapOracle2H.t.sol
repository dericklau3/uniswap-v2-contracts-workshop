// SPDX-License-Identifier: MIT
pragma solidity =0.6.6;

import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "../lib/forge-std/lib/ds-test/src/test.sol";

import {ERC20 as TestERC20} from "../contracts/v2-periphery/test/ERC20.sol";
import {IUniswapV2Router02} from "../contracts/v2-periphery/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "../contracts/v2-core/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "../contracts/v2-core/interfaces/IUniswapV2Pair.sol";
import {UniswapV2TwapOracle2H} from "../contracts/UniswapV2TwapOracle2H.sol";

contract UniswapV2TwapOracle2HTest is DSTest {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    IUniswapV2Router02 router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    address account = address(0xA11CE);
    address keeper = address(0xB0B);

    TestERC20 tokenA;
    TestERC20 tokenB;
    IUniswapV2Pair pair;
    UniswapV2TwapOracle2H oracle;

    function setUp() public {
        vm.createSelectFork("mainnet", 24361930);

        tokenA = new TestERC20(1000000000 ether);
        tokenB = new TestERC20(1000000000 ether);

        tokenA.transfer(account, 1000000 ether);
        tokenB.transfer(account, 1000000 ether);
        vm.deal(account, 10 ether);

        vm.startPrank(account);
        _addLiquidityTokenToken();
        vm.stopPrank();

        address pairAddress = IUniswapV2Factory(router.factory()).getPair(address(tokenA), address(tokenB));
        require(pairAddress != address(0), "pair-not-found");
        pair = IUniswapV2Pair(pairAddress);

        oracle = new UniswapV2TwapOracle2H(pairAddress);
    }

    // 验证刚部署时未预热，consult 会回退
    // function testConsultBeforeUpdateRevert() public {
    //     _expectRevertReason("TWAP: NOT_READY");
    //     oracle.consult(address(tokenA));
    // }

    // // 验证 2 小时未到时 update 会回退
    // function testUpdateBeforePeriodRevert() public {
    //     _expectRevertReason("TWAP: PERIOD_NOT_ELAPSED");
    //     oracle.update();
    // }

    // // 验证任何地址都可以更新（可用性优先）
    // function testAnyAddressCanUpdateAfterPeriod() public {
    //     vm.warp(block.timestamp + uint256(oracle.PERIOD()) + 1);

    //     vm.prank(keeper);
    //     oracle.update();

    //     assertTrue(oracle.isConsultable());
    // }

    // 验证 consult 返回统一 1e18 精度价格
    // function testConsultReturnsPriceE18() public {
    //     vm.warp(block.timestamp + uint256(oracle.PERIOD()) + 1);
    //     oracle.update();

    //     uint256 priceAE18 = oracle.consult(address(tokenA)); // 1 tokenA = ? tokenB (1e18)
    //     uint256 priceBE18 = oracle.consult(address(tokenB)); // 1 tokenB = ? tokenA (1e18)

    //     console.log(priceAE18);
    //     console.log(priceBE18);

    //     (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
    //     address pairToken0 = pair.token0();

    //     uint256 reserveA = address(tokenA) == pairToken0 ? reserve0 : reserve1;
    //     uint256 reserveB = address(tokenA) == pairToken0 ? reserve1 : reserve0;

    //     uint256 expectedPriceAE18 = (reserveB * 1e18) / reserveA;
    //     uint256 expectedPriceBE18 = (reserveA * 1e18) / reserveB;

    //     _assertApproxEqAbs(priceAE18, expectedPriceAE18, 1e8);
    //     _assertApproxEqAbs(priceBE18, expectedPriceBE18, 1e12);
    // }

    // 验证两个时间段内多次交易后，TWAP 能反映各自时间段的加权平均价格
    function testTwoPeriodsMultipleSwapsAndPrintTwap() public {
        uint256 period = uint256(oracle.PERIOD());

        // ===== 第一个时间段：多次 B -> A，整体倾向抬高 A 价格 =====
        uint256 t0 = block.timestamp;
        vm.warp(t0 + 15 minutes);
        _swapExact(address(tokenB), address(tokenA), 0.05 ether);
        vm.warp(t0 + 45 minutes);
        _swapExact(address(tokenB), address(tokenA), 0.05 ether);
        vm.warp(t0 + 90 minutes);
        _swapExact(address(tokenB), address(tokenA), 0.05 ether);

        vm.warp(t0 + period + 1);
        oracle.update();
        uint256 p1AtoB = oracle.consult(address(tokenA)); // 1 tokenA = ? tokenB (1e18)
        uint256 p1BtoA = oracle.consult(address(tokenB)); // 1 tokenB = ? tokenA (1e18)
        uint256 s1AtoB = _spotPriceE18(address(tokenA)); // 实时价格：1 tokenA = ? tokenB (1e18)
        uint256 s1BtoA = _spotPriceE18(address(tokenB)); // 实时价格：1 tokenB = ? tokenA (1e18)

        console.log("period1 price tokenA->tokenB (1e18):");
        console.log(p1AtoB);
        console.log("period1 spot  tokenA->tokenB (1e18):");
        console.log(s1AtoB);
        console.log("period1 price tokenB->tokenA (1e18):");
        console.log(p1BtoA);
        console.log("period1 spot  tokenB->tokenA (1e18):");
        console.log(s1BtoA);

        // ===== 第二个时间段：多次 A -> B，整体倾向压低 A 价格 =====
        uint256 t1 = block.timestamp;
        vm.warp(t1 + 15 minutes);
        _swapExact(address(tokenA), address(tokenB), 300 ether);
        vm.warp(t1 + 45 minutes);
        _swapExact(address(tokenA), address(tokenB), 300 ether);
        vm.warp(t1 + 90 minutes);
        _swapExact(address(tokenA), address(tokenB), 300 ether);

        vm.warp(t1 + period + 1);
        oracle.update();
        uint256 p2AtoB = oracle.consult(address(tokenA)); // 1 tokenA = ? tokenB (1e18)
        uint256 p2BtoA = oracle.consult(address(tokenB)); // 1 tokenB = ? tokenA (1e18)
        uint256 s2AtoB = _spotPriceE18(address(tokenA)); // 实时价格：1 tokenA = ? tokenB (1e18)
        uint256 s2BtoA = _spotPriceE18(address(tokenB)); // 实时价格：1 tokenB = ? tokenA (1e18)

        console.log("period2 price tokenA->tokenB (1e18):");
        console.log(p2AtoB);
        console.log("period2 spot  tokenA->tokenB (1e18):");
        console.log(s2AtoB);
        console.log("period2 price tokenB->tokenA (1e18):");
        console.log(p2BtoA);
        console.log("period2 spot  tokenB->tokenA (1e18):");
        console.log(s2BtoA);

        assertTrue(p1AtoB > 0 && p1BtoA > 0);
        assertTrue(p2AtoB > 0 && p2BtoA > 0);
    }

    // 验证超过 2 小时不更新时 consult 会回退（价格过期）
    // function testConsultRevertWhenStale() public {
    //     vm.warp(block.timestamp + uint256(oracle.PERIOD()) + 1);
    //     oracle.update();

    //     vm.warp(block.timestamp + uint256(oracle.PERIOD()) + 1);
    //     _expectRevertReason("TWAP: STALE");
    //     oracle.consult(address(tokenA));
    // }

    function _addLiquidityTokenToken() internal {
        uint256 amountADesired = 4000 ether;
        uint256 amountBDesired = 1 ether;

        tokenA.approve(address(router), uint256(-1));
        tokenB.approve(address(router), uint256(-1));
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

    function _expectRevertReason(string memory reason) internal {
        vm.expectRevert(abi.encodeWithSignature("Error(string)", reason));
    }

    function _assertApproxEqAbs(uint256 a, uint256 b, uint256 maxDelta) internal {
        uint256 delta = a > b ? a - b : b - a;
        require(delta <= maxDelta, "assert-approx-eq-abs");
    }

    function _swapExact(address tokenIn, address tokenOut, uint256 amountIn) internal {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        vm.prank(account);
        router.swapExactTokensForTokens(
            amountIn,
            0,
            path,
            account,
            _deadline()
        );
    }

    function _spotPriceE18(address tokenIn) internal view returns (uint256 priceE18) {
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        address pairToken0 = pair.token0();

        uint256 reserveA = address(tokenA) == pairToken0 ? reserve0 : reserve1;
        uint256 reserveB = address(tokenA) == pairToken0 ? reserve1 : reserve0;

        if (tokenIn == address(tokenA)) {
            return (reserveB * 1e18) / reserveA; // 1 tokenA = ? tokenB
        }
        require(tokenIn == address(tokenB), "invalid-token-in");
        return (reserveA * 1e18) / reserveB; // 1 tokenB = ? tokenA
    }

    function _deadline() internal view returns (uint256) {
        return block.timestamp + 1800;
    }
}
