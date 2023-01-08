// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
import "./lending/LendingMarket.sol";

abstract contract ExchangeStorage {
    mapping(address => uint) public minTokenAmount;

    mapping(bytes32 => uint) public orderFills;
    mapping(bytes32 => uint) public loopFills;
    mapping(bytes32 => uint) public loops;

    mapping(address => LendingMarket) public assetToMarket;

    uint public makerFee;
    uint public takerFee;
}