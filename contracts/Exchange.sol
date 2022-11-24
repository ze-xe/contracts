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

import "hardhat/console.sol";

contract Exchange is IExchange, EIP712 {
    using SafeERC20 for IERC20;
    using Math for uint256;
    using SafeMath for uint256;

    System public system;
    mapping(bytes32 => Order) private _placedOrders;

    // pairHash => param
    mapping(bytes32 => uint) private _minToken0Amount;
    mapping(bytes32 => uint) private _exchangeRateDecimals;

    // digest => filled amount
    mapping(bytes32 => uint) private _orderFills;
    mapping(bytes32 => uint) private _loopFills;
    mapping(bytes32 => uint) private _loops;

    // asset => casset
    mapping(address => LendingMarket) private _cassets;

    constructor(address _system) EIP712("zexe", "1") {
        system = System(_system);
    }

    /* -------------------------------------------------------------------------- */
    /*                              Public Functions                              */
    /* -------------------------------------------------------------------------- */

    function executeLimitOrder(
        bytes memory signature,
        address maker,
        address token0,
        address token1,
        bool buy,
        uint216 exchangeRate,
        uint256 amount,
        uint32 salt,
        uint256 amountToFill
    ) public returns (uint fillAmount) {
        require(amountToFill > 0, "fillAmount must be greater than 0");
        
        // check signature
        bytes32 orderId = verifyOrderHash(
            signature,
            maker,
            token0,
            token1,
            amount,
            buy,
            salt,
            exchangeRate
        );

        // Fill Amount
        fillAmount = amountToFill.min(amount.sub(orderFills(orderId)));
        _orderFills[orderId] = orderFills(orderId).add(fillAmount);

        // Pair
        uint pairExchangeRateDecimals = exchangeRateDecimals(
            getPairHash(token0, token1)
        );
        // calulate token1 amount based on fillamount and exchange rate
        uint256 token1Amount = fillAmount.mul(
            uint256(exchangeRate).div(10**pairExchangeRateDecimals)
        );

        // set buyer and seller as if order is BUY
        address buyer = maker;
        address seller = msg.sender;

        // if SELL, swap buyer and seller
        if (!buy) {
            seller = maker;
            buyer = msg.sender;
        }

        IERC20(token0).transferFrom(seller, buyer, fillAmount);
        IERC20(token1).transferFrom(buyer, seller, token1Amount);

        _orderFills[orderId] = orderFills(orderId).add(fillAmount);
        emit OrderExecuted(orderId, msg.sender, fillAmount);
    }

    function executeReverseLeverageOrder(
        bytes memory signature,
        LeverageOrder memory order,
        uint amountToFill
    ) external returns (uint) {
        LendingMarket ctoken0 = _cassets[order.token0];
        LendingMarket ctoken1 = _cassets[order.token1];
        require(address(ctoken0) != address(0), "Margin trading not enabled");
        require(address(ctoken1) != address(0), "Margin trading not enabled");

        // verify order signature
        bytes32 digest = verifyLeverageOrderHash(signature, order);  

        uint pairExchangeRateDecimals = exchangeRateDecimals(getPairHash(order.token0, order.token1));
        uint pairMinToken0Amount = minToken0Amount(getPairHash(order.token0, order.token1));

        for (uint i = _loops[digest]; i < order.loops + 1; i++) {
            // limit: max amount of token0 this loop can fill
            uint thisLoopLimitFill = scaledByBorrowLimit(order.amount, order.borrowLimit, i);
            uint amountFillInThisLoop = amountToFill.min(thisLoopLimitFill - _loopFills[digest]);
            
            console.log("loop %s executing %s of %s", i, amountFillInThisLoop, thisLoopLimitFill);
            
            /*** Transfer of tokens in this loop ***/
            // set buyer and seller as if order is BUY
            address buyer = order.maker;
            address seller = msg.sender;

            // if SELL, swap buyer and seller
            if (!order.long) {
                seller = order.maker;
                buyer = msg.sender;
            }

            // actual transfer
            IERC20(order.token0).transferFrom(seller, buyer, amountFillInThisLoop);
            IERC20(order.token1).transferFrom(buyer, seller, amountFillInThisLoop.mul(order.exchangeRate).div(10**pairExchangeRateDecimals));

            // state after transfer
            _loopFills[digest] += amountFillInThisLoop;
            amountToFill = amountToFill.sub(amountFillInThisLoop);

            /** If loop is filled && is not last loop */
            if (_loopFills[digest] == thisLoopLimitFill && i != order.loops) {
                uint nextLoopAmount = _loopFills[digest].mul(order.borrowLimit).div(1e6);
                // token 0: supply token0 -> borrow token1 -> swap token1 to token0 -> repeat
                // SHORT token 0: supply token1 -> borrow token0 -> swap token0 to token1 -> repeat
                LendingMarket supplyToken = ctoken1;
                uint supplyAmount = nextLoopAmount.mul(order.exchangeRate).div(10**pairExchangeRateDecimals);
                LendingMarket borrowToken = ctoken0;
                uint borrowAmount = nextLoopAmount;
                if (order.long) {
                    supplyToken = ctoken0;
                    supplyAmount = nextLoopAmount;
                    borrowToken = ctoken1;
                    borrowAmount = nextLoopAmount.mul(order.exchangeRate).div(10**pairExchangeRateDecimals);
                }
                // supply
                supplyToken.mintFromExchange(order.maker, supplyAmount);
                // borrow
                borrowToken.borrowFromExchange(order.maker, borrowAmount);
                // next loop
                _loops[digest] += 1;
                _loopFills[digest] = 0;
            } 
            /** If no/min fill amount left */
            if (amountToFill < pairMinToken0Amount) {
                break;
            }
        }
        return amountToFill;
    }

    function executeLeverageOrder(
        bytes memory signature,
        LeverageOrder memory order,
        uint amountToFill
    ) external returns (uint) {
        
        // verify order signature
        bytes32 digest = verifyLeverageOrderHash(signature, order);  

        uint pairExchangeRateDecimals = exchangeRateDecimals(getPairHash(order.token0, order.token1));

        uint executionLoop = _loops[digest];
        for(uint i = executionLoop; i < order.loops; i++){
            uint thisLoopLimitFill = scaledByBorrowLimit(order.amount, order.borrowLimit, i+1);
            if(_loopFills[digest] == 0){
                // token 0: supply token0 -> borrow token1 -> swap token1 to token0 -> repeat
                // SHORT token 0: supply token1 -> borrow token0 -> swap token0 to token1 -> repeat
                LendingMarket supplyToken = _cassets[order.token0];
                uint supplyAmount = thisLoopLimitFill;
                LendingMarket borrowToken = _cassets[order.token1];
                uint borrowAmount = thisLoopLimitFill.mul(order.exchangeRate).div(10**pairExchangeRateDecimals);
                if (!order.long) {
                    supplyToken = _cassets[order.token1];
                    supplyAmount = thisLoopLimitFill.mul(order.exchangeRate).div(10**pairExchangeRateDecimals);
                    borrowToken = _cassets[order.token0];
                    borrowAmount = thisLoopLimitFill;
                }
                supplyAmount = supplyAmount.mul(1e6).div(order.borrowLimit);
                // supply
                supplyToken.mintFromExchange(order.maker, supplyAmount);
                // borrow
                borrowToken.borrowFromExchange(order.maker, borrowAmount);
            }
            
            uint amountToFillInThisLoop = amountToFill.min(thisLoopLimitFill - _loopFills[digest]);

            // console.log("loop %s executing %s of %s", _loops[digest], amountToFillInThisLoop, thisLoopLimitFill);

            /*** Transfer of tokens in this loop ***/
            exchangeInternal(
                order.token0,
                order.token1,
                amountToFillInThisLoop,
                order.maker,
                msg.sender,
                order.long,
                order.exchangeRate,
                pairExchangeRateDecimals
            );

            _loopFills[digest] += amountToFillInThisLoop;
            amountToFill = amountToFill.sub(amountToFillInThisLoop);
            if(_loopFills[digest] == thisLoopLimitFill){
                _loops[digest] += 1;
                _loopFills[digest] = 0;
            }
            if(amountToFill < minToken0Amount(getPairHash(order.token0, order.token1))){
                break;
            }
        }

        return amountToFill;
    }

    function exchangeInternal(
        address token0,
        address token1,
        uint amount0,
        address maker, 
        address taker,
        bool long,
        uint exchangeRate,
        uint __exchangeRateDecimals
    ) internal {
        // set buyer and seller as if order is BUY
        address buyer = maker;
        address seller = taker;

        // if SELL, swap buyer and seller
        if (!long) {
            seller = maker;
            buyer = taker;
        }

        // actual transfer
        // console.log("Transfering %s", ERC20(token0).symbol());
        IERC20(token0).transferFrom(seller, buyer, amount0);

        // console.log("Transfering %s", ERC20(token1).symbol());
        // console.log("Transfering %s from %s to %s", amount0.mul(exchangeRate).div(10**__exchangeRateDecimals), seller, buyer);

        IERC20(token1).transferFrom(buyer, seller, amount0.mul(exchangeRate).div(10**__exchangeRateDecimals));
    }

    function cancelOrder(
        bytes memory signature,
        address maker,
        address token0,
        address token1,
        uint256 amount,
        bool buy,
        uint32 salt,
        uint216 exchangeRate
    ) external {
        bytes32 orderId = verifyOrderHash(
            signature,
            maker,
            token0,
            token1,
            amount,
            buy,
            salt,
            exchangeRate
        );

        _orderFills[orderId] = amount;
    }

    /* -------------------------------------------------------------------------- */
    /*                               Admin Functions                              */
    /* -------------------------------------------------------------------------- */
    function updateMinToken0Amount(
        address token0,
        address token1,
        uint256 __minToken0Amount
    ) external onlyAdmin {
        bytes32 pairHash = keccak256(abi.encodePacked(token0, token1));
        _minToken0Amount[pairHash] = __minToken0Amount;
        emit MinToken0AmountUpdated(pairHash, __minToken0Amount);
    }

    function updateExchangeRateDecimals(
        address token0,
        address token1,
        uint256 __exchangeRateDecimals
    ) external onlyAdmin {
        bytes32 pairHash = keccak256(abi.encodePacked(token0, token1));
        _exchangeRateDecimals[pairHash] = __exchangeRateDecimals;
        emit ExchangeRateDecimalsUpdated(pairHash, __exchangeRateDecimals);
    }

    function enableMarginTrading(address token, address cToken) external onlyAdmin {
        _cassets[token] = LendingMarket(cToken);
        require(LendingMarket(cToken).underlying() == token, "Invalid cToken");
    }

    modifier onlyAdmin() {
        require(msg.sender == system.owner(), "NotAuthorized");
        _;
    }

    /* -------------------------------------------------------------------------- */
    /*                               View Functions                               */
    /* -------------------------------------------------------------------------- */
    function getPairHash(address token0, address token1)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(token0, token1));
    }

    function verifyOrderHash(
        bytes memory signature,
        address maker,
        address token0,
        address token1,
        uint256 amount,
        bool buy,
        uint32 salt,
        uint216 exchangeRate
    ) public view returns (bytes32) {
        require(amount > 0, "orderAmount must be greater than 0");
        require(exchangeRate > 0, "exchangeRate must be greater than 0");
        require(token0 != address(0), "Invalid token0 address");
        require(token1 != address(0), "Invalid token1 address");

        bytes32 digest = _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        keccak256(
                            "Order(address maker,address token0,address token1,uint256 amount,bool buy,uint32 salt,uint216 exchangeRate)"
                        ),
                        maker,
                        token0,
                        token1,
                        amount,
                        buy,
                        salt,
                        exchangeRate
                    )
                )
            );
        require(
            SignatureChecker.isValidSignatureNow(maker, digest, signature),
            "invalid signature"
        );

        return digest;
    }

    function verifyLeverageOrderHash(
        bytes memory signature,
        LeverageOrder memory order
    ) public view returns (bytes32) {
        require(order.amount > 0, "orderAmount must be greater than 0");
        require(order.exchangeRate > 0, "exchangeRate must be greater than 0");
        require(order.borrowLimit > 0, "borrowLimit must be greater than 0");
        require(order.borrowLimit < 1e6, "borrowLimit must be less than 1e6");
        require(order.loops > 0, "leverage must be greater than 0");
        require(order.token0 != address(0), "Invalid token0 address");
        require(order.token1 != address(0), "Invalid token1 address");
        require(address(_cassets[order.token0]) != address(0), "Margin trading not enabled");
        require(address(_cassets[order.token1]) != address(0), "Margin trading not enabled");

        bytes32 digest = _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        keccak256(
                            "LeverageOrder(address maker,address token0,address token1,uint256 amount,bool long,uint32 salt,uint176 exchangeRate,uint32 borrowLimit,uint8 loops)"
                        ),
                        order.maker,
                        order.token0,
                        order.token1,
                        order.amount,
                        order.long,
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

    function placedOrders(bytes32 orderId) public view returns (Order memory) {
        return _placedOrders[orderId];
    }

    function minToken0Amount(bytes32 pair) public view returns (uint) {
        return _minToken0Amount[pair];
    }

    function exchangeRateDecimals(bytes32 pair) public view returns (uint) {
        return _exchangeRateDecimals[pair];
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
