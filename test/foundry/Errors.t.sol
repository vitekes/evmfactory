// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../../contracts/errors/Errors.sol";

contract ErrorsTest is Test {
    function setUp() public {}

    /// @notice Тест, который вызывает каждую из доступных ошибок
    /// @dev Используется для проверки корректности объявления ошибок
    function testAllErrorsAreCallable() public {
        // В данном тесте мы используем try-catch для проверки возможности вызвать ошибку
        // Если ошибка объявлена некорректно или дублируется, тест упадет при компиляции

        // Common errors
        try this.triggerZeroAddress() {} catch {};
        try this.triggerInvalidAddress() {} catch {};
        try this.triggerNotAdmin() {} catch {};
        try this.triggerNotFeatureOwner() {} catch {};
        try this.triggerNotOwner() {} catch {};
        try this.triggerNotAuthorized() {} catch {};
        try this.triggerNotFactoryAdmin() {} catch {};
        try this.triggerNotGovernor() {} catch {};
        try this.triggerNotSeller() {} catch {};
        try this.triggerUnauthorized() {} catch {};
        try this.triggerInvalidFee() {} catch {};
        try this.triggerInvalidImplementation() {} catch {};
        try this.triggerInvalidAmount() {} catch {};
        try this.triggerInvalidState() {} catch {};
        try this.triggerInvalidArgument() {} catch {};

        // Token-related errors
        try this.triggerNotAllowedToken() {} catch {};
        try this.triggerUnsupportedPair() {} catch {};
        try this.triggerPriceFeedNotFound() {} catch {};
        try this.triggerInvalidPrice() {} catch {};
        try this.triggerValidatorNotFound() {} catch {};

        // Signature errors
        try this.triggerInvalidSignature() {} catch {};
        try this.triggerExpired() {} catch {};
        try this.triggerInvalidChain() {} catch {};
        try this.triggerAlreadyPurchased() {} catch {};
        try this.triggerPriceExceedsMaximum() {} catch {};

        // Contest errors
        try this.triggerInvalidPrizeData() {} catch {};
        try this.triggerInvalidPrizeDataZeroAmount() {} catch {};
        try this.triggerInvalidPrizeDataInvalidPromoSettings() {} catch {};
        try this.triggerInvalidPrizeDataUnsupportedType() {} catch {};
        try this.triggerInvalidDistribution() {} catch {};
        try this.triggerContestFundingMissing() {} catch {};

        // Payment errors
        try this.triggerPaymentGatewayNotRegistered() {} catch {};
        try this.triggerForbidden() {} catch {};
        try this.triggerLimitExceeded() {} catch {};
        try this.triggerInvalidTemplateId() {} catch {};
        try this.triggerInvalidBounds() {} catch {};
        try this.triggerPriceZero() {} catch {};
        try this.triggerNotAutomation() {} catch {};
        try this.triggerNotModule() {} catch {};
        try this.triggerNotListed() {} catch {};
        try this.triggerNotCreator() {} catch {};
        try this.triggerNotTemplateAdmin() {} catch {};
        try this.triggerInvalidKind() {} catch {};
        try this.triggerOverflow() {} catch {};
        // try this.triggerAlreadyPurchased() {} catch {}; // Дубликат, объявлен выше
        try this.triggerAmountZero() {} catch {};
        try this.triggerBatchTooLarge() {} catch {};
        // try this.triggerExpired() {} catch {}; // Дубликат, объявлен выше
        try this.triggerFeeExceedsAmount() {} catch {};
        try this.triggerFeeTooHigh() {} catch {};
        try this.triggerGasZero() {} catch {};
        try this.triggerInitFailed() {} catch {};
        try this.triggerLengthMismatch() {} catch {};
        try this.triggerModuleNotRegistered() {} catch {};
        try this.triggerNoPlan() {} catch {};
        try this.triggerNotDue() {} catch {};
        try this.triggerNothingToWithdraw() {} catch {};
        try this.triggerPermitFailed() {} catch {};
        try this.triggerRefundDisabled() {} catch {};
        try this.triggerSbtNonTransferable() {} catch {};
        try this.triggerNotFound() {} catch {};
        try this.triggerExceedsRefundLimit() {} catch {};
        try this.triggerInsufficientBalance() {} catch {};
        try this.triggerCommitmentInvalid() {} catch {};
        try this.triggerAlreadyCommitted() {} catch {};
        try this.triggerGracePeriodNotExpired() {} catch {};
        try this.triggerTokenDuplicated() {} catch {};
        try this.triggerContestAlreadyFinalized() {} catch {};
        try this.triggerWrongWinnersCount() {} catch {};
        try this.triggerInvalidParameters() {} catch {};
        try this.triggerStalePrice() {} catch {};
        try this.triggerPaymentTokenNotSupported() {} catch {};
        try this.triggerPriceNotSet() {} catch {};
        try this.triggerInvalidServiceName() {} catch {};
        try this.triggerInvalidEventKind() {} catch {};
    }

    // Common errors
    function triggerZeroAddress() external { revert ZeroAddress(); }
    function triggerInvalidAddress() external { revert InvalidAddress(); }
    function triggerNotAdmin() external { revert NotAdmin(); }
    function triggerNotFeatureOwner() external { revert NotFeatureOwner(); }
    function triggerNotOwner() external { revert NotOwner(); }
    function triggerNotAuthorized() external { revert NotAuthorized(); }
    function triggerNotFactoryAdmin() external { revert NotFactoryAdmin(); }
    function triggerNotGovernor() external { revert NotGovernor(); }
    function triggerNotSeller() external { revert NotSeller(); }
    function triggerUnauthorized() external { revert Unauthorized(); }
    function triggerInvalidFee() external { revert InvalidFee(); }
    function triggerInvalidImplementation() external { revert InvalidImplementation(); }
    function triggerInvalidAmount() external { revert InvalidAmount(); }
    function triggerInvalidState() external { revert InvalidState(); }
    function triggerInvalidArgument() external { revert InvalidArgument(); }

    // Token-related errors
    function triggerNotAllowedToken() external { revert NotAllowedToken(); }
    function triggerUnsupportedPair() external { revert UnsupportedPair(); }
    function triggerPriceFeedNotFound() external { revert PriceFeedNotFound(); }
    function triggerInvalidPrice() external { revert InvalidPrice(); }
    function triggerValidatorNotFound() external { revert ValidatorNotFound(); }

    // Signature errors
    function triggerInvalidSignature() external { revert InvalidSignature(); }
    function triggerExpired() external { revert Expired(); }
    function triggerInvalidChain() external { revert InvalidChain(); }
    function triggerAlreadyPurchased() external { revert AlreadyPurchased(); }
    function triggerPriceExceedsMaximum() external { revert PriceExceedsMaximum(); }

    // Contest errors
    function triggerInvalidPrizeData() external { revert InvalidPrizeData(); }
    function triggerInvalidPrizeDataZeroAmount() external { revert InvalidPrizeData_ZeroAmount(); }
    function triggerInvalidPrizeDataInvalidPromoSettings() external { revert InvalidPrizeData_InvalidPromoSettings(); }
    function triggerInvalidPrizeDataUnsupportedType() external { revert InvalidPrizeData_UnsupportedType(); }
    function triggerInvalidDistribution() external { revert InvalidDistribution(); }
    function triggerContestFundingMissing() external { revert ContestFundingMissing(); }

    // Payment errors
    function triggerPaymentGatewayNotRegistered() external { revert PaymentGatewayNotRegistered(); }
    function triggerForbidden() external { revert Forbidden(); }
    function triggerLimitExceeded() external { revert LimitExceeded(); }
    function triggerInvalidTemplateId() external { revert InvalidTemplateId(); }
    function triggerInvalidBounds() external { revert InvalidBounds(); }
    function triggerPriceZero() external { revert PriceZero(); }
    function triggerNotAutomation() external { revert NotAutomation(); }
    function triggerNotModule() external { revert NotModule(); }
    function triggerNotListed() external { revert NotListed(); }
    function triggerNotCreator() external { revert NotCreator(); }
    function triggerNotTemplateAdmin() external { revert NotTemplateAdmin(); }
    function triggerInvalidKind() external { revert InvalidKind(); }
    function triggerOverflow() external { revert Overflow(); }
    function triggerAmountZero() external { revert AmountZero(); }
    function triggerBatchTooLarge() external { revert BatchTooLarge(); }
    function triggerFeeExceedsAmount() external { revert FeeExceedsAmount(); }
    function triggerFeeTooHigh() external { revert FeeTooHigh(); }
    function triggerGasZero() external { revert GasZero(); }
    function triggerInitFailed() external { revert InitFailed(); }
    function triggerLengthMismatch() external { revert LengthMismatch(); }
    function triggerModuleNotRegistered() external { revert ModuleNotRegistered(); }
    function triggerNoPlan() external { revert NoPlan(); }
    function triggerNotDue() external { revert NotDue(); }
    function triggerNothingToWithdraw() external { revert NothingToWithdraw(); }
    function triggerPermitFailed() external { revert PermitFailed(); }
    function triggerRefundDisabled() external { revert RefundDisabled(); }
    function triggerSbtNonTransferable() external { revert SbtNonTransferable(); }
    function triggerNotFound() external { revert NotFound(); }
    function triggerExceedsRefundLimit() external { revert ExceedsRefundLimit(); }
    function triggerInsufficientBalance() external { revert InsufficientBalance(); }
    function triggerCommitmentInvalid() external { revert CommitmentInvalid(); }
    function triggerAlreadyCommitted() external { revert AlreadyCommitted(); }
    function triggerGracePeriodNotExpired() external { revert GracePeriodNotExpired(); }
    function triggerTokenDuplicated() external { revert TokenDuplicated(); }
    function triggerContestAlreadyFinalized() external { revert ContestAlreadyFinalized(); }
    function triggerWrongWinnersCount() external { revert WrongWinnersCount(); }
    function triggerInvalidParameters() external { revert InvalidParameters(); }
    function triggerStalePrice() external { revert StalePrice(); }
    function triggerPaymentTokenNotSupported() external { revert PaymentTokenNotSupported(); }
    function triggerPriceNotSet() external { revert PriceNotSet(); }
    function triggerInvalidServiceName() external { revert InvalidServiceName(); }
    function triggerInvalidEventKind() external { revert InvalidEventKind(); }
}
import "forge-std/Test.sol";
import "../../contracts/errors/Errors.sol";

contract ErrorsTest is Test {
    function setUp() public {}

    /// @notice Тест, который вызывает каждую из доступных ошибок
    /// @dev Используется для проверки корректности объявления ошибок
    function testAllErrorsAreCallable() public {
        // В данном тесте мы используем try-catch для проверки возможности вызвать ошибку
        // Если ошибка объявлена некорректно или дублируется, тест упадет при компиляции

        // Common errors
        try this.triggerZeroAddress() {} catch {};
        try this.triggerInvalidAddress() {} catch {};
        try this.triggerNotAdmin() {} catch {};
        try this.triggerNotFeatureOwner() {} catch {};
        try this.triggerNotOwner() {} catch {};
        try this.triggerNotAuthorized() {} catch {};
        try this.triggerNotFactoryAdmin() {} catch {};
        try this.triggerNotGovernor() {} catch {};
        try this.triggerNotSeller() {} catch {};
        try this.triggerUnauthorized() {} catch {};
        try this.triggerInvalidFee() {} catch {};
        try this.triggerInvalidImplementation() {} catch {};
        try this.triggerInvalidAmount() {} catch {};
        try this.triggerInvalidState() {} catch {};
        try this.triggerInvalidArgument() {} catch {};

        // Token-related errors
        try this.triggerNotAllowedToken() {} catch {};
        try this.triggerUnsupportedPair() {} catch {};
        try this.triggerPriceFeedNotFound() {} catch {};
        try this.triggerInvalidPrice() {} catch {};
        try this.triggerValidatorNotFound() {} catch {};

        // Signature errors
        try this.triggerInvalidSignature() {} catch {};
        try this.triggerExpired() {} catch {};
        try this.triggerInvalidChain() {} catch {};
        try this.triggerAlreadyPurchased() {} catch {};
        try this.triggerPriceExceedsMaximum() {} catch {};

        // Contest errors
        try this.triggerInvalidPrizeData() {} catch {};
        try this.triggerInvalidPrizeDataZeroAmount() {} catch {};
        try this.triggerInvalidPrizeDataInvalidPromoSettings() {} catch {};
        try this.triggerInvalidPrizeDataUnsupportedType() {} catch {};
        try this.triggerInvalidDistribution() {} catch {};
        try this.triggerContestFundingMissing() {} catch {};

        // Payment errors
        try this.triggerPaymentGatewayNotRegistered() {} catch {};
        try this.triggerForbidden() {} catch {};
        try this.triggerLimitExceeded() {} catch {};
        try this.triggerInvalidTemplateId() {} catch {};
        try this.triggerInvalidBounds() {} catch {};
        try this.triggerPriceZero() {} catch {};
        try this.triggerNotAutomation() {} catch {};
        try this.triggerNotModule() {} catch {};
        try this.triggerNotListed() {} catch {};
        try this.triggerNotCreator() {} catch {};
        try this.triggerNotTemplateAdmin() {} catch {};
        try this.triggerInvalidKind() {} catch {};
        try this.triggerOverflow() {} catch {};
        // try this.triggerAlreadyPurchased() {} catch {}; // Дубликат, объявлен выше
        try this.triggerAmountZero() {} catch {};
        try this.triggerBatchTooLarge() {} catch {};
        // try this.triggerExpired() {} catch {}; // Дубликат, объявлен выше
        try this.triggerFeeExceedsAmount() {} catch {};
        try this.triggerFeeTooHigh() {} catch {};
        try this.triggerGasZero() {} catch {};
        try this.triggerInitFailed() {} catch {};
        try this.triggerLengthMismatch() {} catch {};
        try this.triggerModuleNotRegistered() {} catch {};
        try this.triggerNoPlan() {} catch {};
        try this.triggerNotDue() {} catch {};
        try this.triggerNothingToWithdraw() {} catch {};
        try this.triggerPermitFailed() {} catch {};
        try this.triggerRefundDisabled() {} catch {};
        try this.triggerSbtNonTransferable() {} catch {};
        try this.triggerNotFound() {} catch {};
        try this.triggerExceedsRefundLimit() {} catch {};
        try this.triggerInsufficientBalance() {} catch {};
        try this.triggerCommitmentInvalid() {} catch {};
        try this.triggerAlreadyCommitted() {} catch {};
        try this.triggerGracePeriodNotExpired() {} catch {};
        try this.triggerTokenDuplicated() {} catch {};
        try this.triggerContestAlreadyFinalized() {} catch {};
        try this.triggerWrongWinnersCount() {} catch {};
        try this.triggerInvalidParameters() {} catch {};
        try this.triggerStalePrice() {} catch {};
        try this.triggerPaymentTokenNotSupported() {} catch {};
        try this.triggerPriceNotSet() {} catch {};
        try this.triggerInvalidServiceName() {} catch {};
    }

    // Common errors
    function triggerZeroAddress() external { revert ZeroAddress(); }
    function triggerInvalidAddress() external { revert InvalidAddress(); }
    function triggerNotAdmin() external { revert NotAdmin(); }
    function triggerNotFeatureOwner() external { revert NotFeatureOwner(); }
    function triggerNotOwner() external { revert NotOwner(); }
    function triggerNotAuthorized() external { revert NotAuthorized(); }
    function triggerNotFactoryAdmin() external { revert NotFactoryAdmin(); }
    function triggerNotGovernor() external { revert NotGovernor(); }
    function triggerNotSeller() external { revert NotSeller(); }
    function triggerUnauthorized() external { revert Unauthorized(); }
    function triggerInvalidFee() external { revert InvalidFee(); }
    function triggerInvalidImplementation() external { revert InvalidImplementation(); }
    function triggerInvalidAmount() external { revert InvalidAmount(); }
    function triggerInvalidState() external { revert InvalidState(); }
    function triggerInvalidArgument() external { revert InvalidArgument(); }

    // Token-related errors
    function triggerNotAllowedToken() external { revert NotAllowedToken(); }
    function triggerUnsupportedPair() external { revert UnsupportedPair(); }
    function triggerPriceFeedNotFound() external { revert PriceFeedNotFound(); }
    function triggerInvalidPrice() external { revert InvalidPrice(); }
    function triggerValidatorNotFound() external { revert ValidatorNotFound(); }

    // Signature errors
    function triggerInvalidSignature() external { revert InvalidSignature(); }
    function triggerExpired() external { revert Expired(); }
    function triggerInvalidChain() external { revert InvalidChain(); }
    function triggerAlreadyPurchased() external { revert AlreadyPurchased(); }
    function triggerPriceExceedsMaximum() external { revert PriceExceedsMaximum(); }

    // Contest errors
    function triggerInvalidPrizeData() external { revert InvalidPrizeData(); }
    function triggerInvalidPrizeDataZeroAmount() external { revert InvalidPrizeData_ZeroAmount(); }
    function triggerInvalidPrizeDataInvalidPromoSettings() external { revert InvalidPrizeData_InvalidPromoSettings(); }
    function triggerInvalidPrizeDataUnsupportedType() external { revert InvalidPrizeData_UnsupportedType(); }
    function triggerInvalidDistribution() external { revert InvalidDistribution(); }
    function triggerContestFundingMissing() external { revert ContestFundingMissing(); }

    // Payment errors
    function triggerPaymentGatewayNotRegistered() external { revert PaymentGatewayNotRegistered(); }
    function triggerForbidden() external { revert Forbidden(); }
    function triggerLimitExceeded() external { revert LimitExceeded(); }
    function triggerInvalidTemplateId() external { revert InvalidTemplateId(); }
    function triggerInvalidBounds() external { revert InvalidBounds(); }
    function triggerPriceZero() external { revert PriceZero(); }
    function triggerNotAutomation() external { revert NotAutomation(); }
    function triggerNotModule() external { revert NotModule(); }
    function triggerNotListed() external { revert NotListed(); }
    function triggerNotCreator() external { revert NotCreator(); }
    function triggerNotTemplateAdmin() external { revert NotTemplateAdmin(); }
    function triggerInvalidKind() external { revert InvalidKind(); }
    function triggerOverflow() external { revert Overflow(); }
    function triggerAmountZero() external { revert AmountZero(); }
    function triggerBatchTooLarge() external { revert BatchTooLarge(); }
    function triggerFeeExceedsAmount() external { revert FeeExceedsAmount(); }
    function triggerFeeTooHigh() external { revert FeeTooHigh(); }
    function triggerGasZero() external { revert GasZero(); }
    function triggerInitFailed() external { revert InitFailed(); }
    function triggerLengthMismatch() external { revert LengthMismatch(); }
    function triggerModuleNotRegistered() external { revert ModuleNotRegistered(); }
    function triggerNoPlan() external { revert NoPlan(); }
    function triggerNotDue() external { revert NotDue(); }
    function triggerNothingToWithdraw() external { revert NothingToWithdraw(); }
    function triggerPermitFailed() external { revert PermitFailed(); }
    function triggerRefundDisabled() external { revert RefundDisabled(); }
    function triggerSbtNonTransferable() external { revert SbtNonTransferable(); }
    function triggerNotFound() external { revert NotFound(); }
    function triggerExceedsRefundLimit() external { revert ExceedsRefundLimit(); }
    function triggerInsufficientBalance() external { revert InsufficientBalance(); }
    function triggerCommitmentInvalid() external { revert CommitmentInvalid(); }
    function triggerAlreadyCommitted() external { revert AlreadyCommitted(); }
    function triggerGracePeriodNotExpired() external { revert GracePeriodNotExpired(); }
    function triggerTokenDuplicated() external { revert TokenDuplicated(); }
    function triggerContestAlreadyFinalized() external { revert ContestAlreadyFinalized(); }
    function triggerWrongWinnersCount() external { revert WrongWinnersCount(); }
    function triggerInvalidParameters() external { revert InvalidParameters(); }
    function triggerStalePrice() external { revert StalePrice(); }
    function triggerPaymentTokenNotSupported() external { revert PaymentTokenNotSupported(); }
    function triggerPriceNotSet() external { revert PriceNotSet(); }
    function triggerInvalidServiceName() external { revert InvalidServiceName(); }
}
