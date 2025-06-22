import { expect } from "chai";
import { ethers } from "hardhat";

function predictCloneAddress(impl: string, salt: string, deployer: string) {
  const prefix = "0x3d602d80600a3d3981f3363d3d373d3d3d363d73";
  const suffix = "5af43d82803e903d91602b57fd5bf3";
  const creationCode = prefix + impl.slice(2) + suffix;
  const initHash = ethers.keccak256(creationCode);
  return ethers.getCreate2Address(deployer, salt, initHash);
}

async function deployFactory() {
  const [deployer] = await ethers.getSigners();
  const Token = await ethers.getContractFactory("TestToken");
  const token = await Token.deploy("USD Coin", "USDC");

  const ACL = await ethers.getContractFactory("AccessControlCenter");
  const acl = await ACL.deploy();
  await acl.initialize(deployer.address);
  const FACTORY_ADMIN = ethers.keccak256(ethers.toUtf8Bytes("FACTORY_ADMIN"));
  await acl.grantRole(FACTORY_ADMIN, deployer.address);
  await acl.grantRole(await acl.FEATURE_OWNER_ROLE(), deployer.address);

  const Registry = await ethers.getContractFactory("MockRegistry");
  const registry = await Registry.deploy();
  await registry.setCoreService(ethers.keccak256(Buffer.from("AccessControlCenter")), await acl.getAddress());

  const Gateway = await ethers.getContractFactory("MockPaymentGateway");
  const gateway = await Gateway.deploy();

  const PriceFeed = await ethers.getContractFactory("MockPriceFeed");
  const priceFeed = await PriceFeed.deploy();

  const Validator = await ethers.getContractFactory("MultiValidator");
  const validatorLogic = await Validator.deploy();

  // predict the factory address after the upcoming grantRole tx
  const predictedFactory = ethers.getCreateAddress({
    from: deployer.address,
    nonce: (await deployer.getNonce()) + 1,
  });

  const moduleId = ethers.keccak256(ethers.toUtf8Bytes("Contest"));
  const salt = ethers.keccak256(
    ethers.solidityPacked([
      "string",
      "bytes32",
      "address",
    ], ["Validator", moduleId, predictedFactory])
  );
  const predictedValidator = predictCloneAddress(
    await validatorLogic.getAddress(),
    salt,
    predictedFactory
  );

  await acl.grantRole(await acl.DEFAULT_ADMIN_ROLE(), predictedFactory);
  await acl.grantRole(await acl.DEFAULT_ADMIN_ROLE(), predictedValidator);

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
