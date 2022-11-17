// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ILendingMarket {
    event AccrueInterest(uint totalBorrowsNew, uint interestAccumulated, uint borrowIndexNew);

    struct BorrowBalance {
        uint principal;
        uint interestIndex;
    }
}