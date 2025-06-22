import { expect } from "chai";
import { ethers } from "hardhat";

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
  await acl.grantRole(await acl.DEFAULT_ADMIN_ROLE(), predictedFactory);

  const Factory = await ethers.getContractFactory("ContestFactory");
  const factory = await Factory.deploy(await registry.getAddress(), await gateway.getAddress(), await validatorLogic.getAddress());

  await factory.setPriceFeed(await priceFeed.getAddress());
  await factory.setUsdFeeBounds(ethers.parseEther("5"), ethers.parseEther("10"));

  return { factory, token, priceFeed, registry, gateway };
}

describe("PrizeAssigned event", function () {
  it("emits for non monetary prize", async function () {
    const [creator, winner] = await ethers.getSigners();
    const { factory, token, priceFeed, gateway } = await deployFactory();

    const params = {
      judges: [] as string[],
      metadata: "0x",
      commissionToken: await token.getAddress(),
    };

    await token.approve(await gateway.getAddress(), ethers.parseEther("100"));
    await priceFeed.setPrice(await token.getAddress(), ethers.parseEther("1"));

    const prizes = [
      {
        prizeType: 1,
        token: ethers.ZeroAddress,
        amount: 0,
        distribution: 0,
        uri: "ipfs://swag"
      }
    ];

    const tx = await factory.createCustomContest(prizes, params);
    const rc = await tx.wait();
    const ev = rc?.logs.find((l: any) => l.fragment && l.fragment.name === "ContestCreated");
    const contestAddr = ev?.args[1];
    const esc = await ethers.getContractAt("ContestEscrow", contestAddr);

    const finalizeTx = await esc.finalize([winner.address]);
    const receipt = await finalizeTx.wait();
    const assigned = receipt?.logs.find((l: any) => l.fragment && l.fragment.name === "PrizeAssigned");
    expect(assigned.args[0]).to.equal(winner.address);
    expect(assigned.args[1]).to.equal("ipfs://swag");
  });
});
