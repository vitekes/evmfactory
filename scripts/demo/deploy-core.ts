import { ethers } from "hardhat";
import { deployMockToken, deployMockOracle } from "./utils/helpers";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log(`Deploying from ${deployer.address}`);

  const token = await deployMockToken("DemoToken", "DEMO", 1_000_000n * 10n ** 18n);
  console.log(`Mock token deployed at ${await token.getAddress()}`);

  const oracle = await deployMockOracle();
  console.log(`Mock oracle deployed at ${await oracle.getAddress()}`);
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
