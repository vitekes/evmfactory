import { expect } from "chai";
import { ethers } from "hardhat";
import { deployContestFactory } from "./helpers";

// simple test for direct deploy without prefunding

describe("direct deploy fails if no tokens", function () {
  it("reverts constructor", async function () {
    const [creator] = await ethers.getSigners();
    const { registry, token } = await deployContestFactory();
    const prizes = [
      { prizeType: 0, token: await token.getAddress(), amount: ethers.parseEther("1"), distribution: 0, uri: "" }
    ];
    const Escrow = await ethers.getContractFactory("ContestEscrow");
    await expect(
      Escrow.deploy(await registry.getAddress(), creator.address, prizes, await token.getAddress(), 0, 0, [], "0x")
    ).to.be.revertedWithCustomError(Escrow, "ContestFundingMissing");
  });
});
