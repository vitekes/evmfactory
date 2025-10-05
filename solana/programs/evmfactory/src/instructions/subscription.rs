use anchor_lang::prelude::*;
use anchor_lang::solana_program::{program::invoke, system_instruction};
use anchor_spl::token::{self, TokenAccount, Transfer};

use crate::errors::EvmFactoryError;
use crate::state::{
    MarketplaceConfig,
    SubscriptionInstanceAccount,
    SubscriptionPlanAccount,
    TokenWhitelist,
    VaultAccount,
    CONFIG_SEED,
    SUBSCRIPTION_INSTANCE_SEED,
    SUBSCRIPTION_PLAN_SEED,
    TOKEN_WHITELIST_SEED,
};
use crate::utils::{compute_fee, is_native_mint};

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Debug)]
pub struct ConfigureSubscriptionParams {
    pub plan_seed: [u8; 32],
    pub offchain_hash: [u8; 32],
    pub price_per_period: u64,
    pub period_seconds: i64,
    pub mint: Pubkey,
}

#[derive(Accounts)]
#[instruction(params: ConfigureSubscriptionParams)]
pub struct ConfigureSubscription<'info> {
    #[account(mut)]
    pub creator: Signer<'info>,
    #[account(
        mut,
        seeds = [CONFIG_SEED],
        bump = config.bump,
        has_one = whitelist,
    )]
    pub config: Account<'info, MarketplaceConfig>,
    #[account(
        seeds = [TOKEN_WHITELIST_SEED],
        bump = whitelist.bump,
        address = config.whitelist,
    )]
    pub whitelist: Account<'info, TokenWhitelist>,
    #[account(
        init,
        payer = creator,
        space = 8 + SubscriptionPlanAccount::LEN,
        seeds = [SUBSCRIPTION_PLAN_SEED, creator.key().as_ref(), &params.plan_seed],
        bump,
    )]
    pub plan: Account<'info, SubscriptionPlanAccount>,
    pub system_program: Program<'info, System>,
}

pub fn configure_subscription(ctx: Context<ConfigureSubscription>, params: ConfigureSubscriptionParams) -> Result<()> {
    require!(params.period_seconds > 0, EvmFactoryError::MathOverflow);

    if !is_native_mint(&params.mint) {
        require!(
            ctx.accounts
                .whitelist
                .allowed_mints
                .contains(&params.mint),
            EvmFactoryError::TokenNotWhitelisted,
        );
    }

    let plan = &mut ctx.accounts.plan;
    plan.creator = ctx.accounts.creator.key();
    plan.mint = params.mint;
    plan.price_per_period = params.price_per_period;
    plan.period_seconds = params.period_seconds;
    plan.plan_seed = params.plan_seed;
    plan.offchain_hash = params.offchain_hash;
    plan.active = true;
    plan.bump = *ctx.bumps.get("plan").unwrap_or(&0);
    Ok(())
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Debug)]
pub struct ProcessSubscriptionPaymentParams {
    pub instance_seed: [u8; 32],
    pub now_ts: i64,
}

#[derive(Accounts)]
#[instruction(params: ProcessSubscriptionPaymentParams)]
pub struct ProcessSubscriptionPayment<'info> {
    #[account(mut)]
    pub subscriber: Signer<'info>,
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
        mut,
        seeds = [SUBSCRIPTION_PLAN_SEED, plan.creator.as_ref(), &plan.plan_seed],
        bump = plan.bump,
    )]
    pub plan: Account<'info, SubscriptionPlanAccount>,
    #[account(mut, address = plan.creator)]
    pub creator_destination: SystemAccount<'info>,
    #[account(
        init_if_needed,
        payer = subscriber,
        space = 8 + SubscriptionInstanceAccount::LEN,
        seeds = [SUBSCRIPTION_INSTANCE_SEED, subscriber.key().as_ref(), &params.instance_seed],
        bump,
    )]
    pub instance: Account<'info, SubscriptionInstanceAccount>,
    pub system_program: Program<'info, System>,
}

pub fn process_subscription_payment(
    ctx: Context<ProcessSubscriptionPayment>,
    params: ProcessSubscriptionPaymentParams,
) -> Result<()> {
    let plan = &ctx.accounts.plan;
    require!(plan.active, EvmFactoryError::SubscriptionInactive);

    let instance = &mut ctx.accounts.instance;
    if instance.last_payment_at != 0 {
        let next_due = instance
            .last_payment_at
            .checked_add(plan.period_seconds)
            .ok_or(EvmFactoryError::MathOverflow)?;
        require!(params.now_ts >= next_due, EvmFactoryError::SubscriptionPeriodNotReached);
    }

    let fee_amount = compute_fee(plan.price_per_period, ctx.accounts.config.fee_bps)?;
    let creator_amount = plan
        .price_per_period
        .checked_sub(fee_amount)
        .ok_or(EvmFactoryError::MathOverflow)?;

    if is_native_mint(&plan.mint) {
        if fee_amount > 0 {
            let fee_ix = system_instruction::transfer(
                &ctx.accounts.subscriber.key(),
                &ctx.accounts.treasury.key(),
                fee_amount,
            );
            invoke(
                &fee_ix,
                &[
                    ctx.accounts.subscriber.to_account_info(),
                    ctx.accounts.treasury.to_account_info(),
                    ctx.accounts.system_program.to_account_info(),
                ],
            )?;
        }

        if creator_amount > 0 {
            let payout_ix = system_instruction::transfer(
                &ctx.accounts.subscriber.key(),
                &ctx.accounts.creator_destination.key(),
                creator_amount,
            );
            invoke(
                &payout_ix,
                &[
                    ctx.accounts.subscriber.to_account_info(),
                    ctx.accounts.creator_destination.to_account_info(),
                    ctx.accounts.system_program.to_account_info(),
                ],
            )?;
        }
    } else {
        handle_spl_subscription(&ctx, fee_amount, creator_amount)?;
    }

    instance.subscriber = ctx.accounts.subscriber.key();
    instance.plan = plan.key();
    instance.instance_seed = params.instance_seed;
    instance.last_payment_at = params.now_ts;
    instance.bump = *ctx.bumps.get("instance").unwrap_or(&0);

    Ok(())
}

fn handle_spl_subscription(ctx: &Context<ProcessSubscriptionPayment>, fee_amount: u64, creator_amount: u64) -> Result<()> {
    // remaining_accounts: [subscriber ATA, creator ATA, treasury ATA, token_program]
    let accounts = ctx.remaining_accounts;
    require!(accounts.len() >= 4, EvmFactoryError::MissingTokenAccounts);

    let subscriber_token_ai = &accounts[0];
    let creator_token_ai = &accounts[1];
    let treasury_token_ai = &accounts[2];
    let token_program_ai = &accounts[3];

    validate_token_account(
        subscriber_token_ai,
        &ctx.accounts.plan.mint,
        &ctx.accounts.subscriber.key(),
    )?;
    validate_token_account(
        creator_token_ai,
        &ctx.accounts.plan.mint,
        &ctx.accounts.plan.creator,
    )?;
    validate_token_account(
        treasury_token_ai,
        &ctx.accounts.plan.mint,
        &ctx.accounts.config.treasury,
    )?;

    if fee_amount > 0 {
        token::transfer(
            CpiContext::new(
                token_program_ai.clone(),
                Transfer {
                    from: subscriber_token_ai.clone(),
                    to: treasury_token_ai.clone(),
                    authority: ctx.accounts.subscriber.to_account_info(),
                },
            ),
            fee_amount,
        )?;
    }

    if creator_amount > 0 {
        token::transfer(
            CpiContext::new(
                token_program_ai.clone(),
                Transfer {
                    from: subscriber_token_ai.clone(),
                    to: creator_token_ai.clone(),
                    authority: ctx.accounts.subscriber.to_account_info(),
                },
            ),
            creator_amount,
        )?;
    }

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
