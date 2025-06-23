import { expect } from "chai";
import { ethers } from "hardhat";

const planTypes = {
  Plan: [
    { name: "chainIds", type: "uint256[]" },
    { name: "price", type: "uint256" },
    { name: "period", type: "uint256" },
    { name: "token", type: "address" },
    { name: "merchant", type: "address" },
    { name: "salt", type: "uint256" },
    { name: "expiry", type: "uint64" },
  ],
};

describe("SubscriptionManager permit", function () {
  it("allows subscribe with permit", async function () {
    const [owner, merchant] = await ethers.getSigners();

    const Token = await ethers.getContractFactory("TestToken");
    const token = await Token.deploy("Test", "TST");

    const ACL = await ethers.getContractFactory("AccessControlCenter");
    const acl = await ACL.deploy();
    await acl.initialize(owner.address);

    const Registry = await ethers.getContractFactory("MockRegistry");
    const registry = await Registry.deploy();
    const FACTORY_ADMIN = ethers.keccak256(ethers.toUtf8Bytes("FACTORY_ADMIN"));
    await acl.grantRole(FACTORY_ADMIN, owner.address);
    await acl.grantRole(await acl.FEATURE_OWNER_ROLE(), owner.address);
    await registry.setCoreService(ethers.keccak256(Buffer.from("AccessControlCenter")), await acl.getAddress());

    const Gateway = await ethers.getContractFactory("MockPaymentGateway");
    const gateway = await Gateway.deploy();

    const moduleId = ethers.keccak256(ethers.toUtf8Bytes("Sub"));
    const nextNonce = await owner.getNonce();
    const predictedManager = ethers.getCreateAddress({
      from: owner.address,
      nonce: nextNonce + 1,
    });
    await acl.grantRole(await acl.DEFAULT_ADMIN_ROLE(), predictedManager);
    const Manager = await ethers.getContractFactory("SubscriptionManager");
    const manager = await Manager.deploy(
      await registry.getAddress(),
      await gateway.getAddress(),
      moduleId
    );

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
    const sigMerchant = await merchant.signTypedData(
      { chainId: 31337, verifyingContract: await manager.getAddress() },
      planTypes,
      plan
    );

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

    const ACL = await ethers.getContractFactory("AccessControlCenter");
    const acl = await ACL.deploy();
    await acl.initialize(owner.address);
    const FACTORY_ADMIN = ethers.keccak256(ethers.toUtf8Bytes("FACTORY_ADMIN"));
    await acl.grantRole(FACTORY_ADMIN, owner.address);
    await acl.grantRole(await acl.FEATURE_OWNER_ROLE(), owner.address);

    const Registry = await ethers.getContractFactory("MockRegistry");
    const registry = await Registry.deploy();
    await registry.setCoreService(ethers.keccak256(Buffer.from("AccessControlCenter")), await acl.getAddress());

    const Gateway = await ethers.getContractFactory("MockPaymentGateway");
    const gateway = await Gateway.deploy();

    const moduleId = ethers.keccak256(ethers.toUtf8Bytes("Sub"));
    const nextNonce = await owner.getNonce();
    const predictedManager = ethers.getCreateAddress({
      from: owner.address,
      nonce: nextNonce + 1,
    });
    await acl.grantRole(await acl.DEFAULT_ADMIN_ROLE(), predictedManager);
    const Manager = await ethers.getContractFactory("SubscriptionManager");
    const manager = await Manager.deploy(
      await registry.getAddress(),
      await gateway.getAddress(),
      moduleId
    );

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
    const sigMerchant = await merchant.signTypedData(
      { chainId: 31337, verifyingContract: await manager.getAddress() },
      planTypes,
      plan
    );

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
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";

describe("SubscriptionManager unsubscribe", function () {
  it("removes subscriber on unsubscribe", async function () {
    const [owner, merchant] = await ethers.getSigners();

    const Token = await ethers.getContractFactory("TestToken");
    const token = await Token.deploy("Test", "TST");

    const ACL = await ethers.getContractFactory("AccessControlCenter");
    const acl = await ACL.deploy();
    await acl.initialize(owner.address);
    const FACTORY_ADMIN = ethers.keccak256(ethers.toUtf8Bytes("FACTORY_ADMIN"));
    await acl.grantRole(FACTORY_ADMIN, owner.address);
    await acl.grantRole(await acl.FEATURE_OWNER_ROLE(), owner.address);

    const Registry = await ethers.getContractFactory("MockRegistry");
    const registry = await Registry.deploy();
    await registry.setCoreService(ethers.keccak256(Buffer.from("AccessControlCenter")), await acl.getAddress());

    const Gateway = await ethers.getContractFactory("MockPaymentGateway");
    const gateway = await Gateway.deploy();

    const moduleId = ethers.keccak256(ethers.toUtf8Bytes("Sub"));
    const nextNonce = await owner.getNonce();
    const predictedManager = ethers.getCreateAddress({
      from: owner.address,
      nonce: nextNonce + 1,
    });
    await acl.grantRole(await acl.DEFAULT_ADMIN_ROLE(), predictedManager);
    const Manager = await ethers.getContractFactory("SubscriptionManager");
    const manager = await Manager.deploy(
      await registry.getAddress(),
      await gateway.getAddress(),
      moduleId
    );

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
    const sigMerchant = await merchant.signTypedData(
      { chainId: 31337, verifyingContract: await manager.getAddress() },
      planTypes,
      plan
    );

    await token.approve(await gateway.getAddress(), plan.price);
    await manager.subscribe(plan, sigMerchant, "0x");

    const unsubTx = await manager.unsubscribe();
    await expect(unsubTx).to.emit(manager, "Unsubscribed").withArgs(owner.address, planHash);
    await expect(unsubTx).to.emit(manager, "PlanCancelled").withArgs(owner.address, planHash, anyValue);

    const sub = await manager.subscribers(owner.address);
    expect(sub.nextBilling).to.equal(0);
    expect(sub.planHash).to.equal(ethers.ZeroHash);
  });
});

describe("SubscriptionManager batch charge", function () {
  it("charges multiple subscribers", async function () {
    const signers = await ethers.getSigners();
    const owner = signers[0];
    const merchant = signers[1];
    const users = signers.slice(2, 12);

    const Token = await ethers.getContractFactory("TestToken");
    const token = await Token.deploy("Test", "TST");

    const ACL = await ethers.getContractFactory("AccessControlCenter");
    const acl = await ACL.deploy();
    await acl.initialize(owner.address);
    const FACTORY_ADMIN = ethers.keccak256(ethers.toUtf8Bytes("FACTORY_ADMIN"));
    await acl.grantRole(FACTORY_ADMIN, owner.address);
    await acl.grantRole(await acl.FEATURE_OWNER_ROLE(), owner.address);
    await acl.grantRole(await acl.AUTOMATION_ROLE(), owner.address);

    const Registry = await ethers.getContractFactory("MockRegistry");
    const registry = await Registry.deploy();
    await registry.setCoreService(ethers.keccak256(Buffer.from("AccessControlCenter")), await acl.getAddress());

    const Gateway = await ethers.getContractFactory("MockPaymentGateway");
    const gateway = await Gateway.deploy();

    const moduleId = ethers.keccak256(ethers.toUtf8Bytes("Sub"));
    const nextNonce = await owner.getNonce();
    const predictedManager = ethers.getCreateAddress({
      from: owner.address,
      nonce: nextNonce + 1,
    });
    await acl.grantRole(await acl.DEFAULT_ADMIN_ROLE(), predictedManager);
    const Manager = await ethers.getContractFactory("SubscriptionManager");
    const manager = await Manager.deploy(
      await registry.getAddress(),
      await gateway.getAddress(),
      moduleId
    );

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
    const sigMerchant = await merchant.signTypedData(
      { chainId: 31337, verifyingContract: await manager.getAddress() },
      planTypes,
      plan
    );

    for (const u of users) {
      await token.transfer(u.address, ethers.parseEther("10"));
      await token
        .connect(u)
        .approve(await gateway.getAddress(), ethers.MaxUint256);
      await manager.connect(u).subscribe(plan, sigMerchant, "0x");
    }

    const subsBefore = await Promise.all(users.map(u => manager.subscribers(u.address)));

    await ethers.provider.send("evm_increaseTime", [Number(plan.period)]);
    await ethers.provider.send("evm_mine", []);

    const merchantBal0 = await token.balanceOf(merchant.address);
    const userAddrs = users.map(u => u.address);
    await manager.chargeBatch(userAddrs);
    const merchantBal1 = await token.balanceOf(merchant.address);

    expect(merchantBal1 - merchantBal0).to.equal(plan.price * BigInt(users.length));

    for (let i = 0; i < users.length; i++) {
      const after = await manager.subscribers(users[i].address);
      expect(after.nextBilling).to.equal(subsBefore[i].nextBilling + plan.period);
    }
  });

  it("reverts for caller without automation role", async function () {
    const [owner, merchant, user] = await ethers.getSigners();

    const Token = await ethers.getContractFactory("TestToken");
    const token = await Token.deploy("Test", "TST");

    const ACL = await ethers.getContractFactory("AccessControlCenter");
    const acl = await ACL.deploy();
    await acl.initialize(owner.address);
    const FACTORY_ADMIN = ethers.keccak256(ethers.toUtf8Bytes("FACTORY_ADMIN"));
    await acl.grantRole(FACTORY_ADMIN, owner.address);
    await acl.grantRole(await acl.FEATURE_OWNER_ROLE(), owner.address);

    const Registry = await ethers.getContractFactory("MockRegistry");
    const registry = await Registry.deploy();
    await registry.setCoreService(ethers.keccak256(Buffer.from("AccessControlCenter")), await acl.getAddress());

    const Gateway = await ethers.getContractFactory("MockPaymentGateway");
    const gateway = await Gateway.deploy();

    const moduleId = ethers.keccak256(ethers.toUtf8Bytes("Sub"));
    const nextNonce = await owner.getNonce();
    const predictedManager = ethers.getCreateAddress({
      from: owner.address,
      nonce: nextNonce + 1,
    });
    await acl.grantRole(await acl.DEFAULT_ADMIN_ROLE(), predictedManager);
    const Manager = await ethers.getContractFactory("SubscriptionManager");
    const manager = await Manager.deploy(
      await registry.getAddress(),
      await gateway.getAddress(),
      moduleId
    );

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
    const sigMerchant = await merchant.signTypedData(
      { chainId: 31337, verifyingContract: await manager.getAddress() },
      planTypes,
      plan
    );

    await token.transfer(user.address, ethers.parseEther("10"));
    await token.connect(user).approve(await gateway.getAddress(), plan.price);
    await manager.connect(user).subscribe(plan, sigMerchant, "0x");

    await ethers.provider.send("evm_increaseTime", [Number(plan.period)]);
    await ethers.provider.send("evm_mine", []);

    await expect(manager.chargeBatch([user.address])).to.be.revertedWithCustomError(manager, "NotAutomation");
  });
});
