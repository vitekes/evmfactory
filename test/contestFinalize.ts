import { expect } from "chai";
import { ethers, network } from "hardhat";

async function deployFactory() {
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

async function allowToken(factory: any, registry: any, token: any) {
  const moduleId = ethers.keccak256(ethers.toUtf8Bytes("Contest"));
  const validatorAddr = await registry.getModuleService(moduleId, "Validator");
  await network.provider.send("hardhat_impersonateAccount", [await factory.getAddress()]);
  const factorySigner = await ethers.getSigner(await factory.getAddress());
  const validator = await ethers.getContractAt("MultiValidator", validatorAddr);
  await validator.connect(factorySigner).addToken(await token.getAddress());
  await network.provider.send("hardhat_stopImpersonatingAccount", [await factory.getAddress()]);
}

function getCreatedContest(rc: any) {
  const ev = rc?.logs.find((l: any) => l.fragment && l.fragment.name === "ContestCreated");
  return ev?.args[1];
}

describe("Contest finalize", function () {
  it("handles multiple prizes", async function () {
    const [creator, a, b, c] = await ethers.getSigners();
    const { factory, token, priceFeed, registry, gateway } = await deployFactory();

    await allowToken(factory, registry, token);

    await token.approve(await gateway.getAddress(), ethers.parseEther("1000"));
    await priceFeed.setPrice(await token.getAddress(), ethers.parseEther("1"));

    const params = { judges: [] as string[], metadata: "0x", commissionToken: await token.getAddress() };
    const prizes = [
      { prizeType: 0, token: await token.getAddress(), amount: ethers.parseEther("10"), distribution: 0, uri: "" },
      { prizeType: 0, token: await token.getAddress(), amount: ethers.parseEther("5"), distribution: 0, uri: "" },
      { prizeType: 1, token: ethers.ZeroAddress, amount: 0, distribution: 0, uri: "ipfs://promo" }
    ];

    const tx = await factory.createCustomContest(prizes, params);
    const rc = await tx.wait();
    const contestAddr = getCreatedContest(rc);
    const esc = await ethers.getContractAt("ContestEscrow", contestAddr);

    const balA0 = await token.balanceOf(a.address);
    const balB0 = await token.balanceOf(b.address);

    const finalizeTx = await esc.finalize([a.address, b.address, c.address]);
    await expect(finalizeTx).to.emit(esc, "MonetaryPrizePaid").withArgs(a.address, ethers.parseEther("10"));
    await expect(finalizeTx).to.emit(esc, "MonetaryPrizePaid").withArgs(b.address, ethers.parseEther("5"));
    await expect(finalizeTx).to.emit(esc, "PromoPrizeIssued").withArgs(2, c.address, "ipfs://promo");

    expect(await token.balanceOf(a.address)).to.equal(balA0 + ethers.parseEther("10"));
    expect(await token.balanceOf(b.address)).to.equal(balB0 + ethers.parseEther("5"));

    expect(await esc.isFinalized()).to.equal(true);
    expect(await esc.winners(0)).to.equal(a.address);
    expect(await esc.winners(1)).to.equal(b.address);
    expect(await esc.winners(2)).to.equal(c.address);
  });

  it("reverts on wrong winners count", async function () {
    const [creator, a, b, c] = await ethers.getSigners();
    const { factory, token, priceFeed, registry, gateway } = await deployFactory();
    await allowToken(factory, registry, token);

    await token.approve(await gateway.getAddress(), ethers.parseEther("1000"));
    await priceFeed.setPrice(await token.getAddress(), ethers.parseEther("1"));

    const params = { judges: [] as string[], metadata: "0x", commissionToken: await token.getAddress() };
    const prizes = [
      { prizeType: 0, token: await token.getAddress(), amount: ethers.parseEther("1"), distribution: 0, uri: "" },
      { prizeType: 0, token: await token.getAddress(), amount: ethers.parseEther("1"), distribution: 0, uri: "" },
      { prizeType: 1, token: ethers.ZeroAddress, amount: 0, distribution: 0, uri: "uri" }
    ];

    const tx = await factory.createCustomContest(prizes, params);
    const rc = await tx.wait();
    const contestAddr = getCreatedContest(rc);
    const esc = await ethers.getContractAt("ContestEscrow", contestAddr);

    await expect(esc.finalize([a.address, b.address])).to.be.revertedWithCustomError(esc, "WrongWinnersCount");
  });

  it("refunds gas to creator", async function () {
    if (!network.config.forking?.url) {
      console.log("Skipping: not a forked network");
      this.skip();
    }

    const [creator, a] = await ethers.getSigners();
    await network.provider.send("hardhat_setBalance", [creator.address, "0x21e19e0c9bab2400000"]);

    const { factory, token, priceFeed, registry, gateway } = await deployFactory();
    await allowToken(factory, registry, token);

    await token.approve(await gateway.getAddress(), ethers.parseEther("1000"));
    await priceFeed.setPrice(await token.getAddress(), ethers.parseEther("1"));

    const params = { judges: [] as string[], metadata: "0x", commissionToken: await token.getAddress() };
    const prizes = [
      { prizeType: 0, token: await token.getAddress(), amount: ethers.parseEther("1"), distribution: 0, uri: "" }
    ];

    const tx = await factory.createCustomContest(prizes, params);
    const rc = await tx.wait();
    const contestAddr = getCreatedContest(rc);
    const esc = await ethers.getContractAt("ContestEscrow", contestAddr);

    const balBefore = await token.balanceOf(creator.address);
    const gasPoolBefore = await esc.gasPool();
    const finalizeTx = await esc.finalize([a.address], { gasPrice: 1_000_000_000 });
    const receipt = await finalizeTx.wait();
    const refunded = receipt?.logs.find((l: any) => l.fragment && l.fragment.name === "GasRefunded");
    expect(refunded).to.not.be.undefined;
    expect(await token.balanceOf(creator.address)).to.be.gt(balBefore);
    expect(await esc.gasPool()).to.be.lt(gasPoolBefore);
  });
});

