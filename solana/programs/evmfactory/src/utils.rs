use anchor_lang::prelude::*;
use anchor_lang::solana_program::{
    ed25519_program::instruction::new_ed25519_instruction,
    keccak,
    program::invoke,
};
use anchor_spl::token::spl_token;

use crate::errors::EvmFactoryError;

pub fn verify_author_signature(
    expected_signer: &Pubkey,
    message: &[u8],
    signature: &[u8; 64],
) -> Result<()> {
    let signer_bytes = expected_signer.to_bytes();
    let ix = new_ed25519_instruction(&signer_bytes, message, signature);

    invoke(&ix, &[]).map_err(|_| EvmFactoryError::InvalidOffchainSignature.into())
}

pub fn derive_offchain_hash(payload: &[u8]) -> [u8; 32] {
    let hashed = keccak::hash(payload);
    hashed.0
}

pub fn compute_fee(amount: u64, fee_bps: u16) -> Result<u64> {
    if fee_bps == 0 {
        return Ok(0);
    }

    let numerator = (amount as u128)
        .checked_mul(fee_bps as u128)
        .ok_or(EvmFactoryError::MathOverflow)?;
    Ok((numerator / 10_000) as u64)
}

pub fn is_native_mint(mint: &Pubkey) -> bool {
    *mint == spl_token::native_mint::ID
}
