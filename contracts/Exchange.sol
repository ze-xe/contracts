// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IExchange.sol";
import "./System.sol";

import "./lending/LendingMarket.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

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
        require(amount > 0, "orderAmount must be greater than 0");
        require(exchangeRate > 0, "exchangeRate must be greater than 0");

        // check signature
        bytes32 orderId = getOrderHash(
            maker,
            token0,
            token1,
            amount,
            buy,
            salt,
            exchangeRate
        );

        require(
            SignatureChecker.isValidSignatureNow(maker, orderId, signature),
            "invalid signature"
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

    function executeLeverageOrder(
        bytes memory signature,
        address maker,
        address token0,
        address token1,
        uint256 amount,
        bool buy,
        uint32 salt,
        uint216 exchangeRate,
        uint128 borrowLimit,
        uint128 loops,
        uint amountToFill
    ) external returns (uint fillAmount) {
        LendingMarket ctoken0 = _cassets[token0];
        LendingMarket ctoken1 = _cassets[token1];
        require(address(ctoken0) != address(0), "Margin trading not enabled");
        require(address(ctoken1) != address(0), "Margin trading not enabled");
        require(loops > 0, "loops must be greater than 0");
        require(amount > 0, "orderAmount must be greater than 0");
        require(exchangeRate > 0, "exchangeRate must be greater than 0");

        // get digest
        bytes32 digest = getLeverageOrderHash(
            maker,
            token0,
            token1,
            amount,
            buy,
            salt,
            exchangeRate,
            borrowLimit,
            loops
        );
        // check signature
        require(
            SignatureChecker.isValidSignatureNow(maker, digest, signature),
            "invalid signature"
        );

        uint executionLoop = _loops[digest];
        fillAmount = 0;

        uint pairExchangeRateDecimals = exchangeRateDecimals(getPairHash(token0, token1));
        uint pairMinToken0Amount = minToken0Amount(getPairHash(token0, token1));

        for (uint i = 0; i < loops - executionLoop; i++) {
            uint thisLoopFill = _loopFills[digest];
            uint amountFillInThisLoop = amountToFill.min(amount - thisLoopFill);
            _loopFills[digest] += amountFillInThisLoop;
            fillAmount += amountFillInThisLoop;

            /*** Transfer of tokens ***/
            // set buyer and seller as if order is BUY
            address buyer = maker;
            address seller = msg.sender;

            // if SELL, swap buyer and seller
            if (!buy) {
                seller = maker;
                buyer = msg.sender;
            }

            // actual transfer
            IERC20(token0).transferFrom(buyer, seller, amountFillInThisLoop);
            IERC20(token1).transferFrom(seller, buyer, amountFillInThisLoop.mul(exchangeRate).div(10**pairExchangeRateDecimals));

            if (thisLoopFill < pairMinToken0Amount) {
                uint nextLoopAmount = amount;
                for(uint j = 0; j < _loops[digest]; j++) {
                    nextLoopAmount = nextLoopAmount.mul(borrowLimit).div(1e6);
                }
                // LONG token 0: supply token0 -> borrow token1 -> swap token1 to token0 -> repeat
                // SHORT token 0: supply token1 -> borrow token0 -> swap token0 to token1 -> repeat
                LendingMarket supplyToken = ctoken1;
                uint supplyAmount = nextLoopAmount.mul(exchangeRate).div(10**pairExchangeRateDecimals);
                LendingMarket borrowToken = ctoken0;
                uint borrowAmount = nextLoopAmount;

                if (buy) {
                    supplyToken = ctoken0;
                    supplyAmount = nextLoopAmount;
                    borrowToken = ctoken1;
                    borrowAmount = nextLoopAmount.mul(exchangeRate).div(10**pairExchangeRateDecimals);
                }
                // supply
                supplyToken.mintFromExchange(maker, supplyAmount);
                // borrow
                borrowToken.borrowFromExchange(maker, borrowAmount);

                _loops[digest] += 1;
                _loopFills[digest] = 0;
            } else if (fillAmount < pairMinToken0Amount) {
                break;
            }
        }
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
        bytes32 orderId = getOrderHash(
            maker,
            token0,
            token1,
            amount,
            buy,
            salt,
            exchangeRate
        );

        require(
            SignatureChecker.isValidSignatureNow(maker, orderId, signature),
            "invalid signature"
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

    function getLeverageOrderHash(
        address maker,
        address token0,
        address token1,
        uint256 amount,
        bool buy,
        uint32 salt,
        uint216 exchangeRate,
        uint176 borrowLimit,
        uint256 leverage
    ) public view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        keccak256(
                            "LeverageOrder(address maker,address token0,address token1,uint256 amount,bool buy,uint32 salt,uint176 exchangeRate,uint32 borrowLimit,uint8 leverage)"
                        ),
                        maker,
                        token0,
                        token1,
                        amount,
                        buy,
                        salt,
                        exchangeRate,
                        borrowLimit,
                        leverage
                    )
                )
            );
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
}
