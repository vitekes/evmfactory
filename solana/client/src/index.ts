import { web3, Program, AnchorProvider } from "@project-serum/anchor";

export interface ListingPayload {
  listingSeed: Uint8Array;
  offchainHash: Uint8Array;
  priceLamports: bigint;
  mint: web3.PublicKey;
}

export async function createListingInstruction(
  program: Program,
  accounts: {
    authority: web3.PublicKey;
    config: web3.PublicKey;
    treasury: web3.PublicKey;
    seller: web3.PublicKey;
  },
  payload: ListingPayload,
) {
  return program.methods
    .createListing({
      listingSeed: Array.from(payload.listingSeed),
      offchainHash: Array.from(payload.offchainHash),
      priceLamports: payload.priceLamports,
      mint: payload.mint,
    })
    .accounts({
      authority: accounts.authority,
      config: accounts.config,
      treasury: accounts.treasury,
      seller: accounts.seller,
    })
    .instruction();
}

export function getProvider(): AnchorProvider {
  const provider = AnchorProvider.env();
  AnchorProvider.setProvider(provider);
  return provider;
}
