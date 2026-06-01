// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IPriceOracle {
    function getPrice(address token) external view returns (uint256);
}
