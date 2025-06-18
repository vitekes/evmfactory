import { expect } from "chai";
import { ethers } from "hardhat";

describe("SubscriptionManager permit", function () {
  it("allows subscribe with permit", async function () {
    const [owner, merchant] = await ethers.getSigners();

    const Token = await ethers.getContractFactory("TestToken");
    const token = await Token.deploy("Test", "TST");

    const ACL = await ethers.getContractFactory("MockAccessControlCenter");
    const acl = await ACL.deploy();

    const Registry = await ethers.getContractFactory("MockRegistry");
    const registry = await Registry.deploy();
    await registry.setCoreService(ethers.keccak256(Buffer.from("AccessControlCenter")), await acl.getAddress());

    const Gateway = await ethers.getContractFactory("MockPaymentGateway");
    const gateway = await Gateway.deploy();

    const moduleId = ethers.keccak256(ethers.toUtf8Bytes("Sub"));
    const Manager = await ethers.getContractFactory("SubscriptionManager");
    const manager = await Manager.deploy(await registry.getAddress(), await gateway.getAddress(), moduleId);

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

    const nonce = await token.nonces(owner.address);
    const deadline = (await ethers.provider.getBlock("latest")).timestamp + 1000;
    const chainId = 31337;
    const signature = await owner.signTypedData(
      {
        name: await token.name(),
        version: "1",
        chainId: chainId,
        verifyingContract: await token.getAddress(),
      },
      { Permit: [
        { name: "owner", type: "address" },
        { name: "spender", type: "address" },
        { name: "value", type: "uint256" },
        { name: "nonce", type: "uint256" },
        { name: "deadline", type: "uint256" },
      ] },
      {
        owner: owner.address,
        spender: await gateway.getAddress(),
        value: plan.price,
        nonce: nonce,
        deadline: deadline,
      }
    );
    const sig = ethers.Signature.from(signature);
    const permitSig = ethers.AbiCoder.defaultAbiCoder().encode([
      "uint256",
      "uint8",
      "bytes32",
      "bytes32",
    ], [deadline, sig.v, sig.r, sig.s]);

    await expect(manager.subscribe(plan, sigMerchant, permitSig)).to.not.be.reverted;
  });

  it("reverts on bad permit signature", async function () {
    const [owner, merchant, attacker] = await ethers.getSigners();

    const Token = await ethers.getContractFactory("TestToken");
    const token = await Token.deploy("Test", "TST");

    const ACL = await ethers.getContractFactory("MockAccessControlCenter");
    const acl = await ACL.deploy();

    const Registry = await ethers.getContractFactory("MockRegistry");
    const registry = await Registry.deploy();
    await registry.setCoreService(ethers.keccak256(Buffer.from("AccessControlCenter")), await acl.getAddress());

    const Gateway = await ethers.getContractFactory("MockPaymentGateway");
    const gateway = await Gateway.deploy();

    const moduleId = ethers.keccak256(ethers.toUtf8Bytes("Sub"));
    const Manager = await ethers.getContractFactory("SubscriptionManager");
    const manager = await Manager.deploy(await registry.getAddress(), await gateway.getAddress(), moduleId);

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

    const nonce = await token.nonces(owner.address);
    const deadline = (await ethers.provider.getBlock("latest")).timestamp + 1000;
    const chainIdBad = 31337;
    const signature = await attacker.signTypedData(
      {
        name: await token.name(),
        version: "1",
        chainId: chainIdBad,
        verifyingContract: await token.getAddress(),
      },
      { Permit: [
        { name: "owner", type: "address" },
        { name: "spender", type: "address" },
        { name: "value", type: "uint256" },
        { name: "nonce", type: "uint256" },
        { name: "deadline", type: "uint256" },
      ] },
      {
        owner: owner.address,
        spender: await gateway.getAddress(),
        value: plan.price,
        nonce: nonce,
        deadline: deadline,
      }
    );
    const sig = ethers.Signature.from(signature);
    const permitSig = ethers.AbiCoder.defaultAbiCoder().encode([
      "uint256",
      "uint8",
      "bytes32",
      "bytes32",
    ], [deadline, sig.v, sig.r, sig.s]);

    await expect(manager.subscribe(plan, sigMerchant, permitSig)).to.be.reverted;
  });
});
