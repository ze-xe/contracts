// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./Lever.sol";
import "./IPriceOracle.sol";
import "./ILendingMarket.sol";
import "./IInterestRateModel.sol";
import "hardhat/console.sol";

contract LendingMarket is ILendingMarket {
    using SafeMath for uint;

    // lever contract 
    Lever public lever;
    // underlying token
    address public token;
    // helper contracts
    IPriceOracle public priceOracle;
    IInterestRateModel public interestRateModel;

    // safety paramters
    uint256 public safeCRatio;      // 200-500%
    uint256 public minCRatio;       // 150-200%
    uint256 public liquidationIncentive;

    // user collateral
    mapping (address => uint) private _collateralBalance;

    // user borrow balance
    mapping (address => BorrowBalance) private _borrowBalance;
    // for calulating interest
    uint256 public accrualBlockTimestamp;
    uint256 public borrowIndex;     // 1e18

    // current total collateral provided by all users
    uint256 public totalCollateral;
    // current total borrow amount by all users
    uint256 public totalBorrows;
    // max collateral supported in this market
    uint256 public maxCollateral;
    // max borrow supported in this market
    uint256 public maxBorrow;

    constructor(address _token, uint256 _minCRatio, uint256 _safeCRatio, address _interestRateModel, address _priceOracle, uint _maxCollateral, uint _maxBorrow) {
        minCRatio = _minCRatio;
        safeCRatio = _safeCRatio;
        interestRateModel = IInterestRateModel(_interestRateModel);
        token = _token;
        lever = Lever(msg.sender);
        priceOracle = IPriceOracle(_priceOracle);
        maxCollateral = _maxCollateral;
        maxBorrow = _maxBorrow;
    }

    /* -------------------------------------------------------------------------- */
    /*                               Admin Functions                              */
    /* -------------------------------------------------------------------------- */
    function setMinCRatio(uint256 _minCRatio) external onlyOwner {
        minCRatio = _minCRatio;
    }

    function setSafeCRatio(uint256 _safeCRatio) external onlyOwner {
        safeCRatio = _safeCRatio;
    }

    function setInterestRateModel(address _interestRateModel) external onlyOwner {
        interestRateModel = IInterestRateModel(_interestRateModel);
    }

    function setMaxBorrow(uint256 _maxBorrow) external onlyOwner {
        maxBorrow = _maxBorrow;
    }

    function setMaxCollateral(uint256 _maxCollateral) external onlyOwner {
        maxCollateral = _maxCollateral;
    }

    /* -------------------------------------------------------------------------- */
    /*                              Public Functions                              */
    /* -------------------------------------------------------------------------- */
    function deposit(address user, uint256 amount) external onlyLever {
        _collateralBalance[user] += amount;
        totalCollateral += amount;
        require(totalCollateral <= maxCollateral, "Max deposits reached");
    }

    function withdraw(address user, uint256 amount) external onlyLever {
        require(_collateralBalance[user] >= amount, "Insufficient collateral");
        _collateralBalance[user] -= amount;
        totalCollateral -= amount;
    }

    function borrow(address user, uint256 amount) external onlyLever {
        accrueInterest();
        uint256 borrowBalance = _borrowBalance[user].principal;
        uint256 borrowBalanceNew = borrowBalance.add(amount);
        _borrowBalance[user].principal = borrowBalanceNew;
        _borrowBalance[user].interestIndex = borrowIndex;
        totalBorrows += amount;
        require(totalBorrows <= maxBorrow, "Max borrow reached");
    }

    function repay(address user, uint256 amount) external {
        accrueInterest();
        uint256 borrowBalance = _borrowBalance[user].principal;
        uint256 borrowBalanceNew = borrowBalance.sub(amount);
        _borrowBalance[user].principal = borrowBalanceNew;
        _borrowBalance[user].interestIndex = borrowIndex;
        totalBorrows -= amount;
    }

    function accrueInterest() public {
        /* Remember the initial block number */
        uint currentBlockTimestamp = block.timestamp;
        uint accrualBlockTimestampPrior = accrualBlockTimestamp;

        /* Short-circuit accumulating 0 interest */
        if (accrualBlockTimestampPrior == currentBlockTimestamp) {
            return;
        }

        /* Read the previous values out of storage */
        uint borrowIndexPrior = borrowIndex;

        /* Calculate the current borrow interest rate */
        uint borrowRate = interestRateModel.getBorrowRate(getCash(), totalBorrows);

        /* Calculate the time elapsed since the last accrual */
        uint timeDelta = currentBlockTimestamp - accrualBlockTimestampPrior;

        /*
         *  Calculate the interest accumulated into borrows and reserves and the new index:
         *  simpleInterestFactor = borrowRate * blockDelta
         *  interestAccumulated = simpleInterestFactor * totalBorrows
         *  totalBorrowsNew = interestAccumulated + totalBorrows
         *  totalReservesNew = interestAccumulated * reserveFactor + totalReserves
         *  borrowIndexNew = simpleInterestFactor * borrowIndex + borrowIndex
         */

        uint simpleInterestFactor = borrowRate.mul(timeDelta);
        uint interestAccumulated = simpleInterestFactor.mul(totalBorrows).div(10 ** 18); // div by borrow rate decimals
        uint totalBorrowsNew = interestAccumulated.add(totalBorrows);
        uint borrowIndexNew = (simpleInterestFactor.mul(borrowIndexPrior).div(10 ** 18)).add(borrowIndexPrior);

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /* We write the previously calculated values into storage */
        accrualBlockTimestamp = currentBlockTimestamp;
        borrowIndex = borrowIndexNew;
        totalBorrows = totalBorrowsNew;

        /* We emit an AccrueInterest event */
        emit AccrueInterest(totalBorrowsNew, interestAccumulated, borrowIndexNew);
    }


    /* -------------------------------------------------------------------------- */
    /*                               View Functions                               */
    /* -------------------------------------------------------------------------- */
    function getPrice() public view returns (int256, uint8) {
        return (priceOracle.latestRoundData(), priceOracle.decimals());
    }

    function getCash() public view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    function getCollateralBalance(address user) external view returns (uint256) {
        return _collateralBalance[user];
    }

    function getBorrowBalance(address user) external view returns (uint256) {
        return _borrowBalance[user].principal;
    }

    function getCollateralBalanceUSD(address user) external view returns (uint256) {
        (int256 price, uint8 decimals) = getPrice();
        return uint256(price) * _collateralBalance[user] / 10 ** decimals;
    }

    function getBorrowBalanceUSD(address user) external view returns (uint256) {
        (int256 price, uint8 decimals) = getPrice();
        return uint256(price) * _borrowBalance[user].principal / 10 ** decimals;
    }

    /* -------------------------------------------------------------------------- */
    /*                                  Modifiers                                 */
    /* -------------------------------------------------------------------------- */
    modifier onlyOwner(){
        require(msg.sender == lever.owner(), "Not owner can call this function");
        _;
    }

    modifier onlyLever(){
        require(msg.sender == address(lever), "Not lever can call this function");
        _;
    }
}