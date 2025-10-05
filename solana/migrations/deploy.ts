import { AnchorProvider, Program, web3 } from "@project-serum/anchor";

export default async function (provider: AnchorProvider) {
  AnchorProvider.setProvider(provider);
  const program = (await Program.at(
    "Evmmarket111111111111111111111111111111111",
    provider,
  )) as Program;

  console.log("Deploy script placeholder", {
    programId: program.programId.toBase58(),
  });
}
