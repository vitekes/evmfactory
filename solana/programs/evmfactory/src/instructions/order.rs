use anchor_lang::prelude::*;
use anchor_lang::solana_program::{program::invoke, system_instruction};
use anchor_spl::token::{self, CloseAccount, TokenAccount, Transfer};

use crate::errors::EvmFactoryError;
use crate::state::{
    ListingAccount,
    MarketplaceConfig,
    OrderAccount,
    VaultAccount,
    CONFIG_SEED,
    LISTING_SEED,
    ORDER_SEED,
};
use crate::utils::{compute_fee, is_native_mint};

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Debug)]
pub struct PurchaseListingParams {
    pub expected_price: u64,
}

#[derive(Accounts)]
pub struct PurchaseListing<'info> {
    #[account(mut)]
    pub buyer: Signer<'info>,
    #[account(
        mut,
        seeds = [LISTING_SEED, listing.seller.as_ref(), &listing.listing_seed],
        bump = listing.bump,
        constraint listing.active @ EvmFactoryError::ListingNotActive,
    )]
    pub listing: Account<'info, ListingAccount>,
    #[account(
        mut,
        seeds = [CONFIG_SEED],
        bump = config.bump,
        has_one = treasury,
    )]
    pub config: Account<'info, MarketplaceConfig>,
    #[account(mut, address = config.treasury)]
    pub treasury: Account<'info, VaultAccount>,
    #[account(
        init,
        payer = buyer,
        space = 8 + OrderAccount::LEN,
        seeds = [ORDER_SEED, listing.key().as_ref(), buyer.key().as_ref()],
        bump,
    )]
    pub order: Account<'info, OrderAccount>,
    #[account(mut, address = listing.seller)]
    pub seller_destination: SystemAccount<'info>,
    pub system_program: Program<'info, System>,
}

pub fn purchase_listing(ctx: Context<PurchaseListing>, params: PurchaseListingParams) -> Result<()> {
    let listing = &mut ctx.accounts.listing;
    require_eq!(listing.price_lamports, params.expected_price, EvmFactoryError::PriceMismatch);

    if is_native_mint(&listing.mint) {
        let transfer_ix = system_instruction::transfer(
            &ctx.accounts.buyer.key(),
            &ctx.accounts.order.key(),
            listing.price_lamports,
        );
        invoke(
            &transfer_ix,
            &[
                ctx.accounts.buyer.to_account_info(),
                ctx.accounts.order.to_account_info(),
                ctx.accounts.system_program.to_account_info(),
            ],
        )?;
    } else {
        handle_spl_purchase(&ctx, listing.price_lamports)?;
    }

    let order = &mut ctx.accounts.order;
    order.buyer = ctx.accounts.buyer.key();
    order.seller = listing.seller;
    order.listing = listing.key();
    order.mint = listing.mint;
    order.amount_paid = listing.price_lamports;
    order.settled = false;
    order.bump = *ctx.bumps.get("order").unwrap_or(&0);

    listing.active = false;

    Ok(())
}

#[derive(Accounts)]
pub struct FinalizeOrder<'info> {
    #[account(mut)]
    pub authority: Signer<'info>,
    #[account(
        mut,
        seeds = [CONFIG_SEED],
        bump = config.bump,
        has_one = authority,
        has_one = treasury,
    )]
    pub config: Account<'info, MarketplaceConfig>,
    #[account(mut, address = config.treasury)]
    pub treasury: Account<'info, VaultAccount>,
    #[account(
        mut,
        seeds = [ORDER_SEED, order.listing.as_ref(), order.buyer.as_ref()],
        bump = order.bump,
        constraint !order.settled @ EvmFactoryError::OrderAlreadySettled,
        close = buyer,
    )]
    pub order: Account<'info, OrderAccount>,
    #[account(mut, address = order.buyer)]
    pub buyer: SystemAccount<'info>,
    #[account(mut, address = order.seller)]
    pub seller_destination: SystemAccount<'info>,
}

pub fn finalize_order(ctx: Context<FinalizeOrder>) -> Result<()> {
    let order = &mut ctx.accounts.order;
    let config = &ctx.accounts.config;

    let fee_amount = compute_fee(order.amount_paid, config.fee_bps)?;
    let seller_amount = order
        .amount_paid
        .checked_sub(fee_amount)
        .ok_or(EvmFactoryError::MathOverflow)?;

    if is_native_mint(&order.mint) {
        let order_ai = ctx.accounts.order.to_account_info();
        let treasury_ai = ctx.accounts.treasury.to_account_info();
        let seller_ai = ctx.accounts.seller_destination.to_account_info();

        let escrow_balance = order_ai.lamports();
        require!(escrow_balance >= order.amount_paid, EvmFactoryError::EscrowBalanceTooLow);

        **order_ai.try_borrow_mut_lamports()? -= order.amount_paid;
        **treasury_ai.try_borrow_mut_lamports()? += fee_amount;
        **seller_ai.try_borrow_mut_lamports()? += seller_amount;
    } else {
        handle_spl_finalize(&ctx, seller_amount, fee_amount)?;
    }

    order.settled = true;

    Ok(())
}

fn handle_spl_purchase(ctx: &Context<PurchaseListing>, amount: u64) -> Result<()> {
    // remaining_accounts: [mint, buyer ATA, order ATA, seller ATA, treasury ATA, token_program]
    let accounts = ctx.remaining_accounts;
    require!(accounts.len() >= 6, EvmFactoryError::MissingTokenAccounts);

    let mint_ai = &accounts[0];
    require_keys_eq!(
        mint_ai.key(),
        ctx.accounts.listing.mint,
        EvmFactoryError::TokenAccountMintMismatch,
    );

    let buyer_token_ai = &accounts[1];
    let order_token_ai = &accounts[2];
    let seller_token_ai = &accounts[3];
    let treasury_token_ai = &accounts[4];
    let token_program_ai = &accounts[5];

    require_keys_eq!(token_program_ai.key(), token::ID, EvmFactoryError::InvalidTokenProgram);

    validate_token_account(
        buyer_token_ai,
        &ctx.accounts.listing.mint,
        &ctx.accounts.buyer.key(),
    )?;
    validate_token_account(
        order_token_ai,
        &ctx.accounts.listing.mint,
        &ctx.accounts.order.key(),
    )?;
    validate_token_account(
        seller_token_ai,
        &ctx.accounts.listing.mint,
        &ctx.accounts.listing.seller,
    )?;
    validate_token_account(
        treasury_token_ai,
        &ctx.accounts.listing.mint,
        &ctx.accounts.config.treasury,
    )?;

    token::transfer(
        CpiContext::new(
            token_program_ai.clone(),
            Transfer {
                from: buyer_token_ai.clone(),
                to: order_token_ai.clone(),
                authority: ctx.accounts.buyer.to_account_info(),
            },
        ),
        amount,
    )?;

    Ok(())
}

fn handle_spl_finalize(ctx: &Context<FinalizeOrder>, seller_amount: u64, fee_amount: u64) -> Result<()> {
    // remaining_accounts: [mint, order ATA, seller ATA, treasury ATA, token_program]
    let accounts = ctx.remaining_accounts;
    require!(accounts.len() >= 5, EvmFactoryError::MissingTokenAccounts);

    let mint_ai = &accounts[0];
    require_keys_eq!(mint_ai.key(), ctx.accounts.order.mint, EvmFactoryError::TokenAccountMintMismatch);

    let order_token_ai = &accounts[1];
    let seller_token_ai = &accounts[2];
    let treasury_token_ai = &accounts[3];
    let token_program_ai = &accounts[4];

    require_keys_eq!(token_program_ai.key(), token::ID, EvmFactoryError::InvalidTokenProgram);

    validate_token_account(
        order_token_ai,
        &ctx.accounts.order.mint,
        &ctx.accounts.order.key(),
    )?;
    validate_token_account(
        seller_token_ai,
        &ctx.accounts.order.mint,
        &ctx.accounts.order.seller,
    )?;
    validate_token_account(
        treasury_token_ai,
        &ctx.accounts.order.mint,
        &ctx.accounts.config.treasury,
    )?;

    let order_token_state = Account::<TokenAccount>::try_from(order_token_ai)?;
    let escrow_balance = order_token_state.amount;
    drop(order_token_state);

    require!(
        escrow_balance >= seller_amount + fee_amount,
        EvmFactoryError::EscrowBalanceTooLow
    );

    let signer_seeds: &[&[u8]] = &[
        ORDER_SEED,
        ctx.accounts.order.listing.as_ref(),
        ctx.accounts.order.buyer.as_ref(),
        &[ctx.accounts.order.bump],
    ];

    if seller_amount > 0 {
        token::transfer(
            CpiContext::new_with_signer(
                token_program_ai.clone(),
                Transfer {
                    from: order_token_ai.clone(),
                    to: seller_token_ai.clone(),
                    authority: ctx.accounts.order.to_account_info(),
                },
                &[signer_seeds],
            ),
            seller_amount,
        )?;
    }

    if fee_amount > 0 {
        token::transfer(
            CpiContext::new_with_signer(
                token_program_ai.clone(),
                Transfer {
                    from: order_token_ai.clone(),
                    to: treasury_token_ai.clone(),
                    authority: ctx.accounts.order.to_account_info(),
                },
                &[signer_seeds],
            ),
            fee_amount,
        )?;
    }

    token::close_account(
        CpiContext::new_with_signer(
            token_program_ai.clone(),
            CloseAccount {
                account: order_token_ai.clone(),
                destination: ctx.accounts.buyer.to_account_info(),
                authority: ctx.accounts.order.to_account_info(),
            },
            &[signer_seeds],
        ),
    )?;

    Ok(())
}

fn validate_token_account(
    account_info: &AccountInfo,
    expected_mint: &Pubkey,
    expected_owner: &Pubkey,
) -> Result<()> {
    let token_account = Account::<TokenAccount>::try_from(account_info)?;
    require_keys_eq!(token_account.mint, *expected_mint, EvmFactoryError::TokenAccountMintMismatch);
    require_keys_eq!(token_account.owner, *expected_owner, EvmFactoryError::TokenAccountOwnerMismatch);
    Ok(())
}
