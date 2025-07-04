// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Common errors
error ZeroAddress();
error InvalidAddress();
error NotAdmin();
error NotFeatureOwner();
error NotOwner();
error NotAuthorized();
error NotFactoryAdmin();
error NotGovernor();
error NotSeller();
error Unauthorized();
error InvalidFee();
error InvalidImplementation();
error InvalidAmount();
error InvalidState();
error InvalidArgument();

// Token-related errors
error NotAllowedToken();
error UnsupportedPair();
error PriceFeedNotFound();
error InvalidPrice();
error ValidatorNotFound();

// Signature errors
error InvalidSignature();
error Expired();
error InvalidChain();
error AlreadyPurchased();
error PriceExceedsMaximum();

// Contest errors
error InvalidPrizeData();
error InvalidPrizeData_ZeroAmount();
error InvalidPrizeData_InvalidPromoSettings();
error InvalidPrizeData_UnsupportedType();
error InvalidDistribution();
error ContestFundingMissing();

// Payment errors
error PaymentGatewayNotRegistered();
error Forbidden();
error LimitExceeded();
error InvalidTemplateId();
error InvalidBounds();
error PriceZero();
error NotAutomation();
error NotModule();
error NotListed();
error NotCreator();
error NotTemplateAdmin();
error InvalidKind();
error Overflow();
error AmountZero();
error BatchTooLarge();
error FeeExceedsAmount();
error FeeTooHigh();
error GasZero();
error InitFailed();
error LengthMismatch();
error ModuleNotRegistered();
error NoPlan();
error NotDue();
error NothingToWithdraw();
error PermitFailed();
error RefundDisabled();
error SbtNonTransferable();
error NotFound();
error ExceedsRefundLimit();
error InsufficientBalance();
error CommitmentInvalid();
error AlreadyCommitted();
error GracePeriodNotExpired();
error TokenDuplicated();
error ContestAlreadyFinalized();
error WrongWinnersCount();
error InvalidParameters();
error StalePrice();
error PaymentTokenNotSupported();
error PriceNotSet();
error InvalidServiceName();
error InvalidEventKind();