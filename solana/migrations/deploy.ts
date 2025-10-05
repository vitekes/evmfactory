import { AnchorProvider } from "@project-serum/anchor";
import { PublicKey } from "@solana/web3.js";

const PROGRAM_ID = new PublicKey("Evmmarket111111111111111111111111111111111");

export default async function deploy(provider: AnchorProvider): Promise<void> {
  AnchorProvider.setProvider(provider);

  console.log("Deploy script placeholder", {
    programId: PROGRAM_ID.toBase58(),
  });
}