import { ethers, network } from "hardhat";
import { deployCore, registerModule } from "./utils/deployer";
import { CONSTANTS } from "./utils/constants";
import { safeExecute } from "./utils/helpers";

async function main() {
  const [deployer, merchant, user, keeper] = await ethers.getSigners();

  console.log("=== Subscription Demo ===\n");
  console.log(`Deployer: ${deployer.address}`);
  console.log(`Merchant: ${merchant.address}`);
  console.log(`User:     ${user.address}\n`);

  const { token, registry, gateway, validator, acl } = await deployCore();

  const manager = await safeExecute("deploy subscription manager", async () => {
    const Factory = await ethers.getContractFactory("SubscriptionManager");
    const mgr = await Factory.deploy(
      await registry.getAddress(),
      await gateway.getAddress(),
      CONSTANTS.SUBSCRIPTION_ID
    );
    await mgr.waitForDeployment();
    console.log(`SubscriptionManager deployed at ${await mgr.getAddress()}`);
    return mgr;
  });

  await registerModule(
    registry,
    CONSTANTS.SUBSCRIPTION_ID,
    await manager.getAddress(),
    await validator.getAddress(),
    await gateway.getAddress()
  );

  await safeExecute("grant roles", async () => {
    const featureRole = await acl.FEATURE_OWNER_ROLE();
    const moduleRole = await acl.MODULE_ROLE();
    await acl.grantRole(featureRole, await manager.getAddress());
    await acl.grantRole(moduleRole, await manager.getAddress());
    const autoRole = await acl.AUTOMATION_ROLE();
    await acl.grantRole(autoRole, keeper.address);
  });

  await safeExecute("fund user", async () => {
    await token.transfer(user.address, ethers.parseEther("5"));
  });

  const plan = {
    chainIds: [ (await ethers.provider.getNetwork()).chainId ],
    price: ethers.parseEther("1"),
    period: 3600n,
    token: await token.getAddress(),
    merchant: merchant.address,
    salt: 1n,
    expiry: 0n
  };

  const domain = { chainId: plan.chainIds[0], verifyingContract: await manager.getAddress() };
  const types = {
    Plan: [
      { name: "chainIds", type: "uint256[]" },
      { name: "price", type: "uint256" },
      { name: "period", type: "uint256" },
      { name: "token", type: "address" },
      { name: "merchant", type: "address" },
      { name: "salt", type: "uint256" },
      { name: "expiry", type: "uint64" }
    ]
  } as const;
  const signature = await merchant.signTypedData(domain, types, plan);

  await token.connect(user).approve(await gateway.getAddress(), ethers.parseEther("5"));

  await safeExecute("subscribe", async () => {
    await manager.connect(user).subscribe(plan, signature, "0x");
  });

  await network.provider.send("evm_increaseTime", [ Number(plan.period) + 5 ]);
  await network.provider.send("evm_mine", []);

  await safeExecute("charge", async () => {
    await manager.connect(keeper).charge(user.address);
  });

  const merchantBal = await token.balanceOf(merchant.address);
  console.log(`Merchant balance: ${ethers.formatEther(merchantBal)} tokens`);

  await safeExecute("unsubscribe", async () => {
    await manager.connect(user).unsubscribe();
  });

  console.log("\n✅ Demo finished");
}

main().catch((error) => {
  console.error("Demo failed", error);
  process.exitCode = 1;
});
