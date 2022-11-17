// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "./LendingMarket.sol";
import "./System.sol";

contract Lever is Ownable {
    using SafeMath for uint256;
    using Math for uint256;

    System public system;

    mapping(address => address) public assetToMarket;
    mapping(address => bool) public marketListed;

    mapping(address => address[]) public enteredCollateralMarkets;
    mapping(address => address[]) public enteredBorrowMarkets;

    constructor(address _system) {
        system = System(_system);
    }

    /* -------------------------------------------------------------------------- */
    /*                               Admin Functions                              */
    /* -------------------------------------------------------------------------- */
    function createMarket(
        address asset,
        uint minCRatio,
        uint safeCRatio,
        address interestRateModel,
        address priceOracle,
        uint maxCollateral,
        uint maxBorrow
    ) external onlyOwner {
        require(assetToMarket[asset] == address(0), "Market already listed");
        LendingMarket market = new LendingMarket(
            asset,
            minCRatio,
            safeCRatio,
            interestRateModel,
            priceOracle,
            maxCollateral,
            maxBorrow
        );
        assetToMarket[asset] = address(market);
    }

    function listMarket(address asset) external onlyOwner {
        address market = assetToMarket[asset];
        require(market != address(0), "Market does not exist");
        require(marketListed[market] == false, "Market already listed");
        marketListed[market] = true;
    }

    function unlistMarket(address asset) external onlyOwner {
        address market = assetToMarket[asset];
        require(market != address(0), "Market does not exist");
        require(marketListed[market] == true, "Market not listed");
        marketListed[market] = false;
    }

    /* -------------------------------------------------------------------------- */
    /*                              Public Functions                              */
    /* -------------------------------------------------------------------------- */

    function deposit(address asset, uint256 amount) external {
        address market = assetToMarket[asset];
        require(marketListed[market] == true, "Market not listed");
        if(LendingMarket(market).getCollateralBalance(msg.sender) == 0) {
            enteredCollateralMarkets[msg.sender].push(market);
        }
        LendingMarket(market).deposit(msg.sender, amount);
        system.vault().decreaseBalance(asset, amount, msg.sender);
    }

    function withdraw(address asset, uint256 amount) external {
        address market = assetToMarket[asset];
        require(marketListed[market] == true, "Market not listed");
        LendingMarket(market).withdraw(msg.sender, amount);
        // check health
        require(getHealthFactor(msg.sender) > 1e18, "Health factor below 1");
        system.vault().increaseBalance(asset, amount, msg.sender);

        // remove market if no collateral left
        if(LendingMarket(market).getCollateralBalance(msg.sender) == 0) {
            address[] storage markets = enteredCollateralMarkets[msg.sender];
            for(uint i = 0; i < markets.length; i++) {
                if(markets[i] == market) {
                    markets[i] = markets[markets.length - 1];
                    markets.pop();
                    break;
                }
            }
        }
    }

    function borrow(address asset, uint amount) external {
        address market = assetToMarket[asset];
        require(marketListed[market] == true, "Market not listed");
        require(amount > 0, "Amount must be greater than 0");
        if(LendingMarket(market).getBorrowBalance(msg.sender) == 0) {
            enteredBorrowMarkets[msg.sender].push(market);
        }
        LendingMarket(market).borrow(msg.sender, amount);
        require(getHealthFactor(msg.sender) > 1e18, "Health factor below 1");
        system.vault().decreaseBalance(asset, amount, msg.sender);
    }

    function repay(address asset, uint amount) external {
        address market = assetToMarket[asset];
        require(marketListed[market] == true, "Market not listed");
        require(amount > 0, "Amount must be greater than 0");
        LendingMarket(market).repay(msg.sender, amount);

        // remove market from entered markets if repaid all amount
        if(LendingMarket(market).getBorrowBalance(msg.sender) == 0) {
            address[] storage markets = enteredBorrowMarkets[msg.sender];
            for(uint i = 0; i < markets.length; i++) {
                if(markets[i] == market) {
                    markets[i] = markets[markets.length - 1];
                    markets.pop();
                    break;
                }
            }
        }
        system.vault().increaseBalance(asset, amount, msg.sender);
    }

    /* -------------------------------------------------------------------------- */
    /*                               View Functions                               */
    /* -------------------------------------------------------------------------- */
    function getMarket(address asset) external view returns (address) {
        return assetToMarket[asset];
    }

    function getHealthFactor(address user) public view returns (uint) {
        (uint totalBorrow, uint cummulativeBorrowRatio) = getBorrowFactors(user);
        (uint totalCollateral, uint cummulativeCollateralRatio) = getCollateralFactors(user);
        if(totalBorrow == 0) {
            if(totalCollateral == 0) {
                return 0;
            } else {
                return type(uint).max;
            }
        }
        uint collateralRatio = totalCollateral.mul(1e18).div(totalBorrow);
        uint cummulativeMinCRatio = cummulativeCollateralRatio.max(cummulativeBorrowRatio); 
        if(cummulativeMinCRatio == 0){
            return 0;
        }
        return collateralRatio.mul(1e18).div(cummulativeMinCRatio);
    }

    function getCollateralFactors(address user) public view returns(uint, uint) {
        uint totalCollateral = 0;
        uint cummulativeCollateralRatio = 0;

        for(uint i = 0; i < enteredCollateralMarkets[user].length; i++) {
            address market = enteredCollateralMarkets[user][i];
            uint collateral = LendingMarket(market).getCollateralBalanceUSD(user);
            uint _minCRatio = LendingMarket(market).minCRatio();
            totalCollateral = totalCollateral.add(collateral);
            cummulativeCollateralRatio = cummulativeCollateralRatio.add(collateral.mul(_minCRatio));
        }

        if(totalCollateral == 0) {
            return (0, 0);
        }

        cummulativeCollateralRatio = cummulativeCollateralRatio.div(totalCollateral);

        return (totalCollateral, cummulativeCollateralRatio);
    }

    function getBorrowFactors(address user) public view returns(uint, uint) {
        uint totalBorrow = 0;
        uint cummulativeBorrowRatio = 0;

        for(uint i = 0; i < enteredBorrowMarkets[user].length; i++) {
            address market = enteredBorrowMarkets[user][i];
            uint _borrow = LendingMarket(market).getBorrowBalanceUSD(user);
            uint safeCRatio = LendingMarket(market).safeCRatio();
            totalBorrow = totalBorrow.add(_borrow);
            cummulativeBorrowRatio = cummulativeBorrowRatio.add(_borrow.mul(safeCRatio));
        }

        if(totalBorrow == 0) {
            return (0, 0);
        }

        cummulativeBorrowRatio = cummulativeBorrowRatio.div(totalBorrow);

        return (totalBorrow, cummulativeBorrowRatio);
    }
}