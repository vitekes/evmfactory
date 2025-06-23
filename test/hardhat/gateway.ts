import { expect } from "chai";
import { ethers } from "hardhat";

describe("PaymentGateway access", function () {
  it("reverts for caller without feature owner role", async function () {
    const [admin, user] = await ethers.getSigners();

    const ACC = await ethers.getContractFactory("AccessControlCenter");
    const acc = await ACC.deploy();
    await acc.initialize(admin.address);

    const Registry = await ethers.getContractFactory("MockRegistry");
    const registry = await Registry.deploy();
    await registry.setCoreService(ethers.keccak256(Buffer.from("AccessControlCenter")), await acc.getAddress());

    const Fee = await ethers.getContractFactory("CoreFeeManager");
    const fee = await Fee.deploy();
    await fee.initialize(await acc.getAddress());

    const Gateway = await ethers.getContractFactory("PaymentGateway");
    const gateway = await Gateway.deploy();
    await gateway.initialize(await acc.getAddress(), await registry.getAddress(), await fee.getAddress());

    const Token = await ethers.getContractFactory("TestToken");
    const token = await Token.deploy("Test", "TST");
    await token.transfer(user.address, ethers.parseEther("1"));
    await token.connect(user).approve(await gateway.getAddress(), ethers.parseEther("1"));

    const MODULE_ID = ethers.keccak256(ethers.toUtf8Bytes("Core"));
    await expect(
      gateway.connect(user).processPayment(MODULE_ID, await token.getAddress(), user.address, ethers.parseEther("1"), "0x")
    ).to.be.revertedWithCustomError(gateway, "NotFeatureOwner");
  });
});
