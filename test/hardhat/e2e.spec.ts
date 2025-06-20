import { expect } from "chai";
import { ethers, network } from "hardhat";

async function deployCore() {
  const Token = await ethers.getContractFactory("TestToken");
  const token = await Token.deploy("USD Coin", "USDC");

  const ACL = await ethers.getContractFactory("AccessControlCenter");
  const acl = await ACL.deploy();
  await acl.initialize((await ethers.getSigners())[0].address);
  const FACTORY_ADMIN = ethers.keccak256(ethers.toUtf8Bytes("FACTORY_ADMIN"));
  await acl.grantRole(FACTORY_ADMIN, (await ethers.getSigners())[0].address);
  await acl.grantRole(await acl.FEATURE_OWNER_ROLE(), (await ethers.getSigners())[0].address);

  const Registry = await ethers.getContractFactory("MockRegistry");
  const registry = await Registry.deploy();
  await registry.setCoreService(ethers.keccak256(Buffer.from("AccessControlCenter")), await acl.getAddress());

  const Gateway = await ethers.getContractFactory("MockPaymentGateway");
  const gateway = await Gateway.deploy();

  const PriceFeed = await ethers.getContractFactory("ChainlinkPriceFeed");
  const priceFeed = await PriceFeed.deploy();

  const Validator = await ethers.getContractFactory("MultiValidator");
  const validatorLogic = await Validator.deploy();

  const Factory = await ethers.getContractFactory("ContestFactory");
  const factory = await Factory.deploy(await registry.getAddress(), await gateway.getAddress(), await validatorLogic.getAddress());

  await factory.setPriceFeed(await priceFeed.getAddress());
  await factory.setUsdFeeBounds(ethers.parseEther("5"), ethers.parseEther("10"));

  return { factory, token, priceFeed, registry, gateway };
}

describe("fork e2e", function () {
  it("deploys contest and finalizes prizes", async function () {
    if (!network.config.forking?.url) {
      console.log("Skipping: not a forked network");
      this.skip();
    }

    const [creator, winner] = await ethers.getSigners();
    await network.provider.send("hardhat_setBalance", [creator.address, "0x21e19e0c9bab2400000"]); // 1000 ETH

    const { factory, token, priceFeed, registry, gateway } = await deployCore();

    // configure chainlink feed for our test token
    const FEED = "0xab5c6c3c1626d9052d3b714d8813bb69cf2ce317"; // USDC/USD on Goerli
    await priceFeed.setAggregator(await token.getAddress(), FEED);

    // allow token via validator
    const moduleId = ethers.keccak256(ethers.toUtf8Bytes("Contest"));
    const validatorAddr = await registry.getModuleService(moduleId, "Validator");
    await network.provider.send("hardhat_impersonateAccount", [await factory.getAddress()]);
    const factorySigner = await ethers.getSigner(await factory.getAddress());
    const validator = await ethers.getContractAt("MultiValidator", validatorAddr);
    await validator.connect(factorySigner).addToken(await token.getAddress());
    await network.provider.send("hardhat_stopImpersonatingAccount", [await factory.getAddress()]);

    // approve tokens for gateway
    await token.approve(await gateway.getAddress(), ethers.parseEther("100"));

    const params = {
      judges: [] as string[],
      metadata: "0x",
      commissionToken: await token.getAddress(),
    };

    const prizes = [
      {
        prizeType: 0,
        token: await token.getAddress(),
        amount: ethers.parseEther("10"),
        distribution: 0,
        uri: "",
      },
    ];

    const tx = await factory.createCustomContest(prizes, params);
    const rc = await tx.wait();
    const ev = rc?.logs.find((l: any) => l.fragment && l.fragment.name === "ContestCreated");
    const contestAddr = ev?.args[1];
    const esc = await ethers.getContractAt("ContestEscrow", contestAddr);

    const fee = await esc.commissionFee();
    expect(fee).to.be.gte(ethers.parseEther("5"));
    expect(fee).to.be.lte(ethers.parseEther("10"));

    await esc.finalize([winner.address]);
    expect(await token.balanceOf(winner.address)).to.equal(ethers.parseEther("10"));

    console.log("✅ E2E passed");
  });
});
