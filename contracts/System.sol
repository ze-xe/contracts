// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import './Exchange.sol';
import './lending/Lever.sol';

import '@openzeppelin/contracts/access/Ownable.sol';

contract System is Ownable {
    Exchange public exchange;
    Lever public lever;

    function setExchange(address _exchange) external onlyOwner {
        exchange = Exchange(_exchange);
    }

    function setLever(address _lever) external onlyOwner {
        lever = Lever(_lever);
    }
}