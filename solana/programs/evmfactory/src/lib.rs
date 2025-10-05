use anchor_lang::prelude::*;

pub mod errors;
pub mod instructions;
pub mod state;
pub mod utils;

use instructions::*;

declare_id!("Evmmarket111111111111111111111111111111111");

#[program]
pub mod evmfactory {
    use super::*;

    pub fn initialize_config(ctx: Context<InitializeConfig>, params: InitializeConfigParams) -> Result<()> {
        admin::initialize_config(ctx, params)
    }

    pub fn set_admin_config(ctx: Context<SetAdminConfig>, config: AdminConfigInput) -> Result<()> {
        admin::set_admin_config(ctx, config)
    }

    pub fn update_whitelist(ctx: Context<UpdateWhitelist>, params: UpdateWhitelistParams) -> Result<()> {
        admin::update_whitelist(ctx, params)
    }

    pub fn withdraw_treasury_native(ctx: Context<WithdrawTreasuryNative>, params: WithdrawNativeParams) -> Result<()> {
        admin::withdraw_treasury_native(ctx, params)
    }

    pub fn withdraw_reward_native(ctx: Context<WithdrawRewardNative>, params: WithdrawNativeParams) -> Result<()> {
        admin::withdraw_reward_native(ctx, params)
    }

    pub fn withdraw_treasury_spl(ctx: Context<WithdrawTreasurySpl>, params: WithdrawSplParams) -> Result<()> {
        admin::withdraw_treasury_spl(ctx, params)
    }

    pub fn withdraw_reward_spl(ctx: Context<WithdrawRewardSpl>, params: WithdrawSplParams) -> Result<()> {
        admin::withdraw_reward_spl(ctx, params)
    }

    pub fn create_listing(ctx: Context<CreateListing>, params: CreateListingParams) -> Result<()> {
        listing::create_listing(ctx, params)
    }

    pub fn cancel_listing(ctx: Context<CancelListing>) -> Result<()> {
        listing::cancel_listing(ctx)
    }

    pub fn purchase_listing(ctx: Context<PurchaseListing>, params: PurchaseListingParams) -> Result<()> {
        order::purchase_listing(ctx, params)
    }

    pub fn finalize_order(ctx: Context<FinalizeOrder>) -> Result<()> {
        order::finalize_order(ctx)
    }

    pub fn configure_subscription(ctx: Context<ConfigureSubscription>, params: ConfigureSubscriptionParams) -> Result<()> {
        subscription::configure_subscription(ctx, params)
    }

    pub fn process_subscription_payment(
        ctx: Context<ProcessSubscriptionPayment>,
        params: ProcessSubscriptionPaymentParams,
    ) -> Result<()> {
        subscription::process_subscription_payment(ctx, params)
    }

    pub fn create_contest(ctx: Context<CreateContest>, params: CreateContestParams) -> Result<()> {
        contest::create_contest(ctx, params)
    }

    pub fn submit_contest_entry(ctx: Context<SubmitContestEntry>, params: SubmitContestEntryParams) -> Result<()> {
        contest::submit_contest_entry(ctx, params)
    }

    pub fn resolve_contest(ctx: Context<ResolveContest>, params: ResolveContestParams) -> Result<()> {
        contest::resolve_contest(ctx, params)
    }
}
