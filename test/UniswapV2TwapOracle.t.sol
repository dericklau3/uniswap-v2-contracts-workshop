// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";

import {UniswapV2TwapOracle} from "./UniswapV2TwapOracle.sol";

interface IMainnetUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

contract UniswapV2TwapOracleTest is Test {
    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    UniswapV2TwapOracle internal oracle;
    address internal wethUsdtPair;
    address internal wbtcUsdtPair;

    function setUp() public {
        vm.createSelectFork("mainnet", 25199290);

        oracle = new UniswapV2TwapOracle(USDT);
        wethUsdtPair = IMainnetUniswapV2Factory(UNISWAP_V2_FACTORY).getPair(WETH, USDT);
        wbtcUsdtPair = IMainnetUniswapV2Factory(UNISWAP_V2_FACTORY).getPair(WBTC, USDT);

        require(wethUsdtPair != address(0), "WETH/USDT pair not found");
        require(wbtcUsdtPair != address(0), "WBTC/USDT pair not found");

        oracle.setPair(WETH, wethUsdtPair);
        oracle.setPair(WBTC, wbtcUsdtPair);
    }

    function testDisplaysEthUsdtTwapFromUniswapV2Pair() public {
        _assertAndPrintTwap("ETH-USDT", WETH, wethUsdtPair, 100e18, 50_000e18);
    }

    function testDisplaysWbtcUsdtTwapFromUniswapV2Pair() public {
        _assertAndPrintTwap("WBTC-USDT", WBTC, wbtcUsdtPair, 1_000e18, 1_000_000e18);
    }

    function _assertAndPrintTwap(
        string memory label,
        address token,
        address pair,
        uint256 minHumanPriceE18,
        uint256 maxHumanPriceE18
    ) internal {
        (uint256 spotBeforeUpdateRaw, uint256 initialOraclePriceRaw) = oracle.getRealtimeAndTwapPrice(token);

        vm.warp(block.timestamp + oracle.PERIOD() + 1);
        oracle.update(token);

        (uint256 spotAfterUpdateRaw, uint256 twapRaw) = oracle.getRealtimeAndTwapPrice(token);
        uint256 getPriceRaw = oracle.getPrice(token);

        console2.log(label);
        console2.log("pair:");
        console2.log(pair);
        console2.log("initial oracle price, USDT per token scaled by 1e18:");
        console2.log(initialOraclePriceRaw);
        console2.log("spot before update, USDT per token scaled by 1e18:");
        console2.log(spotBeforeUpdateRaw);
        console2.log("twap after 12h, USDT per token scaled by 1e18:");
        console2.log(twapRaw);
        console2.log("twap displayed as whole USDT per token:");
        console2.log(twapRaw / 1e18);

        assertEq(getPriceRaw, twapRaw);
        assertGt(twapRaw, 0);
        assertApproxEqRel(twapRaw, spotAfterUpdateRaw, 1e12);
        assertGt(twapRaw, minHumanPriceE18);
        assertLt(twapRaw, maxHumanPriceE18);
    }
}
