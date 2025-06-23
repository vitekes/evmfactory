import { expect } from "chai";
import { ethers } from "hardhat";

describe("meta transaction", function () {
  it("allows relayer with role to pay", async function () {
    const [admin, payer, relayer, bad] = await ethers.getSigners();

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
    await (await acc.grantRole(await acc.FEATURE_OWNER_ROLE(), await gateway.getAddress())).wait();

    const Validator = await ethers.getContractFactory("MultiValidator");
    const validator: any = await Validator.deploy();
    await acc.grantRole(await acc.DEFAULT_ADMIN_ROLE(), await validator.getAddress());
    await validator.initialize(await acc.getAddress());

    const MODULE_ID = ethers.keccak256(ethers.toUtf8Bytes("Core"));
    await registry.setModuleServiceAlias(MODULE_ID, "Validator", await validator.getAddress());

    const Token = await ethers.getContractFactory("TestToken");
    const token = await Token.deploy("USD Coin", "USDC");
    await validator.addToken(await token.getAddress());
    await token.transfer(payer.address, ethers.parseEther("10"));
    await token.connect(payer).approve(await gateway.getAddress(), ethers.parseEther("10"));

    const Forwarder = await ethers.getContractFactory("MockForwarder");
    const forwarder = await Forwarder.deploy(await acc.getAddress());

    await (await acc.grantRole(await acc.FEATURE_OWNER_ROLE(), forwarder.getAddress())).wait();
    await (await acc.grantRole(await acc.RELAYER_ROLE(), forwarder.getAddress())).wait();
    await (await acc.grantRole(await acc.RELAYER_ROLE(), relayer.address)).wait();

    const data = gateway.interface.encodeFunctionData("processPayment", [
      MODULE_ID,
      await token.getAddress(),
      payer.address,
      ethers.parseEther("1"),
      "0x",
    ]);

    await forwarder.connect(relayer).execute(await gateway.getAddress(), data);
    expect(await token.balanceOf(await forwarder.getAddress())).to.equal(ethers.parseEther("1"));

    await expect(
      forwarder.connect(bad).execute(await gateway.getAddress(), data)
    ).to.be.revertedWithCustomError(forwarder, "InvalidForwarder");
  });
});
