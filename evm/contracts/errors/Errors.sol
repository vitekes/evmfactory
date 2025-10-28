// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Общие ошибки
error ZeroAddress();
error InvalidAddress();
error InvalidAmount();
error InvalidParameter();
error NotAuthorized();
error FeeTooHigh();
error FeeExceedsAmount();
error InvalidImplementation();
error InvalidSignature();

// Ошибки управления доступом
error NotAdmin();
error NotFeatureOwner();
error NotOperator();
error NotRelayer();
error NotFactoryAdmin();
error NotGovernor();
error NotSeller();
error Unauthorized();
error NotOwner();
error Forbidden();
error NotAutomation();
error NotModule();

// Ошибки реестра
error InvalidServiceName();
error ServiceAlreadyRegistered();
error ServiceNotFound();
error InvalidModule();
error ModuleNotRegistered();

// Ошибки токенов и платежей
error NothingToWithdraw();
error InsufficientBalance();
error RefundDisabled();
error TransferFailed();
error NotAllowedToken();
error ValidatorNotFound();
error PriceFeedNotFound();
error InvalidPrice();
error InvalidDecimals();
error InvalidPriceFeed();
error AmountZero();
error UnsupportedPair();
error PaymentGatewayNotRegistered();
error PriceZero();
error TokenDuplicated();
error TokenAlreadyAllowed();
error TokenNotAllowed();
error PaymentTokenNotSupported();
error PriceNotSet();
error StalePrice();

// Ошибки валидации
error InvalidFee();
error InvalidState();
error InvalidArgument();
error InvalidParameters();
error InvalidBounds();
error InvalidKind();
error InvalidTemplateId();
error InvalidEventKind();

// Ошибки подписи и транзакций
error Expired();
error InvalidChain();
error PermitFailed();
error LimitExceeded();
error ExceedsRefundLimit();
error BatchTooLarge();
error LengthMismatch();
error Overflow();
error GasZero();

// Ошибки рынка
error AlreadyPurchased();
error PriceExceedsMaximum();
error NotListed();
error NotCreator();
error NotTemplateAdmin();
error NotDue();
error NoPlan();
error InitFailed();

// Ошибки конкурсов
error EscrowExpired();
error ContestNotActive();
error DeadlineInPast();
error DeadlineNotReached();
error NoWinners();
error PrizeNotSet();
error InvalidPrizeDistribution();
error DuplicateWinner();
error InvalidPrizeData();
error InvalidPrizeData_ZeroAmount();
error InvalidPrizeData_InvalidPromoSettings();
error InvalidPrizeData_UnsupportedType();
error InvalidDistribution();
error ContestFundingMissing();
error ContestAlreadyFinalized();
error WrongWinnersCount();

// Прочие ошибки
error SbtNonTransferable();
error NotFound();
error CommitmentInvalid();
error AlreadyCommitted();
error GracePeriodNotExpired();
error PlanAlreadyExists();
error PlanNotFound();
error PlanInactive();
error PlanFrozen();
error UnauthorizedMerchant();
error ActivePlanLimitReached();
error ActivePlanExists();
error RetryWindow();
