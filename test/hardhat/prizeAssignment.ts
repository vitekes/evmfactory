import { expect } from "chai";
import { ethers } from "hardhat";
import { deployContestFactory } from "./helpers";

describe("PrizeAssigned event", function () {
  it("emits for non monetary prize", async function () {
    const [creator, winner] = await ethers.getSigners();
    const { factory, token, priceFeed, gateway, registry } = await deployContestFactory();

    const params = {
      judges: [] as string[],
      metadata: "0x",
      commissionToken: await token.getAddress(),
    };

    await token.approve(await gateway.getAddress(), ethers.parseEther("100"));
    await priceFeed.setPrice(await token.getAddress(), ethers.parseEther("1"));

    const prizes = [
      {
        prizeType: 1,
        token: ethers.ZeroAddress,
        amount: 0,
        distribution: 0,
        uri: "ipfs://swag"
      }
    ];

    const tx = await factory.createCustomContest(prizes, params);
    const rc = await tx.wait();
    const ev = rc?.logs.find((l: any) => l.fragment && l.fragment.name === "ContestCreated");
    const contestAddr = ev?.args[1];
    const esc = await ethers.getContractAt("ContestEscrow", contestAddr);

    const moduleId = ethers.keccak256(ethers.toUtf8Bytes("Contest"));
    await registry.setModuleServiceAlias(moduleId, "EventRouter", winner.address);
    await registry.setModuleServiceAlias(moduleId, "NFTManager", winner.address);

    const finalizeTx = await esc.finalize([winner.address]);
    const receipt = await finalizeTx.wait();
    const assigned = receipt?.logs.find((l: any) => l.fragment && l.fragment.name === "PrizeAssigned");
    expect(assigned.args[0]).to.equal(winner.address);
    expect(assigned.args[1]).to.equal("ipfs://swag");
  });
});
