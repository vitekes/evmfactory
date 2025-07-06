import { ethers } from "hardhat";
import { deployMockToken } from "./utils/helpers";

const FACTORY_ADDR = process.env.CONTEST_FACTORY_ADDRESS;

async function main() {
  const [creator] = await ethers.getSigners();
  const token = await deployMockToken("Prize", "PRZ", 1_000_000n * 10n ** 18n);
  console.log(`Prize token at ${await token.getAddress()}`);

  if (!FACTORY_ADDR) {
    throw new Error("CONTEST_FACTORY_ADDRESS env var not set");
  }

  // Connect to deployed ContestFactory
  const factory = await ethers.getContractAt("ContestFactory", FACTORY_ADDR);

  const prizes = [{prizeType: 0, token: await token.getAddress(), amount: ethers.parseEther("100"), distribution: 0, uri: ""}];
  const tx = await factory.createContest(prizes, "0x");
  const receipt = await tx.wait();
  console.log(`Contest created in tx ${receipt?.hash}`);
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});

