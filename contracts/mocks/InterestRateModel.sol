// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract InterestRateModel {
    using SafeMath for uint256;
    /* -------------------------------------------------------------------------- */
    /*                                  Variables                                 */
    /* -------------------------------------------------------------------------- */
    uint256 public baseRate;
    uint256 public multiplier;

    /* -------------------------------------------------------------------------- */
    /*                                  Constructor                               */
    /* -------------------------------------------------------------------------- */
    constructor(uint256 _baseRate, uint256 _multiplier) {
        baseRate = _baseRate;
        multiplier = _multiplier;
    }

    /* -------------------------------------------------------------------------- */
    /*                                  Functions                                 */
    /* -------------------------------------------------------------------------- */
    function getBorrowRate(uint256 cash, uint256 borrows)
        external
        view
        returns (uint256)
    {
        if (cash == 0 && borrows == 0) return 0;
        uint256 utilization = borrows.mul(1e18).div(cash.add(borrows));
        return baseRate.add(utilization.mul(multiplier));
    }
}