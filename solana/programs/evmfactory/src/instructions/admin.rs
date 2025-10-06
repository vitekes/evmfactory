use anchor_lang::prelude::*;
use anchor_lang::solana_program::rent::Rent;
use anchor_spl::token::{self, Mint, Token, TokenAccount, Transfer};

use crate::errors::EvmFactoryError;
use crate::state::{
    MarketplaceConfig,
    TokenWhitelist,
    VaultAccount,
    CONFIG_SEED,
    REWARD_VAULT_SEED,
    TOKEN_WHITELIST_SEED,
    TREASURY_VAULT_SEED,
};

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Debug)]
pub struct InitializeConfigParams {
    pub fee_bps: u16,
}

#[derive(Accounts)]
pub struct InitializeConfig<'info> {
    #[account(mut)]
    pub authority: Signer<'info>,
    #[account(
        init,
        payer = authority,
        space = 8 + MarketplaceConfig::LEN,
        seeds = [CONFIG_SEED],
        bump,
    )]
    pub config: Account<'info, MarketplaceConfig>,
    #[account(
        init,
        payer = authority,
        space = 8 + VaultAccount::LEN,
        seeds = [TREASURY_VAULT_SEED],
        bump,
    )]
    pub treasury_vault: Account<'info, VaultAccount>,
    #[account(
        init,
        payer = authority,
        space = 8 + VaultAccount::LEN,
        seeds = [REWARD_VAULT_SEED],
        bump,
    )]
    pub reward_vault: Account<'info, VaultAccount>,
    #[account(
        init,
        payer = authority,
        space = 8 + TokenWhitelist::len(),
        seeds = [TOKEN_WHITELIST_SEED],
        bump,
    )]
    pub token_whitelist: Account<'info, TokenWhitelist>,
    pub system_program: Program<'info, System>,
}

pub fn initialize_config(ctx: Context<InitializeConfig>, params: InitializeConfigParams) -> Result<()> {
    require!(params.fee_bps <= 10_000, EvmFactoryError::InvalidFeeBps);

    let config = &mut ctx.accounts.config;
    config.authority = ctx.accounts.authority.key();
    config.treasury = ctx.accounts.treasury_vault.key();
    config.reward_vault = ctx.accounts.reward_vault.key();
    config.whitelist = ctx.accounts.token_whitelist.key();
    config.fee_bps = params.fee_bps;
    config.bump = *ctx.bumps.get("config").unwrap_or(&0);

    ctx.accounts.treasury_vault.bump = *ctx.bumps.get("treasury_vault").unwrap_or(&0);
    ctx.accounts.reward_vault.bump = *ctx.bumps.get("reward_vault").unwrap_or(&0);
    ctx.accounts.token_whitelist.bump = *ctx.bumps.get("token_whitelist").unwrap_or(&0);
    ctx.accounts.token_whitelist.authority = ctx.accounts.authority.key();
    ctx.accounts.token_whitelist.allowed_mints = vec![];

    Ok(())
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Debug)]
pub struct AdminConfigInput {
    pub fee_bps: u16,
    pub treasury: Pubkey,
    pub reward_vault: Pubkey,
}

#[derive(Accounts)]
pub struct SetAdminConfig<'info> {
    #[account(mut)]
    pub authority: Signer<'info>,
    #[account(
        mut,
        seeds = [CONFIG_SEED],
        bump = config.bump,
        has_one = authority,
    )]
    pub config: Account<'info, MarketplaceConfig>,
}

pub fn set_admin_config(ctx: Context<SetAdminConfig>, input: AdminConfigInput) -> Result<()> {
    require!(input.fee_bps <= 10_000, EvmFactoryError::InvalidFeeBps);

    let config = &mut ctx.accounts.config;
    config.fee_bps = input.fee_bps;
    config.treasury = input.treasury;
    config.reward_vault = input.reward_vault;
    Ok(())
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Debug)]
pub struct UpdateWhitelistParams {
    pub mint: Pubkey,
    pub add: bool,
}

#[derive(Accounts)]
pub struct UpdateWhitelist<'info> {
    #[account(mut)]
    pub authority: Signer<'info>,
    #[account(
        mut,
        seeds = [TOKEN_WHITELIST_SEED],
        bump = whitelist.bump,
        has_one = authority,
    )]
    pub whitelist: Account<'info, TokenWhitelist>,
}

pub fn update_whitelist(ctx: Context<UpdateWhitelist>, params: UpdateWhitelistParams) -> Result<()> {
    let whitelist = &mut ctx.accounts.whitelist;
    if params.add {
        require!(
            !whitelist.allowed_mints.contains(&params.mint),
            EvmFactoryError::TokenAlreadyWhitelisted
        );
        require!(
            whitelist.allowed_mints.len() < TokenWhitelist::MAX_MINTS,
            EvmFactoryError::WhitelistFull
        );
        whitelist.allowed_mints.push(params.mint);
    } else {
        whitelist.allowed_mints.retain(|m| m != &params.mint);
    }
    Ok(())
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Debug)]
pub struct WithdrawNativeParams {
    pub amount: u64,
}

#[derive(Accounts)]
pub struct WithdrawTreasuryNative<'info> {
    #[account(mut)]
    pub authority: Signer<'info>,
    #[account(
        mut,
        seeds = [CONFIG_SEED],
        bump = config.bump,
        has_one = authority,
    )]
    pub config: Account<'info, MarketplaceConfig>,
    #[account(
        mut,
        seeds = [TREASURY_VAULT_SEED],
        bump = treasury_vault.bump,
        address = config.treasury,
    )]
    pub treasury_vault: Account<'info, VaultAccount>,
    #[account(mut)]
    pub destination: SystemAccount<'info>,
}

pub fn withdraw_treasury_native(ctx: Context<WithdrawTreasuryNative>, params: WithdrawNativeParams) -> Result<()> {
    require!(params.amount > 0, EvmFactoryError::AmountMustBePositive);

    let source = ctx.accounts.treasury_vault.to_account_info();
    require!(source.lamports() >= params.amount, EvmFactoryError::EscrowBalanceTooLow);

    let rent_exempt_minimum = Rent::get()?.minimum_balance(VaultAccount::LEN + 8);
    let remaining = source
        .lamports()
        .checked_sub(params.amount)
        .ok_or(EvmFactoryError::EscrowBalanceTooLow)?;
    require!(remaining >= rent_exempt_minimum, EvmFactoryError::RentExemptionViolation);

    **source.try_borrow_mut_lamports()? -= params.amount;
    **ctx
        .accounts
        .destination
        .to_account_info()
        .try_borrow_mut_lamports()? += params.amount;

    Ok(())
}

#[derive(Accounts)]
pub struct WithdrawRewardNative<'info> {
    #[account(mut)]
    pub authority: Signer<'info>,
    #[account(
        mut,
        seeds = [CONFIG_SEED],
        bump = config.bump,
        has_one = authority,
    )]
    pub config: Account<'info, MarketplaceConfig>,
    #[account(
        mut,
        seeds = [REWARD_VAULT_SEED],
        bump = reward_vault.bump,
        address = config.reward_vault,
    )]
    pub reward_vault: Account<'info, VaultAccount>,
    #[account(mut)]
    pub destination: SystemAccount<'info>,
}

pub fn withdraw_reward_native(ctx: Context<WithdrawRewardNative>, params: WithdrawNativeParams) -> Result<()> {
    require!(params.amount > 0, EvmFactoryError::AmountMustBePositive);

    let source = ctx.accounts.reward_vault.to_account_info();
    require!(source.lamports() >= params.amount, EvmFactoryError::EscrowBalanceTooLow);

    let rent_exempt_minimum = Rent::get()?.minimum_balance(VaultAccount::LEN + 8);
    let remaining = source
        .lamports()
        .checked_sub(params.amount)
        .ok_or(EvmFactoryError::EscrowBalanceTooLow)?;
    require!(remaining >= rent_exempt_minimum, EvmFactoryError::RentExemptionViolation);

    **source.try_borrow_mut_lamports()? -= params.amount;
    **ctx
        .accounts
        .destination
        .to_account_info()
        .try_borrow_mut_lamports()? += params.amount;

    Ok(())
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Debug)]
pub struct WithdrawSplParams {
    pub amount: u64,
}

#[derive(Accounts)]
pub struct WithdrawTreasurySpl<'info> {
    #[account(mut)]
    pub authority: Signer<'info>,
    #[account(
        mut,
        seeds = [CONFIG_SEED],
        bump = config.bump,
        has_one = authority,
    )]
    pub config: Account<'info, MarketplaceConfig>,
    #[account(
        mut,
        seeds = [TREASURY_VAULT_SEED],
        bump = treasury_vault.bump,
        address = config.treasury,
    )]
    pub treasury_vault: Account<'info, VaultAccount>,
    pub mint: Account<'info, Mint>,
    #[account(
        mut,
        constraint = treasury_token_account.owner == config.treasury @ EvmFactoryError::TokenAccountOwnerMismatch,
        constraint = treasury_token_account.mint == mint.key() @ EvmFactoryError::TokenAccountMintMismatch,
    )]
    pub treasury_token_account: Account<'info, TokenAccount>,
    #[account(
        mut,
        constraint = destination_token_account.mint == mint.key() @ EvmFactoryError::TokenAccountMintMismatch,
    )]
    pub destination_token_account: Account<'info, TokenAccount>,
    pub token_program: Program<'info, Token>,
}

pub fn withdraw_treasury_spl(ctx: Context<WithdrawTreasurySpl>, params: WithdrawSplParams) -> Result<()> {
    require!(params.amount > 0, EvmFactoryError::AmountMustBePositive);
    require!(
        ctx.accounts.treasury_token_account.amount >= params.amount,
        EvmFactoryError::EscrowBalanceTooLow
    );

    let seeds: &[&[u8]] = &[TREASURY_VAULT_SEED, &[ctx.accounts.treasury_vault.bump]];

    token::transfer(
        CpiContext::new_with_signer(
            ctx.accounts.token_program.to_account_info(),
            Transfer {
                from: ctx.accounts.treasury_token_account.to_account_info(),
                to: ctx.accounts.destination_token_account.to_account_info(),
                authority: ctx.accounts.treasury_vault.to_account_info(),
            },
            &[seeds],
        ),
        params.amount,
    )?;

    Ok(())
}

#[derive(Accounts)]
pub struct WithdrawRewardSpl<'info> {
    #[account(mut)]
    pub authority: Signer<'info>,
    #[account(
        mut,
        seeds = [CONFIG_SEED],
        bump = config.bump,
        has_one = authority,
    )]
    pub config: Account<'info, MarketplaceConfig>,
    #[account(
        mut,
        seeds = [REWARD_VAULT_SEED],
        bump = reward_vault.bump,
        address = config.reward_vault,
    )]
    pub reward_vault: Account<'info, VaultAccount>,
    pub mint: Account<'info, Mint>,
    #[account(
        mut,
        constraint = reward_token_account.owner == config.reward_vault @ EvmFactoryError::TokenAccountOwnerMismatch,
        constraint = reward_token_account.mint == mint.key() @ EvmFactoryError::TokenAccountMintMismatch,
    )]
    pub reward_token_account: Account<'info, TokenAccount>,
    #[account(
        mut,
        constraint = destination_token_account.mint == mint.key() @ EvmFactoryError::TokenAccountMintMismatch,
    )]
    pub destination_token_account: Account<'info, TokenAccount>,
    pub token_program: Program<'info, Token>,
}

pub fn withdraw_reward_spl(ctx: Context<WithdrawRewardSpl>, params: WithdrawSplParams) -> Result<()> {
    require!(params.amount > 0, EvmFactoryError::AmountMustBePositive);
    require!(
        ctx.accounts.reward_token_account.amount >= params.amount,
        EvmFactoryError::EscrowBalanceTooLow
    );

    let seeds: &[&[u8]] = &[REWARD_VAULT_SEED, &[ctx.accounts.reward_vault.bump]];

    token::transfer(
        CpiContext::new_with_signer(
            ctx.accounts.token_program.to_account_info(),
            Transfer {
                from: ctx.accounts.reward_token_account.to_account_info(),
                to: ctx.accounts.destination_token_account.to_account_info(),
                authority: ctx.accounts.reward_vault.to_account_info(),
            },
            &[seeds],
        ),
        params.amount,
    )?;

    Ok(())
}
