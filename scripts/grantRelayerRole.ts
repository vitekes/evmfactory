import { ethers } from "hardhat";

async function main() {
  const accessAddress = process.env.ACCESS_CONTROL_ADDRESS;
  const relayerAddress = process.env.RELAYER_ADDRESS;
  if (!accessAddress || !relayerAddress) {
    throw new Error("ACCESS_CONTROL_ADDRESS and RELAYER_ADDRESS required");
  }

  const access = await ethers.getContractAt("AccessControlCenter", accessAddress);
  const role = await access.RELAYER_ROLE();
  const tx = await access.grantRole(role, relayerAddress);
  await tx.wait();
  console.log(`Granted RELAYER_ROLE to ${relayerAddress}`);
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
