// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IExchange.sol";
import "./lending/interfaces/ILever.sol";

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

            // If no/min fill amount left
            if (amountToFill <= minTokenAmount(order.token0)) {
                break;
            }
        }
        if(_executedAmount > 0){
            emit OrderExecuted(digest, msg.sender, _executedAmount);
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

            if(thisLoopFill + amountToFillInThisLoop == thisLoopLimitFill){
                _loops[digest] += 1;
                _loopFills[digest] = 0;
            }

            // If no/min fill amount left
            if(amountToFill <= minTokenAmount(order.token0)){
                break;
            }
        }
        if(_executedAmount > 0){
            emit OrderExecuted(digest, msg.sender, _executedAmount);
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

    function mint(address token, uint amount) public {
        LendingMarket ctoken = _cassets[token];
        require(address(ctoken) != address(0), "Margin trading not enabled");
        require(amount >= minTokenAmount(token), "Amount too small");
        require(ctoken.mint(msg.sender, amount) == 0, "Mint failed");
    }

    function redeem(address token, uint amount) public {
        LendingMarket ctoken = _cassets[token];
        require(address(ctoken) != address(0), "Margin trading not enabled");
        require(amount >= minTokenAmount(token), "Amount too small");
        require(ctoken.redeem(msg.sender, amount) == 0, "Redeem failed");
    }

    function borrow(address token, uint amount) public {
        LendingMarket ctoken = _cassets[token];
        require(address(ctoken) != address(0), "Margin trading not enabled");
        require(amount >= minTokenAmount(token), "Amount too small");
        require(ctoken.borrow(msg.sender, amount) == 0, "Borrow failed");
    }

    function repay(address token, uint amount) public {
        LendingMarket ctoken = _cassets[token];
        require(address(ctoken) != address(0), "Margin trading not enabled");
        require(amount >= minTokenAmount(token), "Amount too small");
        require(ctoken.repayBorrow(msg.sender, amount) == 0, "Repay failed");
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

    /* -------------------------------------------------------------------------- */
    /*                               Admin Functions                              */
    /* -------------------------------------------------------------------------- */
    function enableMarginTrading(address token, address cToken) external onlyOwner {
        _cassets[token] = LendingMarket(cToken);
        require(LendingMarket(cToken).underlying() == token, "Invalid cToken");
        emit MarginEnabled(token, cToken);
    }

    function setMinTokenAmount(address token, uint amount) external onlyOwner {
        _minTokenAmount[token] = amount;
        emit MinTokenAmountSet(token, amount);
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
        console.log("Supplying", supplyAmount);
        supplyToken.mint(order.maker, supplyAmount);
        // borrow
        borrowToken.borrow(order.maker, borrowAmount);
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
