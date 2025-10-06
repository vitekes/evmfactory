import { AnchorProvider, BN, Program, web3 } from "@coral-xyz/anchor";

export interface ListingPayload {
  listingSeed: Uint8Array;
  offchainHash: Uint8Array;
  priceLamports: BN;
  mint: web3.PublicKey;
  sellerSignature: Uint8Array;
}

export interface ListingAccounts {
  authority: web3.PublicKey;
  config: web3.PublicKey;
  treasury: web3.PublicKey;
  whitelist: web3.PublicKey;
  seller: web3.PublicKey;
  listing: web3.PublicKey;
  systemProgram?: web3.PublicKey;
}

export async function createListingInstruction(
  program: Program<any>,
  accounts: ListingAccounts,
  payload: ListingPayload,
  remainingAccounts: web3.AccountMeta[] = [],
) {
  let builder = program.methods
    .createListing({
      listingSeed: Array.from(payload.listingSeed),
      offchainHash: Array.from(payload.offchainHash),
      priceLamports: payload.priceLamports,
      mint: payload.mint,
      sellerSignature: Array.from(payload.sellerSignature),
    })
    .accounts({
      authority: accounts.authority,
      config: accounts.config,
      treasury: accounts.treasury,
      whitelist: accounts.whitelist,
      seller: accounts.seller,
      listing: accounts.listing,
      systemProgram: accounts.systemProgram ?? web3.SystemProgram.programId,
    });

  if (remainingAccounts.length > 0) {
    builder = builder.remainingAccounts(remainingAccounts);
  }

  return builder.instruction();
}

export function getProvider(): AnchorProvider {
  const provider = AnchorProvider.env();
  AnchorProvider.setProvider(provider);
  return provider;
}
