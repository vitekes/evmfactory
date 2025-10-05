use anchor_lang::prelude::*;

pub const CONFIG_SEED: &[u8] = b"config";
pub const LISTING_SEED: &[u8] = b"listing";
pub const ORDER_SEED: &[u8] = b"order";
pub const ORDER_VAULT_SEED: &[u8] = b"order_vault";
pub const SUBSCRIPTION_PLAN_SEED: &[u8] = b"sub_plan";
pub const SUBSCRIPTION_INSTANCE_SEED: &[u8] = b"sub_instance";
pub const CONTEST_SEED: &[u8] = b"contest";
pub const CONTEST_ENTRY_SEED: &[u8] = b"contest_entry";
pub const TREASURY_VAULT_SEED: &[u8] = b"treasury_vault";
pub const REWARD_VAULT_SEED: &[u8] = b"reward_vault";
pub const TOKEN_WHITELIST_SEED: &[u8] = b"token_whitelist";

#[account]
pub struct VaultAccount {
    pub bump: u8,
}

impl VaultAccount {
    pub const LEN: usize = 1;
}

#[account]
pub struct MarketplaceConfig {
    pub authority: Pubkey,
    pub treasury: Pubkey,
    pub fee_bps: u16,
    pub reward_vault: Pubkey,
    pub whitelist: Pubkey,
    pub bump: u8,
}

impl MarketplaceConfig {
    pub const LEN: usize = 32 + 32 + 2 + 32 + 32 + 1;
}

#[account]
pub struct TokenWhitelist {
    pub authority: Pubkey,
    pub allowed_mints: Vec<Pubkey>,
    pub bump: u8,
}

impl TokenWhitelist {
    pub const MAX_MINTS: usize = 32;
    pub fn len() -> usize {
        32 + 4 + (TokenWhitelist::MAX_MINTS * 32) + 1
    }
}

#[account]
pub struct ListingAccount {
    pub seller: Pubkey,
    pub mint: Pubkey,
    pub price_lamports: u64,
    pub listing_seed: [u8; 32],
    pub offchain_hash: [u8; 32],
    pub active: bool,
    pub bump: u8,
}

impl ListingAccount {
    pub const LEN: usize = 32 + 32 + 8 + 32 + 32 + 1 + 1;
}

#[account]
pub struct OrderAccount {
    pub buyer: Pubkey,
    pub seller: Pubkey,
    pub listing: Pubkey,
    pub mint: Pubkey,
    pub amount_paid: u64,
    pub settled: bool,
    pub bump: u8,
}

impl OrderAccount {
    pub const LEN: usize = 32 + 32 + 32 + 32 + 8 + 1 + 1;
}

#[account]
pub struct SubscriptionPlanAccount {
    pub creator: Pubkey,
    pub mint: Pubkey,
    pub price_per_period: u64,
    pub period_seconds: i64,
    pub plan_seed: [u8; 32],
    pub offchain_hash: [u8; 32],
    pub active: bool,
    pub bump: u8,
}

impl SubscriptionPlanAccount {
    pub const LEN: usize = 32 + 32 + 8 + 8 + 32 + 32 + 1 + 1;
}

#[account]
pub struct SubscriptionInstanceAccount {
    pub subscriber: Pubkey,
    pub plan: Pubkey,
    pub instance_seed: [u8; 32],
    pub last_payment_at: i64,
    pub bump: u8,
}

impl SubscriptionInstanceAccount {
    pub const LEN: usize = 32 + 32 + 32 + 8 + 1;
}

#[account]
pub struct ContestAccount {
    pub creator: Pubkey,
    pub reward_pool: Pubkey,
    pub deadline: i64,
    pub contest_seed: [u8; 32],
    pub offchain_hash: [u8; 32],
    pub prize_lamports: u64,
    pub settled: bool,
    pub bump: u8,
}

impl ContestAccount {
    pub const LEN: usize = 32 + 32 + 8 + 32 + 32 + 8 + 1 + 1;
}

#[account]
pub struct ContestEntryAccount {
    pub contestant: Pubkey,
    pub contest: Pubkey,
    pub entry_seed: [u8; 32],
    pub offchain_hash: [u8; 32],
    pub score: u64,
    pub bump: u8,
}

impl ContestEntryAccount {
    pub const LEN: usize = 32 + 32 + 32 + 32 + 8 + 1;
}
