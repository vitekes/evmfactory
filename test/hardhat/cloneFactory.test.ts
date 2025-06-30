import { expect } from "chai";
import { ethers } from "hardhat";

describe("CloneFactory", function () {
  let factory: any;
  let template: any;

  beforeEach(async () => {
    const Factory = await ethers.getContractFactory("TestCloneFactory");
    factory = await Factory.deploy();

    const Template = await ethers.getContractFactory("DummyTemplate");
    template = await Template.deploy();
  });

  it("clones template and initializes", async () => {
    const salt = ethers.keccak256(ethers.toUtf8Bytes("one"));
    const initData = new ethers.Interface(["function init(uint256)"]).encodeFunctionData("init", [42]);
    const predicted = await factory.predict(await template.getAddress(), salt);
    await expect(factory.clone(await template.getAddress(), salt, initData))
      .to.emit(factory, "Cloned")
      .withArgs(await template.getAddress(), predicted);
    const cloneAddr = await factory.predict(await template.getAddress(), salt);
    const clone = await ethers.getContractAt("DummyTemplate", cloneAddr);
    expect(await clone.value()).to.equal(42n);
    const code = await ethers.provider.getCode(cloneAddr);
    expect(code.length / 2 - 1).to.equal(45); // hex string length minus 0x
  });

  it("reverts on init failure", async () => {
    const salt = ethers.keccak256(ethers.toUtf8Bytes("two"));
    const initData = new ethers.Interface(["function init(uint256)"]).encodeFunctionData("init", [0]);
    await expect(factory.clone(await template.getAddress(), salt, initData))
      .to.be.revertedWithCustomError(template, "InitFailed");
  });

  it("different salts produce different addresses", async () => {
    const salt1 = ethers.zeroPadValue("0x01", 32);
    const salt2 = ethers.zeroPadValue("0x02", 32);
    const initData = new ethers.Interface(["function init(uint256)"]).encodeFunctionData("init", [1]);
    const c1 = await factory.clone(await template.getAddress(), salt1, initData);
    const c2 = await factory.clone(await template.getAddress(), salt2, initData);
    expect(c1).to.not.equal(c2);
  });

  it("returns existing clone on subsequent calls", async () => {
    const salt = ethers.keccak256(ethers.toUtf8Bytes("repeat"));
    const initData = new ethers.Interface(["function init(uint256)"]).encodeFunctionData("init", [123]);
    const predicted = await factory.predict(await template.getAddress(), salt);
    await factory.clone(await template.getAddress(), salt, initData);
    await factory.clone(await template.getAddress(), salt, "0x");
    const clone = await ethers.getContractAt("DummyTemplate", predicted);
    expect(await clone.value()).to.equal(123n);
  });
});
