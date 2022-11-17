// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import './System.sol';
import 'hardhat/console.sol';

contract Vault is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    System public system;

    constructor(address _system) {
        system = System(_system);
    }

    mapping(address => mapping(address => uint256)) public userTokenBalance;

    function deposit(address token, uint256 amount) external {
        if (amount == 0) revert('ZeroAmt');
        userTokenBalance[msg.sender][token] = userTokenBalance[msg.sender][token].add(amount);
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        emit TokensDeposited(msg.sender, token, amount);
    }

    function withdraw(address token, uint256 amount) external {
        if (amount == 0) revert('ZeroAmt');
        userTokenBalance[msg.sender][token] = userTokenBalance[msg.sender][token].sub(amount);
        IERC20(token).safeTransfer(msg.sender, amount);
        emit TokenWithdrawn(msg.sender, token, amount);
    }

    function getBalance(address token) public view returns (uint256) {
        return userTokenBalance[msg.sender][token];
    }

    //Update data on order execution
    function increaseBalance(
        address token,
        uint256 amount,
        address account
    ) external onlyInternal {
        userTokenBalance[account][token] = userTokenBalance[account][token].add(amount);
    }

    function decreaseBalance(
        address token,
        uint256 amount,
        address account
    ) external onlyInternal {
        userTokenBalance[account][token] = userTokenBalance[account][token].sub(amount);
    }

    modifier onlyInternal() {
        require(msg.sender == address(system.exchange()) || msg.sender == address(system.lever()), 'NotAuthorized');
        _;
    }

    event TokensDeposited(address account, address token, uint256 amount);
    event TokenWithdrawn(address account, address token, uint256 amount);
}
