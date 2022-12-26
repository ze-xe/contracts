// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IExchange {
    /* -------------------------------------------------------------------------- */
    /*                                   Events                                   */
    /* -------------------------------------------------------------------------- */
    event OrderCreated(
        bytes32 orderId,
        address maker,
        address token0,
        address token1,
        uint256 amount,
        uint216 _exchangeRate,
        bool buy,
        uint32 salt
    );

    event OrderUpdated(
        bytes32 orderId,
        uint256 amount,
        uint256 _exchangeRate
    );

    event PairCreated(
        bytes32 pairId,
        address token0,
        address token1,
        uint256 exchangeRateDecimals,
        uint256 minToken0Order,
        uint256 minToken1Order
    );

    event MarginEnabled(address token, address cToken);

    event OrderExecuted(bytes32 orderId, address taker, uint fillAmount);
    event OrderCancelled(bytes32 orderId);

    /* -------------------------------------------------------------------------- */
    /*                                 Structures                                 */
    /* -------------------------------------------------------------------------- */

    enum OrderType {
        BUY,
        SELL,
        LONG,
        SHORT
    }

    struct Order {
        address maker;
        address token0;
        address token1;
        uint256 amount;
        OrderType orderType;
        uint32 salt;
        uint176 exchangeRate;
        uint32 borrowLimit;
        uint8 loops;
    }

    struct Pair {
        address token0;
        address token1;
        uint256 exchangeRateDecimals;
        uint256 minToken0Order;
        uint256 minToken1Order;
    }
}
