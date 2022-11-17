// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// stores price of an asset
contract PriceOracle {
    uint private price;

    constructor(uint _price) {
        price = _price;
    }

    function latestRoundData() external view returns (uint) {
        return price;
    }

    function decimals() external pure returns (uint) {
        return 18;
    }
}