// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IExchange.sol";
import "./System.sol";

import "./lending/LendingMarket.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
// import "hardhat/console.sol";

contract Exchange is IExchange, EIP712, Ownable {
    using SafeERC20 for IERC20;
    using Math for uint256;
    using SafeMath for uint256;

    // token address => param
    mapping(address => uint) private _minTokenAmount;

    // digest => filled amount
    mapping(bytes32 => uint) private _orderFills;
    mapping(bytes32 => uint) private _loopFills;
    mapping(bytes32 => uint) private _loops;

    // asset => casset
    mapping(address => LendingMarket) private _cassets;

    uint public makerFee = 1e18;
    uint public takerFee = 1e18;

    constructor() EIP712("zexe", "1") {}

    /* -------------------------------------------------------------------------- */
    /*                              Public Functions                              */
    /* -------------------------------------------------------------------------- */

    function _executeLimitOrder(
        bytes memory signature,
        Order memory order,
        uint256 amountToFill
    ) internal returns (uint) {        
        // check signature
        bytes32 orderId = verifyOrderHash(signature, order);
        require(validateOrder(order));

        // Fill Amount
        uint alreadyFilledAmount = _orderFills[orderId];
        amountToFill = amountToFill.min(order.amount.sub(alreadyFilledAmount));
        if(amountToFill == 0) {
            return 0;
        }

        // set buyer and seller as if order is BUY
        address buyer = order.maker;
        address seller = msg.sender;

        // if SELL, swap buyer and seller
        if (order.orderType == OrderType.SELL) {
            seller = order.maker;
            buyer = msg.sender;
        }

        // calulate token1 amount based on fillamount and exchange rate
        IERC20(order.token0).transferFrom(seller, buyer, amountToFill);
        IERC20(order.token1).transferFrom(buyer, seller, amountToFill.mul(uint256(order.exchangeRate)).div(10**18));

        _orderFills[orderId] = alreadyFilledAmount.add(amountToFill);
        emit OrderExecuted(orderId, msg.sender, amountToFill);
        return amountToFill;
    }

    function executeLimitOrders(
        bytes[] memory signatures,
        Order[] memory orders,
        uint256 token0AmountToFill
    ) external {
        require(signatures.length == orders.length, "signatures and orders must have same length");
        for (uint i = 0; i < orders.length; i++) {
            uint amount = 0;
            if(orders[i].orderType == OrderType.BUY || orders[i].orderType == OrderType.SELL) {
                amount = _executeLimitOrder(signatures[i], orders[i], token0AmountToFill);
            } else {
                amount = _executeLeverageOrder(signatures[i], orders[i], token0AmountToFill);
            }
            token0AmountToFill -= amount;
            if (token0AmountToFill == 0) {
                break;
            }
        }
    }

    function executeMarketOrders(
        bytes[] memory signatures,
        Order[] memory orders,
        uint256 token1AmountToFill
    ) external {
        require(signatures.length == orders.length, "signatures and orders must have same length");
        for (uint i = 0; i < orders.length; i++) {
            uint token0AmountToFill = token1AmountToFill.mul(1e18).div(orders[i].exchangeRate);
            uint amount = 0;
            if(orders[i].orderType == OrderType.BUY || orders[i].orderType == OrderType.SELL) {
                amount = _executeLimitOrder(signatures[i], orders[i], token0AmountToFill);
            } else {
                amount = _executeLeverageOrder(signatures[i], orders[i], token0AmountToFill);
            }
            token0AmountToFill -= amount;
            token1AmountToFill = token0AmountToFill.mul(orders[i].exchangeRate).div(1e18);
            if (token0AmountToFill == 0) {
                break;
            }
        }
    }

    function _executeReverseLeverageOrder(
        bytes memory signature,
        Order memory order,
        uint amountToFill
    ) internal returns (uint) {
        LendingMarket ctoken0 = _cassets[order.token0];
        LendingMarket ctoken1 = _cassets[order.token1];
        require(address(ctoken0) != address(0), "Margin trading not enabled");
        require(address(ctoken1) != address(0), "Margin trading not enabled");

        // verify order signature
        bytes32 digest = verifyOrderHash(signature, order);  
        require(validateOrder(order));

        uint _executedAmount = 0;

        for (uint i = _loops[digest]; i < order.loops + 1; i++) {
            // limit: max amount of token0 this loop can fill
            uint thisLoopLimitFill = scaledByBorrowLimit(order.amount, order.borrowLimit, i);
            uint amountFillInThisLoop = amountToFill.min(thisLoopLimitFill - _loopFills[digest]);
            
            // exchange of tokens in this loop
            _executedAmount += amountFillInThisLoop;

            // state after transfer
            _loopFills[digest] += amountFillInThisLoop;
            amountToFill = amountToFill.sub(amountFillInThisLoop);

            /** If loop is filled && is not last loop */
            if (_loopFills[digest] == thisLoopLimitFill && i != order.loops) {
                uint nextLoopAmount = _loopFills[digest].mul(order.borrowLimit).div(1e6);
                // borrow token0
                leverageInternal(ctoken0, ctoken1, nextLoopAmount, order);
                // next loop
                _loops[digest] += 1;
                _loopFills[digest] = 0;
            }

            exchangeInternal(order, msg.sender, _executedAmount);
            emit OrderExecuted(digest, msg.sender, _executedAmount);

            // If no/min fill amount left
            if (amountToFill <= minTokenAmount(order.token0)) {
                break;
            }
        }
        return amountToFill;
    }

    function _executeLeverageOrder(
        bytes memory signature,
        Order memory order,
        uint amountToFill
    ) internal returns (uint) {
        
        LendingMarket ctoken0 = _cassets[order.token0];
        LendingMarket ctoken1 = _cassets[order.token1];

        // verify order signature
        bytes32 digest = verifyOrderHash(signature, order);
        require(validateOrder(order));

        uint _executedAmount = 0;
        for(uint i = _loops[digest]; i < order.loops; i++){
            uint thisLoopLimitFill = scaledByBorrowLimit(order.amount, order.borrowLimit, i+1);
            uint thisLoopFill = _loopFills[digest];
            if(thisLoopFill == 0){
                leverageInternal(ctoken0, ctoken1, thisLoopLimitFill, order);
            }
            
            uint amountToFillInThisLoop = amountToFill.min(thisLoopLimitFill - thisLoopFill);

            // Tokens to transfer in this loop
            _executedAmount += amountToFillInThisLoop;
            exchangeInternal(order, msg.sender, amountToFillInThisLoop);

            _loopFills[digest] += amountToFillInThisLoop;
            amountToFill = amountToFill.sub(amountToFillInThisLoop);

            emit OrderExecuted(digest, msg.sender, _executedAmount);

            if(thisLoopFill + amountToFillInThisLoop == thisLoopLimitFill){
                _loops[digest] += 1;
                _loopFills[digest] = 0;
            }

            // If no/min fill amount left
            if(amountToFill <= minTokenAmount(order.token0)){
                break;
            }
        }
        return amountToFill;
    }

    function cancelOrder(
        bytes memory signature,
        Order memory order
    ) external {
        bytes32 orderId = verifyOrderHash(
            signature,
            order
        );

        _orderFills[orderId] = order.amount;
        emit OrderCancelled(orderId);
    }

    /* -------------------------------------------------------------------------- */
    /*                               Admin Functions                              */
    /* -------------------------------------------------------------------------- */
    function enableMarginTrading(address token, address cToken, uint minAmount) external onlyOwner {
        _cassets[token] = LendingMarket(cToken);
        require(LendingMarket(cToken).underlying() == token, "Invalid cToken");
        _minTokenAmount[token] = minAmount;
        emit MarginEnabled(token, cToken);
    }

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

        // actual transfer
        IERC20(order.token0).transferFrom(seller, buyer, token0amount);
        IERC20(order.token1).transferFrom(buyer, seller, token0amount.mul(order.exchangeRate).div(10**18));
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
        supplyToken.mintFromExchange(order.maker, supplyAmount);
        // borrow
        borrowToken.borrowFromExchange(order.maker, borrowAmount);
    }

    /* -------------------------------------------------------------------------- */
    /*                               View Functions                               */
    /* -------------------------------------------------------------------------- */
    function verifyOrderHash(bytes memory signature, Order memory order) public view returns (bytes32) {

        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    keccak256(
                        "Order(address maker,address token0,address token1,uint256 amount,uint8 orderType,uint32 salt,uint176 exchangeRate,uint32 borrowLimit,uint8 loops)"
                    ),
                    order.maker,
                    order.token0,
                    order.token1,
                    order.amount,
                    uint8(order.orderType),
                    order.salt,
                    order.exchangeRate,
                    order.borrowLimit,
                    order.loops
                )
            )
        );
        require(
            SignatureChecker.isValidSignatureNow(order.maker, digest, signature),
            "invalid signature"
        );

        return digest;
    }

    function validateOrder(Order memory order) public view returns(bool) {
        
        require(order.amount > 0, "OrderAmount must be greater than 0");
        require(order.exchangeRate > 0, "ExchangeRate must be greater than 0");

        if(order.orderType == OrderType.LONG || order.orderType == OrderType.SHORT){
            require(order.borrowLimit > 0, "BorrowLimit must be greater than 0");
            require(order.borrowLimit < 1e6, "borrowLimit must be less than 1e6");
            require(order.loops > 0, "leverage must be greater than 0");
            require(address(_cassets[order.token0]) != address(0), "Margin trading not enabled");
            require(address(_cassets[order.token1]) != address(0), "Margin trading not enabled");
        }

        require(order.token0 != address(0), "Invalid token0 address");
        require(order.token1 != address(0), "Invalid token1 address");
        require(order.token0 != order.token1, "token0 and token1 must be different");
        return true;
    }

    function minTokenAmount(address token) public view returns (uint) {
        return _minTokenAmount[token];
    }

    function orderFills(bytes32 digest) public view returns (uint) {
        return _orderFills[digest];
    }

    function loops(bytes32 digest) public view returns (uint) {
        return _loops[digest];
    }

    function loopFill(bytes32 digest) public view returns (uint) {
        return _loopFills[digest];
    }

    function scaledByBorrowLimit(uint amount, uint borrowLimit, uint loop) public pure returns (uint) {
        for(uint i = 0; i < loop; i++) {
            amount = amount.mul(borrowLimit).div(1e6);
        }
        return amount;
    }
}
