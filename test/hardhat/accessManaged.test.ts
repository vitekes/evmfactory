import { expect } from "chai";
import { ethers } from "hardhat";

describe("AccessManaged", function () {
  let acc: any;
  let test: any;
  beforeEach(async () => {
    const ACC = await ethers.getContractFactory("MockAccessControlCenter");
    acc = await ACC.deploy();
    const Test = await ethers.getContractFactory("TestAccessManaged");
    test = await Test.deploy(await acc.getAddress());
  });

  it("grants self roles", async () => {
    await expect(test.grantSelf()).to.not.be.reverted;
  });

  it("allows calls with correct role", async () => {
    await expect(test.restricted()).to.not.be.reverted;
  });

  it("reverts for wrong role", async () => {
    await expect(test.restrictedOther()).to.be.revertedWithCustomError(test, "Forbidden");
  });
});
