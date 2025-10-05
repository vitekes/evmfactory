use anchor_lang::prelude::*;

#[error_code]
pub enum EvmFactoryError {
    #[msg("Invalid marketplace authority")]
    InvalidAuthority,
    #[msg("Listing is not active")]
    ListingNotActive,
    #[msg("Order already settled")]
    OrderAlreadySettled,
    #[msg("Signature verification failed")]
    InvalidOffchainSignature,
    #[msg("Contest already resolved")]
    ContestResolved,
    #[msg("Subscription inactive")]
    SubscriptionInactive,
    #[msg("Payment period not reached")]
    SubscriptionPeriodNotReached,
    #[msg("Math overflow")]
    MathOverflow,
    #[msg("Listing price does not match expected value")]
    PriceMismatch,
    #[msg("Escrow balance too low")]
    EscrowBalanceTooLow,
    #[msg("Fee basis points must be <= 10000")]
    InvalidFeeBps,
    #[msg("Prizes must be positive")]
    InvalidPrizeAmount,
    #[msg("Contest deadline has not passed")]
    ContestDeadlineNotReached,
    #[msg("Contest deadline already passed")]
    ContestDeadlinePassed,
    #[msg("Winner account mismatch")]
    WinnerAccountMismatch,
    #[msg("Token mint not whitelisted")]
    TokenNotWhitelisted,
    #[msg("Token already in whitelist")]
    TokenAlreadyWhitelisted,
    #[msg("Whitelist is full")]
    WhitelistFull,
    #[msg("Missing token accounts for SPL payment flow")]
    MissingTokenAccounts,
    #[msg("Token account owner mismatch")]
    TokenAccountOwnerMismatch,
    #[msg("Token account mint mismatch")]
    TokenAccountMintMismatch,
    #[msg("Amount must be greater than zero")]
    AmountMustBePositive,
}
