import { expect } from "chai";
import { ethers } from "hardhat";

describe("ContestEscrow", function () {
  let token: any;
  let escrow: any;
  let deployer: any, creator: any, w1: any, w2: any;
  let deadline: number;

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
    deadline = (latestBlock!).timestamp + 86400;
    escrow = await Escrow.connect(deployer).deploy(creator.address, prizes, await registry.getAddress(), 0, await token.getAddress(), deadline);
    await token.transfer(await escrow.getAddress(), ethers.parseEther("150"));
  });

  it("finalize distributes prizes", async () => {
    await escrow.connect(creator).finalize([w1.address, w2.address], 0, 0);
    expect(await token.balanceOf(w1.address)).to.equal(ethers.parseEther("100"));
    expect(await token.balanceOf(w2.address)).to.equal(ethers.parseEther("50"));
    expect(await escrow.finalized()).to.equal(true);
  });

  it("reverts with wrong winners count", async () => {
    await expect(
      escrow.connect(creator).finalize([w1.address], 0, 0)
    ).to.be.revertedWithCustomError(escrow, "WrongWinnersCount");
  });

  it("creator can cancel and retrieve funds", async () => {
    await escrow.connect(creator).cancel();
    expect(await token.balanceOf(creator.address)).to.equal(
      ethers.parseEther("150")
    );
    expect(await escrow.finalized()).to.equal(true);
  });

  it("emergency withdraw after grace period", async () => {
    await ethers.provider.send("evm_setNextBlockTimestamp", [
      deadline + 30 * 24 * 60 * 60 + 1,
    ]);
    await ethers.provider.send("evm_mine", []);
    await escrow.connect(creator).emergencyWithdraw();
    expect(await token.balanceOf(creator.address)).to.equal(
      ethers.parseEther("150")
    );
    expect(await escrow.finalized()).to.equal(true);
  });

  it("emergency withdraw before grace period reverts", async () => {
    await expect(
      escrow.connect(creator).emergencyWithdraw()
    ).to.be.revertedWithCustomError(escrow, "GracePeriodNotExpired");
  });
});
