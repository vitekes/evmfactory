import { expect } from "chai";
import { ethers } from "hardhat";
import { deployContestFactory } from "./helpers";

describe("ContestFactory fee", function () {
  it("uses price feed for commission", async function () {
    const [creator] = await ethers.getSigners();
    const { factory, token, priceFeed, gateway } = await deployContestFactory();

    const params = {
      judges: [] as string[],
      metadata: "0x",
      commissionToken: await token.getAddress(),
    };

    // Approve factory to pull tokens via gateway mock
  await token.approve(await gateway.getAddress(), ethers.parseEther("100"));
  await token.approve(await factory.getAddress(), ethers.parseEther("100"));

    // test price 0.95 USD
    await priceFeed.setPrice(await token.getAddress(), ethers.parseEther("0.95"));
    let tx = await factory.createCustomContest([], params);
    let rc = await tx.wait();
    let ev = rc?.logs.find((l: any) => l.fragment && l.fragment.name === "ContestCreated");
    const contestAddr1 = ev?.args[1];
    const esc1 = (await ethers.getContractAt("ContestEscrow", contestAddr1)) as any;
    let fee1 = await esc1.commissionFee();
    expect(fee1).to.be.gte(ethers.parseEther("5"));
    expect(fee1).to.be.lte(ethers.parseEther("10"));

    // test price 1.05 USD
    await priceFeed.setPrice(await token.getAddress(), ethers.parseEther("1.05"));
    tx = await factory.createCustomContest([], params);
    rc = await tx.wait();
    ev = rc?.logs.find((l: any) => l.fragment && l.fragment.name === "ContestCreated");
    const contestAddr2 = ev?.args[1];
    const esc2 = (await ethers.getContractAt("ContestEscrow", contestAddr2)) as any;
    let fee2 = await esc2.commissionFee();
    expect(fee2).to.be.gte(ethers.parseEther("5"));
    expect(fee2).to.be.lte(ethers.parseEther("10"));
  });
});
