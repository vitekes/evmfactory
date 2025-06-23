import { expect } from "chai";
import { ethers } from "hardhat";
import { deployContestFactory } from "./helpers";

async function allowToken(factory: any, registry: any, token: any) {
  const moduleId = ethers.keccak256(ethers.toUtf8Bytes("Contest"));
  const serviceId = ethers.keccak256(ethers.toUtf8Bytes("Validator"));
  const validatorAddr = await registry.getModuleService(moduleId, serviceId);
  await ethers.provider.send("hardhat_setBalance", [await factory.getAddress(), "0x21e19e0c9bab2400000"]);
  await ethers.provider.send("hardhat_impersonateAccount", [await factory.getAddress()]);
  const factorySigner = await ethers.getSigner(await factory.getAddress());
  const validator = (await ethers.getContractAt("MultiValidator", validatorAddr)) as any;
  await validator.connect(factorySigner).addToken(await token.getAddress());
  await ethers.provider.send("hardhat_stopImpersonatingAccount", [await factory.getAddress()]);
}

describe("escrow funded", function () {
  it("holds prize pool after deployment", async function () {
    const { factory, token, priceFeed, registry, gateway } = await deployContestFactory();
    await allowToken(factory, registry, token);

    await token.approve(await gateway.getAddress(), ethers.parseEther("100"));
    await token.approve(await factory.getAddress(), ethers.parseEther("100"));
    await priceFeed.setPrice(await token.getAddress(), ethers.parseEther("1"));

    const params = { judges: [] as string[], metadata: "0x", commissionToken: await token.getAddress() };
    const prizes = [
      { prizeType: 0, token: await token.getAddress(), amount: ethers.parseEther("3"), distribution: 0, uri: "" },
      { prizeType: 0, token: await token.getAddress(), amount: ethers.parseEther("2"), distribution: 0, uri: "" }
    ];

    const tx = await factory.createCustomContest(prizes, params);
    const rc = await tx.wait();
    const ev = rc?.logs.find((l: any) => l.fragment && l.fragment.name === "ContestCreated");
    const contestAddr = ev?.args[1];
    const esc = (await ethers.getContractAt("ContestEscrow", contestAddr)) as any;

    const expected = ethers.parseEther("5") + (await esc.gasPool());
    expect(await token.balanceOf(contestAddr)).to.equal(expected);
  });
});
