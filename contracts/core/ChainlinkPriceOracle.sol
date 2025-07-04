// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../interfaces/IPriceOracle.sol';
import '../interfaces/AggregatorV3Interface.sol';
import '../core/AccessControlCenter.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import '../errors/Errors.sol';
import '../interfaces/IEventRouter.sol';
import '../interfaces/IEventPayload.sol';
import '../interfaces/IRegistry.sol';
import '../interfaces/CoreDefs.sol';

/// @title Chainlink Price Oracle
/// @notice Provides price data using Chainlink price feeds
contract ChainlinkPriceOracle is IPriceOracle {
    /// @notice Address of the access control contract
    AccessControlCenter public immutable accessControl;

    /// @notice Registry contract reference
    IRegistry public registry;

    /// @notice Maximum age of price data in seconds
    uint256 public constant MAX_PRICE_AGE = 24 hours;

    /// @notice Chainlink price feed for each token
    mapping(address => address) public priceFeeds;

    /// @notice Base token for each price feed
    mapping(address => address) public baseTokens;


    /// @notice Initialize the oracle with access control
    /// @param _accessControl Address of the access control contract
    /// @param _registry Address of the registry contract
    constructor(address _accessControl, address _registry) {
        if (_accessControl == address(0)) revert InvalidAddress();
        accessControl = AccessControlCenter(_accessControl);

        if (_registry != address(0)) {
            registry = IRegistry(_registry);
        }
    }

    /// @notice Set registry address
    /// @param _registry New registry address
    function setRegistry(address _registry) external {
        if (!accessControl.hasRole(accessControl.DEFAULT_ADMIN_ROLE(), msg.sender)) revert NotAdmin();
        if (_registry == address(0)) revert InvalidAddress();
        registry = IRegistry(_registry);
    }

    /// @dev Get event router
    /// @return router Event router address or address(0) if not available
    function _getEventRouter() internal view returns (address router) {
        if (address(registry) != address(0)) {
            router = registry.getCoreService(CoreDefs.SERVICE_EVENT_ROUTER);
        }
        return router;
    }

    /// @notice Set a price feed for a token
    /// @param token Token address
    /// @param priceFeed Chainlink price feed address
    /// @param baseToken Base token address (e.g. USDC for USD feeds)
    function setPriceFeed(
        address token,
        address priceFeed,
        address baseToken
    ) external {
        if (!accessControl.hasRole(accessControl.GOVERNOR_ROLE(), msg.sender)) revert NotGovernor();
        if (token == address(0) || priceFeed == address(0) || baseToken == address(0)) revert InvalidAddress();

        priceFeeds[token] = priceFeed;
        baseTokens[token] = baseToken;

        // Отправляем событие через EventRouter если доступен
        address router = _getEventRouter();
        if (router != address(0)) {
            IEventPayload.TokenEvent memory eventData = IEventPayload.TokenEvent({
                tokenAddress: token,
                fromToken: address(0),
                toToken: baseToken,
                amount: 0,
                convertedAmount: 0,
                version: 1
            });
            IEventRouter(router).route(
                IEventRouter.EventKind.PriceConverted,
                abi.encode(eventData)
            );
        }
    }

    /// @notice Get price for a token pair from Chainlink
    /// @param token Token to get price for
    /// @param baseToken Base token to compare against
    /// @return price Price with decimals
    /// @return decimals Number of decimals in the price
    function getPrice(address token, address baseToken) public view override returns (uint256 price, uint8 decimals) {
        // Если токены совпадают, возвращаем 1:1
        if (token == baseToken) {
            return (10**IERC20Metadata(token).decimals(), IERC20Metadata(token).decimals());
        }

        // Проверяем, есть ли прямой feed
        address directFeed = priceFeeds[token];
        address directBase = baseTokens[token];

        // Если прямого feed нет, или базовый токен не совпадает - ошибка
        if (directFeed == address(0) || directBase != baseToken) revert UnsupportedPair();

        // Получаем данные из Chainlink
        AggregatorV3Interface feed = AggregatorV3Interface(directFeed);
        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        // Проверяем корректность данных
        if (answer <= 0) revert InvalidPrice();
        if (updatedAt < block.timestamp - MAX_PRICE_AGE) revert StalePrice();
        if (answeredInRound < roundId) revert StalePrice();

        return (uint256(answer), feed.decimals());
    }
    /// @notice Отправляет событие конвертации токенов
    /// @param fromToken Исходный токен
    /// @param toToken Целевой токен
    /// @param amount Исходная сумма
    /// @param convertedAmount Конвертированная сумма
    function emitConversionEvent(
        address fromToken,
        address toToken,
        uint256 amount,
        uint256 convertedAmount
    ) external {
        if (!accessControl.hasRole(accessControl.DEFAULT_ADMIN_ROLE(), msg.sender)) revert NotAdmin();
        address eventRouter = _getEventRouter();
        if (eventRouter != address(0)) {
            IEventPayload.TokenEvent memory eventData = IEventPayload.TokenEvent({
                tokenAddress: address(0),
                fromToken: fromToken,
                toToken: toToken,
                amount: amount,
                convertedAmount: convertedAmount,
                version: 1
            });
            IEventRouter(eventRouter).route(
                IEventRouter.EventKind.TokenConverted,
                abi.encode(eventData)
            );
        }
    }
    /// @notice Convert amount from one token to another using price feeds
    /// @param fromToken Token to convert from
    /// @param toToken Token to convert to
    /// @param amount Amount to convert
    /// @return convertedAmount Amount in target token
    function convertAmount(
        address fromToken,
        address toToken,
        uint256 amount
    ) external view override returns (uint256 convertedAmount) {
        // Если токены совпадают, возвращаем исходную сумму
        if (fromToken == toToken) {
            convertedAmount = amount;

            // События не отправляются для идентичных токенов, чтобы сохранить view модификатор

            return convertedAmount;
        }

        // Получаем общий базовый токен (обычно USDC/USDT)
        address fromBase = baseTokens[fromToken];
        address toBase = baseTokens[toToken];

        // Если разные базовые токены или какой-то отсутствует, возвращаем ошибку
        if (fromBase == address(0) || toBase == address(0) || fromBase != toBase) revert UnsupportedPair();

        // Получаем цены
        (uint256 fromPrice, uint8 fromDecimals) = getPrice(fromToken, fromBase);
        (uint256 toPrice, uint8 toDecimals) = getPrice(toToken, fromBase);

        // Получаем информацию о десятичных знаках токенов
        uint8 fromTokenDecimals = IERC20Metadata(fromToken).decimals();
        uint8 toTokenDecimals = IERC20Metadata(toToken).decimals();

        // Рассчитываем промежуточную сумму в базовом токене
        uint256 baseAmount = (amount * fromPrice) / (10**fromDecimals);

        // Конвертируем в целевой токен
        uint256 adjustedForDecimals = (baseAmount * (10**toTokenDecimals)) / (10**fromTokenDecimals);
        convertedAmount = (adjustedForDecimals * (10**toDecimals)) / toPrice;

        // События перенесены в отдельный метод emitConversionEvent, который может быть вызван после convertAmount

        return convertedAmount;
    }

    /// @notice Check if a token pair is supported
    /// @param token Token to check
    /// @param baseToken Base token to check against
    /// @return supported True if the pair is supported
    function isPairSupported(address token, address baseToken) external view override returns (bool supported) {
        // Если токены совпадают, пара всегда поддерживается
        if (token == baseToken) {
            return true;
        }

        // Проверяем наличие feed и соответствие базового токена
        address feed = priceFeeds[token];
        address tokenBase = baseTokens[token];

        return feed != address(0) && tokenBase == baseToken;
    }
}
