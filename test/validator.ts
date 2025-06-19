import { expect } from "chai";
import { ethers } from "hardhat";

describe("MultiValidator", function () {
  it("adds and removes tokens with events", async function () {
    const ACL = await ethers.getContractFactory("MockAccessControlCenter");
    const acl = await ACL.deploy();

    const Validator = await ethers.getContractFactory("MultiValidator");
    const val = await Validator.deploy();
    await val.initialize(await acl.getAddress());

    const token = "0x1000000000000000000000000000000000000001";

    await expect(val.addToken(token))
      .to.emit(val, "TokenAllowed")
      .withArgs(token, true);
    expect(await val.isAllowed(token)).to.equal(true);

    await expect(val.removeToken(token))
      .to.emit(val, "TokenAllowed")
      .withArgs(token, false);
    expect(await val.isAllowed(token)).to.equal(false);
  });
});
