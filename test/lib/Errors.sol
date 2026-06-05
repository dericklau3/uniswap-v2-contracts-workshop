// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

library Errors {
    error ZeroAddress();
    error InvalidParameter();
    error InvalidFlashloanAmount();
    error FlashloanInProgress();
    error UnexpectedCallback();
    error InsufficientRepaymentBalance();
}
