// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import './Vault.sol';
import './Exchange.sol';
import './Lever.sol';

import '@openzeppelin/contracts/access/Ownable.sol';

contract System is Ownable {
    Exchange public exchange;
    Vault public vault;
    Lever public lever;

    function setExchange(address _exchange) external onlyOwner {
        exchange = Exchange(_exchange);
    }

    function setVault(address _vault) external onlyOwner {
        vault = Vault(_vault);
    }

    function setLever(address _lever) external onlyOwner {
        lever = Lever(_lever);
    }
}