import { expect } from "chai";
import { ethers } from "hardhat";

describe("ContestEscrow", function () {
  let token: any;
  let escrow: any;
  let deployer: any, creator: any, w1: any, w2: any;

  beforeEach(async () => {
    [deployer, creator, w1, w2] = await ethers.getSigners();

    const Token = await ethers.getContractFactory("TestToken");
    token = await Token.deploy("T", "T");

    const Registry = await ethers.getContractFactory("MockRegistry");
    const registry = await Registry.deploy();

    const prizes = [
      { prizeType: 0, token: await token.getAddress(), amount: ethers.parseEther("100"), distribution: 0, uri: "" },
      { prizeType: 0, token: await token.getAddress(), amount: ethers.parseEther("50"), distribution: 0, uri: "" },
    ];

    const Escrow = await ethers.getContractFactory("ContestEscrow");
    const latestBlock = await ethers.provider.getBlock("latest");
    const deadline = (latestBlock!).timestamp + 86400;
    escrow = await Escrow.connect(deployer).deploy(creator.address, prizes, await registry.getAddress(), 0, await token.getAddress(), deadline);
    await token.transfer(await escrow.getAddress(), ethers.parseEther("150"));
  });

  it("finalize distributes prizes", async () => {
    await escrow.connect(creator).finalize([w1.address, w2.address], 0, 0);
    expect(await token.balanceOf(w1.address)).to.equal(ethers.parseEther("100"));
    expect(await token.balanceOf(w2.address)).to.equal(ethers.parseEther("50"));
    expect(await escrow.finalized()).to.equal(true);
  });
});
