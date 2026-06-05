// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

import {UniswapV2Flashloan} from "./UniswapV2Flashloan.sol";
import {Errors} from "./lib/Errors.sol";

contract UniswapV2FlashloanTest is Test {
    address internal constant WETH_USDT_PAIR = 0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852;
    address internal profitRecipient = makeAddr("profitRecipient");

    UniswapV2FlashloanHarness internal flashloan;

    function setUp() public {
        vm.createSelectFork("mainnet", 25_199_290);
        flashloan = new UniswapV2FlashloanHarness(profitRecipient);
    }

    function testStartsFlashloanAndRepaysBorrowedTokenWithFee() public {
        IUniswapV2Pair pair = IUniswapV2Pair(WETH_USDT_PAIR);
        address token0 = pair.token0();
        uint256 amount0Out = 1 ether;
        uint256 repayment = flashloan.getRepaymentAmount(amount0Out);

        deal(token0, address(flashloan), repayment - amount0Out);

        uint256 pairBalanceBefore = IERC20(token0).balanceOf(address(pair));

        flashloan.startFlashloan(address(pair), token0, amount0Out);

        assertEq(IERC20(token0).balanceOf(address(pair)), pairBalanceBefore + repayment - amount0Out);
        assertEq(flashloan.lastPair(), address(pair));
        assertEq(flashloan.lastToken(), token0);
        assertEq(flashloan.lastAmount(), amount0Out);
        assertEq(flashloan.lastFee(), repayment - amount0Out);
        assertEq(flashloan.lastInitiator(), address(this));
    }

    function testTransfersBorrowedTokenProfitToProfitRecipient() public {
        IUniswapV2Pair pair = IUniswapV2Pair(WETH_USDT_PAIR);
        address token0 = pair.token0();
        uint256 amount0Out = 1 ether;
        uint256 repayment = flashloan.getRepaymentAmount(amount0Out);
        uint256 profit = 0.5 ether;

        deal(token0, address(flashloan), repayment - amount0Out + profit);

        uint256 recipientBalanceBefore = IERC20(token0).balanceOf(profitRecipient);

        flashloan.startFlashloan(address(pair), token0, amount0Out);

        assertEq(IERC20(token0).balanceOf(profitRecipient), recipientBalanceBefore + profit);
        assertEq(IERC20(token0).balanceOf(address(flashloan)), 0);
    }

    function testRejectsUnexpectedCallbackCaller() public {
        vm.expectRevert(Errors.UnexpectedCallback.selector);
        flashloan.uniswapV2Call(address(flashloan), 1 ether, 0, bytes(""));
    }

    function testRejectsBorrowingTokenOutsidePair() public {
        vm.expectRevert(Errors.InvalidParameter.selector);
        flashloan.startFlashloan(WETH_USDT_PAIR, makeAddr("not-token-in-pair"), 1 ether);
    }

    function testRejectsZeroBorrowAmount() public {
        IUniswapV2Pair pair = IUniswapV2Pair(WETH_USDT_PAIR);
        address token0 = pair.token0();

        vm.expectRevert(Errors.InvalidFlashloanAmount.selector);
        flashloan.startFlashloan(WETH_USDT_PAIR, token0, 0);
    }

    function testRejectsZeroProfitRecipient() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new UniswapV2FlashloanHarness(address(0));
    }
}

contract UniswapV2FlashloanHarness is UniswapV2Flashloan {
    address public lastPair;
    address public lastToken;
    uint256 public lastAmount;
    uint256 public lastFee;
    address public lastInitiator;

    constructor(address profitRecipient) UniswapV2Flashloan(profitRecipient) {}

    function _executeFlashloan(
        address pair,
        address token,
        uint256 tokenAmount,
        uint256 fee,
        address initiator
    ) internal override {
        lastPair = pair;
        lastToken = token;
        lastAmount = tokenAmount;
        lastFee = fee;
        lastInitiator = initiator;
    }
}
