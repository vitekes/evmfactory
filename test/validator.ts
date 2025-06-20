import { expect } from "chai";
import { ethers } from "hardhat";

describe("MultiValidator", function () {
  it("adds and removes tokens with events", async function () {
    const [admin] = await ethers.getSigners();

    const ACL = await ethers.getContractFactory("AccessControlCenter");
    const acl = await ACL.deploy();
    await acl.initialize(admin.address);

    const Validator = await ethers.getContractFactory("MultiValidator");
    const val = await Validator.deploy();

    // allow validator to grant roles during initialize
    await acl.grantRole(await acl.DEFAULT_ADMIN_ROLE(), await val.getAddress());
    await val.initialize(await acl.getAddress());

    expect(await acl.hasRole(await acl.GOVERNOR_ROLE(), admin.address)).to.equal(true);

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

  it("reverts for non governor", async function () {
    const [admin, attacker] = await ethers.getSigners();

    const ACL = await ethers.getContractFactory("AccessControlCenter");
    const acl = await ACL.deploy();
    await acl.initialize(admin.address);

    const Validator = await ethers.getContractFactory("MultiValidator");
    const val = await Validator.deploy();

    await acl.grantRole(await acl.DEFAULT_ADMIN_ROLE(), await val.getAddress());
    await val.initialize(await acl.getAddress());

    await expect(
      val.connect(attacker).addToken("0x2000000000000000000000000000000000000002")
    ).to.be.revertedWithCustomError(val, "Forbidden");
  });
});
