use anchor_lang::prelude::*;

use crate::errors::EvmFactoryError;
use crate::state::{
    ContestAccount,
    ContestEntryAccount,
    MarketplaceConfig,
    VaultAccount,
    CONTEST_ENTRY_SEED,
    CONTEST_SEED,
    CONFIG_SEED,
};

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Debug)]
pub struct CreateContestParams {
    pub contest_seed: [u8; 32],
    pub offchain_hash: [u8; 32],
    pub deadline: i64,
    pub prize_lamports: u64,
}

#[derive(Accounts)]
#[instruction(params: CreateContestParams)]
pub struct CreateContest<'info> {
    #[account(mut)]
    pub creator: Signer<'info>,
    #[account(
        mut,
        seeds = [CONFIG_SEED],
        bump = config.bump,
        has_one = reward_vault,
    )]
    pub config: Account<'info, MarketplaceConfig>,
    #[account(mut, address = config.reward_vault)]
    pub reward_vault: Account<'info, VaultAccount>,
    #[account(
        init,
        payer = creator,
        space = 8 + ContestAccount::LEN,
        seeds = [CONTEST_SEED, creator.key().as_ref(), &params.contest_seed],
        bump,
    )]
    pub contest: Account<'info, ContestAccount>,
    pub system_program: Program<'info, System>,
}

pub fn create_contest(ctx: Context<CreateContest>, params: CreateContestParams) -> Result<()> {
    require!(params.prize_lamports > 0, EvmFactoryError::InvalidPrizeAmount);
    let now = Clock::get()?.unix_timestamp;
    require!(params.deadline > now, EvmFactoryError::ContestDeadlinePassed);

    let reward_ai = ctx.accounts.reward_vault.to_account_info();
    let contest_ai = ctx.accounts.contest.to_account_info();
    let reward_balance = reward_ai.lamports();
    require!(reward_balance >= params.prize_lamports, EvmFactoryError::EscrowBalanceTooLow);

    **reward_ai.try_borrow_mut_lamports()? -= params.prize_lamports;
    **contest_ai.try_borrow_mut_lamports()? += params.prize_lamports;

    let contest = &mut ctx.accounts.contest;
    contest.creator = ctx.accounts.creator.key();
    contest.reward_pool = ctx.accounts.reward_vault.key();
    contest.deadline = params.deadline;
    contest.contest_seed = params.contest_seed;
    contest.offchain_hash = params.offchain_hash;
    contest.prize_lamports = params.prize_lamports;
    contest.settled = false;
    contest.bump = *ctx.bumps.get("contest").unwrap_or(&0);

    Ok(())
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Debug)]
pub struct SubmitContestEntryParams {
    pub contest_seed: [u8; 32],
    pub entry_seed: [u8; 32],
    pub offchain_hash: [u8; 32],
}

#[derive(Accounts)]
#[instruction(params: SubmitContestEntryParams)]
pub struct SubmitContestEntry<'info> {
    #[account(mut)]
    pub contestant: Signer<'info>,
    #[account(
        mut,
        seeds = [CONTEST_SEED, contest.creator.as_ref(), &params.contest_seed],
        bump = contest.bump,
        constraint !contest.settled @ EvmFactoryError::ContestResolved,
    )]
    pub contest: Account<'info, ContestAccount>,
    #[account(
        init,
        payer = contestant,
        space = 8 + ContestEntryAccount::LEN,
        seeds = [CONTEST_ENTRY_SEED, contest.key().as_ref(), &params.entry_seed],
        bump,
    )]
    pub entry: Account<'info, ContestEntryAccount>,
    pub system_program: Program<'info, System>,
}

pub fn submit_contest_entry(ctx: Context<SubmitContestEntry>, params: SubmitContestEntryParams) -> Result<()> {
    let now = Clock::get()?.unix_timestamp;
    require!(now <= ctx.accounts.contest.deadline, EvmFactoryError::ContestDeadlinePassed);

    let entry = &mut ctx.accounts.entry;
    entry.contestant = ctx.accounts.contestant.key();
    entry.contest = ctx.accounts.contest.key();
    entry.entry_seed = params.entry_seed;
    entry.offchain_hash = params.offchain_hash;
    entry.score = 0;
    entry.bump = *ctx.bumps.get("entry").unwrap_or(&0);
    Ok(())
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Debug)]
pub struct ResolveContestParams {
    pub contest_seed: [u8; 32],
    pub entry_seed: [u8; 32],
    pub winner: Pubkey,
    pub score: u64,
}

#[derive(Accounts)]
#[instruction(params: ResolveContestParams)]
pub struct ResolveContest<'info> {
    #[account(mut)]
    pub authority: Signer<'info>,
    #[account(
        mut,
        seeds = [CONFIG_SEED],
        bump = config.bump,
        has_one = authority,
        has_one = reward_vault,
    )]
    pub config: Account<'info, MarketplaceConfig>,
    #[account(mut, address = config.reward_vault)]
    pub reward_vault: Account<'info, VaultAccount>,
    #[account(
        mut,
        seeds = [CONTEST_SEED, contest.creator.as_ref(), &params.contest_seed],
        bump = contest.bump,
        constraint !contest.settled @ EvmFactoryError::ContestResolved,
        close = reward_vault,
    )]
    pub contest: Account<'info, ContestAccount>,
    #[account(
        mut,
        seeds = [CONTEST_ENTRY_SEED, contest.key().as_ref(), &params.entry_seed],
        bump = entry.bump,
    )]
    pub entry: Account<'info, ContestEntryAccount>,
    #[account(mut)]
    pub reward_destination: SystemAccount<'info>,
}

pub fn resolve_contest(ctx: Context<ResolveContest>, params: ResolveContestParams) -> Result<()> {
    let now = Clock::get()?.unix_timestamp;
    require!(now >= ctx.accounts.contest.deadline, EvmFactoryError::ContestDeadlineNotReached);
    require!(params.winner == ctx.accounts.reward_destination.key(), EvmFactoryError::WinnerAccountMismatch);
    require!(params.winner == ctx.accounts.entry.contestant, EvmFactoryError::WinnerAccountMismatch);

    let contest_ai = ctx.accounts.contest.to_account_info();
    let winner_ai = ctx.accounts.reward_destination.to_account_info();
    let prize = ctx.accounts.contest.prize_lamports;
    require!(prize > 0, EvmFactoryError::InvalidPrizeAmount);
    let contest_balance = contest_ai.lamports();
    require!(contest_balance >= prize, EvmFactoryError::EscrowBalanceTooLow);

    **contest_ai.try_borrow_mut_lamports()? -= prize;
    **winner_ai.try_borrow_mut_lamports()? += prize;

    let contest = &mut ctx.accounts.contest;
    contest.prize_lamports = 0;
    contest.settled = true;

    let entry = &mut ctx.accounts.entry;
    entry.score = params.score;

    Ok(())
}
