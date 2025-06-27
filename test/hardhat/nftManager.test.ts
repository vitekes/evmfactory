import { expect } from "chai";
import { ethers } from "hardhat";

describe("NFTManager", function () {
  let nft: any;
  let owner: any, user: any, other: any;

  beforeEach(async () => {
    [owner, user, other] = await ethers.getSigners();
    const NFT = await ethers.getContractFactory("NFTManager");
    nft = await NFT.deploy("Demo", "D");
  });

  it("mints and burns", async () => {
    await expect(nft.mint(user.address, "uri", false))
      .to.emit(nft, "Minted")
      .withArgs(user.address, 1n, "uri", false);
    expect(await nft.balanceOf(user.address)).to.equal(1n);
    await expect(nft.connect(owner).burn(1))
      .to.emit(nft, "Transfer")
      .withArgs(user.address, ethers.ZeroAddress, 1n);
    expect(await nft.balanceOf(user.address)).to.equal(0n);
  });

  it("reverts transfers without approval", async () => {
    await nft.mint(user.address, "u", false);
    await expect(
      nft.connect(other).transferFrom(user.address, other.address, 1)
    ).to.be.revertedWithCustomError(nft, "ERC721InsufficientApproval");
  });

  it("prevents transferring soulbound tokens", async () => {
    await nft.mint(user.address, "u", true);
    await expect(
      nft.connect(user).transferFrom(user.address, other.address, 1)
    ).to.be.revertedWithCustomError(nft, "SbtNonTransferable");
  });

  it("batch mint", async () => {
    const recipients = [user.address, other.address];
    const uris = ["u1", "u2"];
    await expect(nft.mintBatch(recipients, uris, false))
      .to.emit(nft, "Minted")
      .withArgs(user.address, 1n, "u1", false)
      .and.to.emit(nft, "Minted")
      .withArgs(other.address, 2n, "u2", false);
    expect(await nft.balanceOf(user.address)).to.equal(1n);
    expect(await nft.balanceOf(other.address)).to.equal(1n);
  });

  it("reverts on length mismatch", async () => {
    await expect(
      nft.mintBatch([user.address], [], false)
    ).to.be.revertedWithCustomError(nft, "LengthMismatch");
  });

  it("reverts when batch too large", async () => {
    const recipients = Array(51).fill(user.address);
    const uris = Array(51).fill("u");
    await expect(
      nft.mintBatch(recipients, uris, false)
    ).to.be.revertedWithCustomError(nft, "BatchTooLarge");
  });
});
