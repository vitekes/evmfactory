import { expect } from "chai";
import { ethers } from "hardhat";

async function deployFactory() {
  const Token = await ethers.getContractFactory("TestToken");
  const token = await Token.deploy("USD Coin", "USDC");

  const ACL = await ethers.getContractFactory("MockAccessControlCenter");
  const acl = await ACL.deploy();

  const Registry = await ethers.getContractFactory("MockRegistry");
  const registry = await Registry.deploy();
  await registry.setCoreService(ethers.keccak256(Buffer.from("AccessControlCenter")), await acl.getAddress());

  const Gateway = await ethers.getContractFactory("MockPaymentGateway");
  const gateway = await Gateway.deploy();

  const PriceFeed = await ethers.getContractFactory("MockPriceFeed");
  const priceFeed = await PriceFeed.deploy();

  const Validator = await ethers.getContractFactory("MultiValidator");
  const validatorLogic = await Validator.deploy();

  const Factory = await ethers.getContractFactory("ContestFactory");
  const factory = await Factory.deploy(await registry.getAddress(), await gateway.getAddress(), await validatorLogic.getAddress());

  await factory.setPriceFeed(await priceFeed.getAddress());
  await factory.setUsdFeeBounds(ethers.parseEther("5"), ethers.parseEther("10"));

  return { factory, token, priceFeed, registry, gateway };
}

describe("ContestFactory fee", function () {
  it("uses price feed for commission", async function () {
    const [creator] = await ethers.getSigners();
    const { factory, token, priceFeed, gateway } = await deployFactory();

    const params = {
      judges: [] as string[],
      metadata: "0x",
      commissionToken: await token.getAddress(),
    };

    // Approve factory to pull tokens via gateway mock
  await token.approve(await gateway.getAddress(), ethers.parseEther("100"));

    // test price 0.95 USD
    await priceFeed.setPrice(await token.getAddress(), ethers.parseEther("0.95"));
    let tx = await factory.createCustomContest([], params);
    let rc = await tx.wait();
    let ev = rc?.logs.find((l: any) => l.fragment && l.fragment.name === "ContestCreated");
    const contestAddr1 = ev?.args[1];
    const esc1 = await ethers.getContractAt("ContestEscrow", contestAddr1);
    let fee1 = await esc1.commissionFee();
    expect(fee1).to.be.gte(ethers.parseEther("5"));
    expect(fee1).to.be.lte(ethers.parseEther("10"));

    // test price 1.05 USD
    await priceFeed.setPrice(await token.getAddress(), ethers.parseEther("1.05"));
    tx = await factory.createCustomContest([], params);
    rc = await tx.wait();
    ev = rc?.logs.find((l: any) => l.fragment && l.fragment.name === "ContestCreated");
    const contestAddr2 = ev?.args[1];
    const esc2 = await ethers.getContractAt("ContestEscrow", contestAddr2);
    let fee2 = await esc2.commissionFee();
    expect(fee2).to.be.gte(ethers.parseEther("5"));
    expect(fee2).to.be.lte(ethers.parseEther("10"));
  });
});
