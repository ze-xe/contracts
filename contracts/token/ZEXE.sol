pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract ZEXE is ERC20, Ownable {
    constructor() ERC20("Zexe", "ZEXE") {}

    function mint(address user, uint amount) external {
        _mint(user, amount);
    }
}