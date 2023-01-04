// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./lending/LendingMarket.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

abstract contract BaseExchange {
    using SafeMathUpgradeable for uint256;

    /* -------------------------------------------------------------------------- */
    /*                                   Events                                   */
    /* -------------------------------------------------------------------------- */
    event MarginEnabled(address token, address cToken);
    
    event OrderExecuted(bytes32 orderId, address taker, uint fillAmount);
    
    event OrderCancelled(bytes32 orderId);
    
    event MinTokenAmountSet(address token, uint amount);
    
    event FeesSet(uint makerFee, uint takerFee);

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

    /* -------------------------------------------------------------------------- */
    /*                                   Storage                                  */
    /* -------------------------------------------------------------------------- */
    mapping(address => uint) public minTokenAmount;

    mapping(bytes32 => uint) public orderFills;
    mapping(bytes32 => uint) public loopFills;
    mapping(bytes32 => uint) public loops;

    mapping(address => LendingMarket) public assetToMarket;

    uint public makerFee;
    uint public takerFee;

    /* -------------------------------------------------------------------------- */
    /*                             Internal Functions                             */
    /* -------------------------------------------------------------------------- */
    function exchangeInternal(
        Order memory order,
        address taker,
        uint token0amount
     ) internal {
        // set buyer and seller as if order is BUY
        address buyer = order.maker;
        address seller = taker;

        // if SELL, swap buyer and seller
        if (order.orderType == OrderType.SELL || order.orderType == OrderType.SHORT) {
            seller = order.maker;
            buyer = taker;
        }
     
        uint256 exchangeT1Amt = token0amount.mul(uint256(order.exchangeRate)).div(10**18);
        uint256 calculatedMakerFee =  (token0amount * makerFee).div(10**18);
        uint256 calculatedTakerFee = (exchangeT1Amt * takerFee).div(10**18);

        require(calculatedMakerFee < token0amount || calculatedTakerFee <  exchangeT1Amt, "Total amount of fees are more than exchange amount");

        IERC20Upgradeable(order.token0).transferFrom(seller, buyer, (token0amount - calculatedMakerFee));
        IERC20Upgradeable(order.token0).transferFrom(seller, address(this), calculatedMakerFee);
        IERC20Upgradeable(order.token1).transferFrom(buyer, seller, (exchangeT1Amt - calculatedTakerFee));
        IERC20Upgradeable(order.token1).transferFrom(buyer, address(this), calculatedTakerFee);

     //     // actual transfer
     //     IERC20Upgradeable(order.token0).transferFrom(seller, buyer, token0amount);
     //     IERC20Upgradeable(order.token1).transferFrom(buyer, seller, token0amount.mul(order.exchangeRate).div(10**18));
    
    }

    function leverageInternal(
        LendingMarket ctoken0,
        LendingMarket ctoken1,
        uint amount0,
        Order memory order
     ) internal {
        // token 0: supply token0 -> borrow token1 -> swap token1 to token0 -> repeat
        // SHORT token 0: supply token1 -> borrow token0 -> swap token0 to token1 -> repeat
        LendingMarket supplyToken = ctoken0;
        uint supplyAmount = amount0;
        LendingMarket borrowToken = ctoken1;
        uint borrowAmount = amount0.mul(order.exchangeRate).div(10**18);
        if (order.orderType == OrderType.SHORT) {
            supplyToken = ctoken1;
            supplyAmount = amount0.mul(order.exchangeRate).div(10**18);
            borrowToken = ctoken0;
            borrowAmount = amount0;
        }
        supplyAmount = supplyAmount.mul(1e6).div(order.borrowLimit);
        // supply
        supplyToken.mint(order.maker, supplyAmount);
        // borrow
        borrowToken.borrow(order.maker, borrowAmount);
    }

    
    /* -------------------------------------------------------------------------- */
    /*                                  Utilities                                 */
    /* -------------------------------------------------------------------------- */
    function validateOrder(Order memory order) public view returns(bool) {
        
        require(order.amount > 0, "OrderAmount must be greater than 0");
        require(order.exchangeRate > 0, "ExchangeRate must be greater than 0");

        if(order.orderType == OrderType.LONG || order.orderType == OrderType.SHORT){
            require(order.borrowLimit > 0, "BorrowLimit must be greater than 0");
            require(order.borrowLimit < 1e6, "borrowLimit must be less than 1e6");
            require(order.loops > 0, "leverage must be greater than 0");
            require(address(assetToMarket[order.token0]) != address(0), "Margin trading not enabled");
            require(address(assetToMarket[order.token1]) != address(0), "Margin trading not enabled");
        }

        require(order.token0 != address(0), "Invalid token0 address");
        require(order.token1 != address(0), "Invalid token1 address");
        require(order.token0 != order.token1, "token0 and token1 must be different");

        // order is not cancelled
        return true;
    }

    function scaledByBorrowLimit(uint amount, uint borrowLimit, uint loop) public pure returns (uint) {
        for(uint i = 0; i < loop; i++) {
            amount = amount.mul(borrowLimit).div(1e6);
        }
        return amount;
    }


    /**
     * @dev Performs a transfer in, reverting upon failure. Returns the amount actually transferred to the protocol, in case of a fee.
     *  This may revert due to insufficient balance or insufficient allowance.
     * 
     * @dev Similar to EIP20 transfer, except it handles a False result from `transferFrom` and reverts in that case.
     *      This will revert due to insufficient balance or insufficient allowance.
     *      This function returns the actual amount received,
     *      which may be less than `amount` if there is a fee attached to the transfer.
     *
     *      Note: This wrapper safely handles non-standard ERC-20 tokens that do not return a value.
     *            See here: https://medium.com/coinmonks/missing-return-value-bug-at-least-130-tokens-affected-d67bf08521ca
     */
    function doTransferIn(address asset, address from, uint amount) virtual external returns (uint) {
        address underlying_ = asset;
        EIP20NonStandardInterface token = EIP20NonStandardInterface(underlying_);
        uint balanceBefore = EIP20Interface(underlying_).balanceOf(address(this));
        token.transferFrom(from, address(this), amount);

        bool success;
        assembly {
            switch returndatasize()
                case 0 {                       // This is a non-standard ERC-20
                    success := not(0)          // set success to true
                }
                case 32 {                      // This is a compliant ERC-20
                    returndatacopy(0, 0, 32)
                    success := mload(0)        // Set `success = returndata` of override external call 
                }
                default {                      // This is an excessively non-compliant ERC-20, revert.
                    revert(0, 0)
                }
        }
        require(success, "TOKEN_TRANSFER_IN_FAILED");

        // Calculate the amount that was *actually* transferred
        uint balanceAfter = EIP20Interface(underlying_).balanceOf(address(this));
        return balanceAfter - balanceBefore;   // underflow already checked above, just subtract
    }

    /**
     * @dev Performs a transfer out, ideally returning an explanatory error code upon failure rather than reverting.
     *  If caller has not called checked protocol's balance, may revert due to insufficient cash held in the contract.
     *  If caller has checked protocol's balance, and verified it is >= amount, this should not revert in normal conditions.
     *
     * @dev Similar to EIP20 transfer, except it handles a False success from `transfer` and returns an explanatory
     *      error code rather than reverting. If caller has not called checked protocol's balance, this may revert due to
     *      insufficient cash held in this contract. If caller has checked protocol's balance prior to this call, and verified
     *      it is >= amount, this should not revert in normal conditions.
     *
     *      Note: This wrapper safely handles non-standard ERC-20 tokens that do not return a value.
     *            See here: https://medium.com/coinmonks/missing-return-value-bug-at-least-130-tokens-affected-d67bf08521ca
     */
    function doTransferOut(address asset, address payable to, uint amount) virtual external {
        EIP20NonStandardInterface token = EIP20NonStandardInterface(asset);
        token.transfer(to, amount);
        bool success;
        assembly {
            switch returndatasize()
                case 0 {                      // This is a non-standard ERC-20
                    success := not(0)          // set success to true
                }
                case 32 {                     // This is a compliant ERC-20
                    returndatacopy(0, 0, 32)
                    success := mload(0)        // Set `success = returndata` of override external call
                }
                default {                     // This is an excessively non-compliant ERC-20, revert.
                    revert(0, 0)
                }
        }
        require(success, "TOKEN_TRANSFER_OUT_FAILED");
    }


    // function Withdraw() external nonReentrant onlyOwner{
    //      IERC20 token = IERC20(TenkaAdd);
    //        token.transfer(owner(), getTokenBalance(address(this)));
    //      payable(owner()).transfer(getEtherBalance(address(this)));
    
    // } 

}
