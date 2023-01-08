// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./BaseExchange.sol";
import "./lending/interfaces/ILever.sol";

import "./lending/LendingMarket.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/draft-EIP712Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/SignatureCheckerUpgradeable.sol";
// import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";


contract Exchange is BaseExchange, EIP712Upgradeable, AccessControlUpgradeable, PausableUpgradeable, UUPSUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using MathUpgradeable for uint256;
    using SafeMathUpgradeable for uint256;
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /**
     * @dev Initialize the contract
     * @param __name Name of the contract
     * @param __version Version of the contract
     */
    function initialize(string memory __name, string memory __version, address _admin, address _pauser, address _upgradeAdmin) public initializer {
        __Pausable_init();
        __AccessControl_init();
        __EIP712_init(__name, __version);
        __UUPSUpgradeable_init();

        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, _pauser);
        _grantRole(UPGRADER_ROLE, _upgradeAdmin);
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyRole(UPGRADER_ROLE)
        override
    {}

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /* -------------------------------------------------------------------------- */
    /*                              Public Functions                              */
    /* -------------------------------------------------------------------------- */
    /**
     * @dev Execute a limit order
     * @param signature Signature of the order
     * @param order Order struct
     * @param amountToFill Amount of token0 to fill
     * @return Amount of token0 filled
     */
    function _executeLimitOrder(
        bytes memory signature,
        Order memory order,
        uint256 amountToFill
    ) internal returns (uint) {        
        // check signature
        bytes32 orderId = verifyOrderHash(signature, order);
        require(validateOrder(order));

        // Fill Amount
        uint alreadyFilledAmount = orderFills[orderId];
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

        // IERC20Upgradeable(order.token0).transferFrom(seller, buyer, amountToFill);
        // IERC20Upgradeable(order.token1).transferFrom(buyer, seller, amountToFill.mul(uint256(order.exchangeRate)).div(10**18));
      
        // calulate token1 amount based on fillamount and exchange rate
      
        exchangeInternal(order, msg.sender, amountToFill);

        orderFills[orderId] = alreadyFilledAmount.add(amountToFill);
        emit OrderExecuted(orderId, msg.sender, amountToFill);
        return amountToFill;
    }

    /**
     * @dev Execute multiple limit orders as per token0 amount
     * @param signatures Signatures of the orders
     * @param orders Order structs
     * @param token0AmountToFill Amount of token0 to fill
     */
    function executeT0LimitOrders(
        bytes[] memory signatures,
        Order[] memory orders,
        uint256 token0AmountToFill
    ) external {
        require(signatures.length == orders.length, "signatures and orders must have same length");
        for (uint i = 0; i < orders.length; i++) {
            uint amount = 0;
            if(orders[i].orderType == OrderType.BUY || orders[i].orderType == OrderType.SELL) {
                amount = _executeLimitOrder(signatures[i], orders[i], token0AmountToFill);
            } 
            else if(orders[i].orderType == OrderType.LONG || orders[i].orderType == OrderType.SHORT)  {
                amount = _executeT0LeverageOrder(signatures[i], orders[i], token0AmountToFill);
            }
            else {
               revert("Order type not supported");
            }
            token0AmountToFill -= amount;
            if (token0AmountToFill == 0) {
                break;
            }
        }
    }

    /**
     * @dev Execute multiple limit orders as per token1 amount
     * @param signatures Signatures of the orders
     * @param orders Order structs
     * @param token1AmountToFill Amount of token1 to fill
     */
    function executeT1LimitOrders(
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
            }  
            else if(orders[i].orderType == OrderType.LONG || orders[i].orderType == OrderType.SHORT) {
                amount = _executeT0LeverageOrder(signatures[i], orders[i], token0AmountToFill);
            }
            else {
               revert("Order type not supported");
            }
            token0AmountToFill -= amount;
            token1AmountToFill = token0AmountToFill.mul(orders[i].exchangeRate).div(1e18);
            if (token0AmountToFill == 0) {
                break;
            }
        }
    }

    /**
     * @dev Execute a leverage order as per token0 amount
     * @param signature Signature of the order
     * @param order Order struct
     * @param amountToFill Amount of token0 to fill
     * @return Amount of token0 filled
     */
    function _executeT0LeverageOrder(
        bytes memory signature,
        Order memory order,
        uint amountToFill
    ) internal returns (uint) {
        LendingMarket ctoken0 = assetToMarket[order.token0];
        LendingMarket ctoken1 = assetToMarket[order.token1];

        // verify order signature
        bytes32 digest = verifyOrderHash(signature, order);
        require(validateOrder(order));

        uint _executedAmount = 0;
        for(uint i = loops[digest]; i < order.loops; i++){
            uint thisLoopLimitFill = scaledByBorrowLimit(order.amount, order.borrowLimit, i+1);
            uint thisLoopFill = loopFills[digest];
            if(thisLoopFill == 0){
                leverageInternal(ctoken0, ctoken1, thisLoopLimitFill, order);
            }
            
            uint amountToFillInThisLoop = amountToFill.min(thisLoopLimitFill - thisLoopFill);

            // Tokens to transfer in this loop
            _executedAmount += amountToFillInThisLoop;
            exchangeInternal(order, msg.sender, amountToFillInThisLoop);

            loopFills[digest] += amountToFillInThisLoop;
            amountToFill = amountToFill.sub(amountToFillInThisLoop);

            if(thisLoopFill + amountToFillInThisLoop == thisLoopLimitFill){
                loops[digest] += 1;
                loopFills[digest] = 0;
            }

            // If no/min fill amount left
            if(amountToFill <= minTokenAmount[order.token0]){
                break;
            }
        }
        if(_executedAmount > 0){
            emit OrderExecuted(digest, msg.sender, _executedAmount);
        }
        
        return amountToFill;
    }

    /**
     * @dev Execute a leverage order as per token1 amount
     * @param signature Signature of the order
     * @param order Order struct
     * @param amountToFill Amount of token1 to fill
     * @return Amount of token1 filled
     */
    function _executeT1LeverageOrder(
        bytes memory signature,
        Order memory order,
        uint amountToFill
    ) internal returns (uint) {
        LendingMarket ctoken0 = assetToMarket[order.token0];
        LendingMarket ctoken1 = assetToMarket[order.token1];

        // verify order signature
        bytes32 digest = verifyOrderHash(signature, order);  
        require(validateOrder(order));

        uint _executedAmount = 0;
        for (uint i = loops[digest]; i < order.loops + 1; i++) {
            // limit: max amount of token0 this loop can fill
            uint thisLoopLimitFill = scaledByBorrowLimit(order.amount, order.borrowLimit, i);
            uint amountFillInThisLoop = amountToFill.min(thisLoopLimitFill - loopFills[digest]);
            
            // exchange of tokens in this loop
            _executedAmount += amountFillInThisLoop;

            // state after transfer
            loopFills[digest] += amountFillInThisLoop;
            amountToFill = amountToFill.sub(amountFillInThisLoop);

            // If loop is filled && is not last loop 
            if (loopFills[digest] == thisLoopLimitFill && i != order.loops) {
                uint nextLoopAmount = loopFills[digest].mul(order.borrowLimit).div(1e6);
                // borrow token0
                leverageInternal(ctoken0, ctoken1, nextLoopAmount, order);
                // next loop
                loops[digest] += 1;
                loopFills[digest] = 0;
            }

            exchangeInternal(order, msg.sender, _executedAmount);

            // If no/min fill amount left
            if (amountToFill <= minTokenAmount[order.token0]) {
                break;
            }
        }
        if(_executedAmount > 0){
            emit OrderExecuted(digest, msg.sender, _executedAmount);
        }
        return amountToFill;
    }

    /**
     * @notice Executed leverage order with limit orders
     */
    function executeLeverageWithLimitOrders(
        bytes[] memory limitOrderSignatures,
        Order[] memory limitOrders,
        bytes memory signature,
        Order memory order
    ) external {
        // TODO
        // require(limitOrderSignatures.length == limitOrders.length, "Invalid limit order signatures");
        // require(limitOrders.length > 0, "No limit orders");
        // bytes32 orderId = verifyOrderHash(signature, order);
        // require(validateOrder(order), "Invalid order");

        // uint limitOrderExecIndex = 0;
        // uint limitOrdersLength = limitOrders.length;

        // for(uint i = loops[orderId]; i < order.loops; i++){
        //     uint thisLoopLimitFill = scaledByBorrowLimit(order.amount, order.borrowLimit, i+1);
        //     uint thisLoopFill = loopFills[orderId];
        //     if(thisLoopFill == 0){
        //         leverageInternal(assetToMarket[order.token0], assetToMarket[order.token1], thisLoopLimitFill, order);
        //     }
            
        //     uint amountToFillInThisLoop = thisLoopLimitFill - thisLoopFill;

        //     // Tokens to transfer in this loop
        //     for(uint j = limitOrderExecIndex; j < limitOrdersLength; j++){
                
        //     }
        //     uint amount = _executeLimitOrder(limitOrderSignatures, limitOrders, amountToFillInThisLoop);
        //     loopFills[orderId] += amount;
        //     amountToFillInThisLoop = amountToFillInThisLoop.sub(amount);

        //     if(thisLoopFill + amountToFillInThisLoop == thisLoopLimitFill){
        //         loops[orderId] += 1;
        //         loopFills[orderId] = 0;
        //     }

        //     // If no/min fill amount left
        //     if(amountToFillInThisLoop <= minTokenAmount[order.token0]){
        //         break;
        //     }
        // }
    }

    /**
     * @dev Cancel an order
     * @param signature Signature of the order
     * @param order Order struct
     */
    function cancelOrder(
        bytes memory signature,
        Order memory order
    ) external {
        bytes32 orderId = verifyOrderHash(
            signature,
            order
        );
        
        require(order.maker == msg.sender, "Only maker can cancel order");

        if(order.orderType == OrderType.BUY || order.orderType == OrderType.SELL){
            orderFills[orderId] = order.amount;
        } else if(order.orderType == OrderType.LONG || order.orderType == OrderType.SHORT) {
            loopFills[orderId] = order.amount;
            loops[orderId] = order.loops;
        } else {
            revert("Order type not supported");
        }
        emit OrderCancelled(orderId);
    }

    /**
     * @dev Deposit tokens to lever
     * @param token Token to deposit
     * @param amount Amount of token to deposit
     */
    function mint(address token, uint amount) public {
        LendingMarket ctoken = assetToMarket[token];
        require(address(ctoken) != address(0), "Margin trading not enabled");
        require(amount >= minTokenAmount[token], "Amount too small");
        require(ctoken.mint(msg.sender, amount) == 0, "Mint failed");
    }

    /**
     * @dev Withdraw tokens from lever
     * @param token Token to withdraw
     * @param amount Amount of token to withdraw
     */
    function redeem(address token, uint amount) public {
        LendingMarket ctoken = assetToMarket[token];
        require(address(ctoken) != address(0), "Margin trading not enabled");
        require(amount >= minTokenAmount[token], "Amount too small");
        require(ctoken.redeem(msg.sender, amount) == 0, "Redeem failed");
    }

    /**
     * @dev Borrow tokens from lever
     * @param token Token to borrow
     * @param amount Amount of token to borrow
     */
    function borrow(address token, uint amount) public {
        LendingMarket ctoken = assetToMarket[token];
        require(address(ctoken) != address(0), "Margin trading not enabled");
        require(amount >= minTokenAmount[token], "Amount too small");
        require(ctoken.borrow(msg.sender, amount) == 0, "Borrow failed");
    }

    /**
     * @dev Repay tokens to lever
     * @param token Token to repay
     * @param amount Amount of token to repay
     */
    function repay(address token, uint amount) public {
        LendingMarket ctoken = assetToMarket[token];
        require(address(ctoken) != address(0), "Margin trading not enabled");
        require(amount >= minTokenAmount[token], "Amount too small");
        require(ctoken.repayBorrow(msg.sender, amount) == 0, "Repay failed");
    }

    /* -------------------------------------------------------------------------- */
    /*                               Admin Functions                              */
    /* -------------------------------------------------------------------------- */
    /**
     * @dev Enable margin trading for a token
     * @param token Token to enable
     * @param cToken cToken of the token
     */
    function enableMarginTrading(address token, address cToken) external onlyRole(ADMIN_ROLE) {
        assetToMarket[token] = LendingMarket(cToken);
        require(LendingMarket(cToken).underlying() == token, "Invalid cToken");
        emit MarginEnabled(token, cToken);
    }

    /**
     * @dev Set minimum token amount
     * @param token Token to set
     * @param amount Minimum amount of token
     */
    function setMinTokenAmount(address token, uint256 amount) external onlyRole(ADMIN_ROLE) {
        minTokenAmount[token] = amount;
        emit MinTokenAmountSet(token, amount);
    }

    /**
     * @dev Set fees
     * @param _makerFee Maker fee
     * @param _takerFee Taker fee
     */
    function setFees(uint256 _makerFee, uint256 _takerFee) external onlyRole(ADMIN_ROLE)  {
        makerFee = _makerFee;
        takerFee = _takerFee;
        emit FeesSet(_makerFee, _takerFee);
    }

     function withdrawFunds(address _tokenAddress) external onlyRole(ADMIN_ROLE)  {
         IERC20Upgradeable(_tokenAddress).transfer(msg.sender, IERC20Upgradeable(_tokenAddress).balanceOf(address(this)));
       }

    /* -------------------------------------------------------------------------- */
    /*                               View Functions                               */
    /* -------------------------------------------------------------------------- */
    /**
     * @dev Verify the order
     * @param signature Signature of the order
     * @param order Order struct
     */
    function verifyOrderHash(bytes memory signature, Order memory order) public view returns (bytes32) {
        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    keccak256("Order(address maker,address token0,address token1,uint256 amount,uint8 orderType,uint32 salt,uint176 exchangeRate,uint32 borrowLimit,uint8 loops)"),
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
            SignatureCheckerUpgradeable.isValidSignatureNow(order.maker, digest, signature),
            "invalid signature"
        );

        return digest;
    }
}
