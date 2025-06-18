import { expect } from "chai";
import { ethers } from "hardhat";

describe("SubscriptionManager permit", function () {
  it("uses Permit2 for subscribe", async function () {
    const [owner, merchant] = await ethers.getSigners();

    const Token = await ethers.getContractFactory("TestToken");
    const token = await Token.deploy("Test", "TST");

    const ACL = await ethers.getContractFactory("MockAccessControlCenter");
    const acl = await ACL.deploy();

    const Registry = await ethers.getContractFactory("MockRegistry");
    const registry = await Registry.deploy();
    await registry.setCoreService(ethers.keccak256(Buffer.from("AccessControlCenter")), acl.getAddress());

    const Gateway = await ethers.getContractFactory("MockPaymentGateway");
    const gateway = await Gateway.deploy();

    const Permit2 = await ethers.getContractFactory("MockPermit2");
    const permit2 = await Permit2.deploy();

    const moduleId = ethers.keccak256(ethers.toUtf8Bytes("Sub"));
    const Manager = await ethers.getContractFactory("SubscriptionManager");
    const manager = await Manager.deploy(await registry.getAddress(), await gateway.getAddress(), moduleId);
    await registry.setModuleServiceAlias(moduleId, "Permit2", await permit2.getAddress());

    const plan = {
      chainIds: [31337n],
      price: ethers.parseEther("1"),
      period: 100n,
      token: await token.getAddress(),
      merchant: merchant.address,
      salt: 1n,
      expiry: 0n,
    } as const;

    const planHash = await manager.hashPlan(plan);
    const sigMerchant = await merchant.signMessage(ethers.getBytes(planHash));

    const deadline = (await ethers.provider.getBlock("latest")).timestamp + 1000;
    const permit = {
      permitted: { token: await token.getAddress(), amount: plan.price },
      nonce: 0n,
      deadline: BigInt(deadline),
    };
    const details = { to: await gateway.getAddress(), requestedAmount: plan.price };
    const permitSig = permit2.interface.encodeFunctionData("permitTransferFrom", [permit, details, owner.address, "0x"]);

    await expect(manager.subscribe(plan, sigMerchant, permitSig)).to.not.be.reverted;
  });
});
