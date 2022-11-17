// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IInterestRateModel {
    function getBorrowRate(uint cash, uint borrows) external view returns (uint);
}