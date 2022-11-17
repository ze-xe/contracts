// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IExchange.sol";
import "./Vault.sol";
import "./System.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
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

    constructor(address _system) EIP712("Zexe", "1") {
        system = System(_system);
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

    function getOrderHash(
        address maker,
        address token0,
        address token1,
        uint256 amount,
        bool buy,
        uint32 salt,
        uint216 exchangeRate
    ) public view returns (bytes32) {
        return
            _hashTypedDataV4(
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
    }

    function vault() public view returns (Vault) {
        return system.vault();
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


    /* -------------------------------------------------------------------------- */
    /*                              Public Functions                              */
    /* -------------------------------------------------------------------------- */
    function createLimitOrder(
        address token0,
        address token1,
        uint256 amount,
        bool buy,
        uint216 exchangeRate,
        uint32 salt
    ) external {
        uint pairMinToken0Order = minToken0Amount(getPairHash(token0, token1));

        // validation
        if (exchangeRate == 0) revert ('InvalidExchangeRate');
        if (amount < pairMinToken0Order) revert ('InvalidOrderAmount');

        bytes32 orderId = getOrderHash(
            msg.sender, // maker
            token0, // token0
            token1, // token1
            amount, // amount
            buy, // buy
            salt, // salt
            exchangeRate // exchangeRate
        );

        Order storage order = _placedOrders[orderId];
        order.maker = msg.sender;
        order.token0 = token0;
        order.token1 = token1;
        order.exchangeRate = exchangeRate;
        order.amount = amount;
        order.buy = buy;
        order.salt = salt;

        emit OrderCreated(
            orderId,
            msg.sender,
            token0,
            token1,
            amount,
            exchangeRate,
            buy,
            salt
        );
    }

    function updateLimitOrder(
        bytes32 orderId,
        uint256 amount,
        uint216 exchangeRate
    ) external {
        Order storage order = _placedOrders[orderId];
        if (order.maker != msg.sender) revert('NotAuthorized');

        order.amount = amount;
        order.exchangeRate = exchangeRate;

        emit OrderUpdated(orderId, amount, exchangeRate);
    }

    function executeOnChainOrder(bytes32 orderId, uint256 fillAmount) external {
        // Order
        Order memory order = _placedOrders[orderId];
        // Validate order
        if (order.maker == address(0)) revert ('OrderNotFound');
        if (order.amount - orderFills(orderId) < fillAmount)
            revert ('ZeroAmt');

        fillAmount = executeInternal(
            order.maker,
            msg.sender,
            order.token0,
            order.token1,
            order.exchangeRate,
            order.buy,
            order.amount,
            fillAmount,
            orderId
        );
        _orderFills[orderId] = _orderFills[orderId].add(fillAmount);
        emit OrderExecuted(orderId, msg.sender, fillAmount);
    }

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
        require(amount > 0, "orderAmount must be greater than 0");
        require(exchangeRate > 0, "exchangeRate must be greater than 0");

        // check signature
        bytes32 digest = getOrderHash(
            maker,
            token0,
            token1,
            amount,
            buy,
            salt,
            exchangeRate
        );

        require(
            SignatureChecker.isValidSignatureNow(maker, digest, signature),
            "invalid signature"
        );

        fillAmount = executeInternal(
            maker,
            msg.sender,
            token0,
            token1,
            exchangeRate,
            buy,
            amount,
            amountToFill,
            digest
        );

        _orderFills[digest] = orderFills(digest).add(fillAmount);
        emit OrderExecuted(digest, msg.sender, fillAmount);
    }

    function executeInternal(
        address maker,
        address taker,
        address token0,
        address token1,
        uint256 exchangeRate,
        bool buy,
        uint256 orderAmount,
        uint256 amountToFill,
        bytes32 orderId
    ) internal returns (uint fillAmount) {
        // Fill Amount
        fillAmount = amountToFill.min(orderAmount.sub(orderFills(orderId)));
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
        address seller = taker;

        // if SELL, swap buyer and seller
        if (!buy) {
            seller = maker;
            buyer = taker;
        }

        // decrement seller's token0 balance
        vault().decreaseBalance(token0, fillAmount, seller);
        // increment buyer's token0 balance
        vault().increaseBalance(token0, fillAmount, buyer);
        // decrement buyer's token1 balance
        vault().decreaseBalance(token1, token1Amount, buyer);
        // increment seller's token1 balance
        vault().increaseBalance(token1, token1Amount, seller);
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

    modifier onlyAdmin() {
        require(msg.sender == system.owner(), "NotAuthorized");
        _;
    }
}
