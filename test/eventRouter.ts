import { expect } from "chai";
import { ethers } from "hardhat";

describe("EventRouter", function () {
  it("reverts on unknown kind", async function () {
    const [owner] = await ethers.getSigners();

    const ACC = await ethers.getContractFactory("AccessControlCenter");
    const acc = await ACC.deploy();
    await acc.initialize(owner.address);
    await acc.grantRole(await acc.MODULE_ROLE(), owner.address);

    const Router = await ethers.getContractFactory("EventRouter");
    const router = await Router.deploy();
    await router.initialize(await acc.getAddress());

    await expect(router.route(0, "0x")).to.be.revertedWithCustomError(
      router,
      "InvalidKind"
    );
  });
});
