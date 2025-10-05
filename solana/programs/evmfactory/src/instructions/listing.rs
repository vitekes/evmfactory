use anchor_lang::prelude::*;

use crate::errors::EvmFactoryError;
use crate::state::{
    ListingAccount,
    MarketplaceConfig,
    TokenWhitelist,
    VaultAccount,
    CONFIG_SEED,
    LISTING_SEED,
    TOKEN_WHITELIST_SEED,
};
use crate::utils::{is_native_mint, verify_author_signature};

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Debug)]
pub struct CreateListingParams {
    pub listing_seed: [u8; 32],
    pub offchain_hash: [u8; 32],
    pub price_lamports: u64,
    pub mint: Pubkey,
    pub seller_signature: [u8; 64],
}

#[derive(Accounts)]
#[instruction(params: CreateListingParams)]
pub struct CreateListing<'info> {
    #[account(mut)]
    pub authority: Signer<'info>,
    #[account(
        mut,
        seeds = [CONFIG_SEED],
        bump = config.bump,
        has_one = authority,
        has_one = treasury,
        has_one = whitelist,
    )]
    pub config: Account<'info, MarketplaceConfig>,
    #[account(mut, address = config.treasury)]
    pub treasury: Account<'info, VaultAccount>,
    #[account(
        seeds = [TOKEN_WHITELIST_SEED],
        bump = whitelist.bump,
        address = config.whitelist,
    )]
    pub whitelist: Account<'info, TokenWhitelist>,
    /// CHECK: seller signature can be validated off-chain using payload digest.
    pub seller: UncheckedAccount<'info>,
    #[account(
        init,
        payer = authority,
        space = 8 + ListingAccount::LEN,
        seeds = [LISTING_SEED, seller.key().as_ref(), &params.listing_seed],
        bump,
    )]
    pub listing: Account<'info, ListingAccount>,
    pub system_program: Program<'info, System>,
}

pub fn create_listing(ctx: Context<CreateListing>, params: CreateListingParams) -> Result<()> {
    verify_author_signature(
        &ctx.accounts.seller.key(),
        &params.offchain_hash,
        &params.seller_signature,
    )?;

    if !is_native_mint(&params.mint) {
        require!(
            ctx.accounts
                .whitelist
                .allowed_mints
                .contains(&params.mint),
            EvmFactoryError::TokenNotWhitelisted,
        );
    }

    let listing = &mut ctx.accounts.listing;
    listing.seller = ctx.accounts.seller.key();
    listing.mint = params.mint;
    listing.price_lamports = params.price_lamports;
    listing.listing_seed = params.listing_seed;
    listing.offchain_hash = params.offchain_hash;
    listing.active = true;
    listing.bump = *ctx.bumps.get("listing").unwrap_or(&0);
    Ok(())
}

#[derive(Accounts)]
pub struct CancelListing<'info> {
    #[account(mut)]
    pub seller: Signer<'info>,
    #[account(
        mut,
        seeds = [CONFIG_SEED],
        bump = config.bump,
        has_one = treasury,
    )]
    pub config: Account<'info, MarketplaceConfig>,
    #[account(
        mut,
        seeds = [LISTING_SEED, seller.key().as_ref(), &listing.listing_seed],
        bump = listing.bump,
        constraint listing.seller == seller.key() @ EvmFactoryError::InvalidAuthority,
        close = treasury,
    )]
    pub listing: Account<'info, ListingAccount>,
    #[account(mut, address = config.treasury)]
    pub treasury: Account<'info, VaultAccount>,
    pub system_program: Program<'info, System>,
}

pub fn cancel_listing(ctx: Context<CancelListing>) -> Result<()> {
    let listing = &mut ctx.accounts.listing;
    require!(listing.active, EvmFactoryError::ListingNotActive);
    listing.active = false;
    Ok(())
}
