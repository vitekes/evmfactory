import { ethers } from "hardhat";
import { deployCore, registerModule } from "./utils/deployer";
import { CONSTANTS } from "./utils/constants";
import { safeExecute } from "./utils/helpers";
import { createContest, finalizeContest } from "./utils/contest";

async function main() {
  const [deployer, p1, p2, p3] = await ethers.getSigners();

  console.log("=== Contest Demo ===\n");
  console.log(`Deployer: ${deployer.address}`);
  console.log(`Participant1: ${p1.address}`);
  console.log(`Participant2: ${p2.address}`);
  console.log(`Participant3: ${p3.address}\n`);

  const { token, registry, gateway, validator, feeManager } = await deployCore();

  const contestFactory = await safeExecute("deploy contest factory", async () => {
    const Factory = await ethers.getContractFactory("ContestFactory");
    const factory = await Factory.deploy(
      await registry.getAddress(),
      await feeManager.getAddress()
    );
    await factory.waitForDeployment();
    return factory;
  });

  await registerModule(
    registry,
    CONSTANTS.CONTEST_ID,
    await contestFactory.getAddress(),
    await validator.getAddress(),
    await gateway.getAddress()
  );

  await safeExecute("approve tokens", async () => {
    await token.approve(await contestFactory.getAddress(), ethers.parseEther("1000"));
  });

  const contestAddress = await safeExecute("create contest", async () => {
    return createContest(contestFactory, await token.getAddress());
  });

  await safeExecute("finalize contest", async () => {
    const winners = [p1.address, p2.address, p3.address];
    await finalizeContest(contestAddress, winners);
  });

  const [bal1, bal2, bal3] = await Promise.all([
    token.balanceOf(p1.address),
    token.balanceOf(p2.address),
    token.balanceOf(p3.address)
  ]);
  console.log(`Winner1 balance: ${ethers.formatEther(bal1)} tokens`);
  console.log(`Winner2 balance: ${ethers.formatEther(bal2)} tokens`);
  console.log(`Winner3 balance: ${ethers.formatEther(bal3)} tokens`);

  console.log("\n✅ Demo finished");
}

main().catch((error) => {
  console.error("Demo failed", error);
  process.exitCode = 1;
});
