import { ethers } from "hardhat";

async function main() {
  const accessAddress = process.env.ACCESS_CONTROL_ADDRESS;
  const keeperAddress = process.env.KEEPER_ADDRESS;
  if (!accessAddress || !keeperAddress) {
    throw new Error("ACCESS_CONTROL_ADDRESS and KEEPER_ADDRESS required");
  }

  const access = await ethers.getContractAt("AccessControlCenter", accessAddress);
  const role = await access.AUTOMATION_ROLE();
  const tx = await access.grantRole(role, keeperAddress);
  await tx.wait();
  console.log(`Granted AUTOMATION_ROLE to ${keeperAddress}`);
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

