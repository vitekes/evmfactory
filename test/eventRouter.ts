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

  it("parses payload for each kind", async function () {
    const [owner] = await ethers.getSigners();

    const ACC = await ethers.getContractFactory("AccessControlCenter");
    const acc = await ACC.deploy();
    await acc.initialize(owner.address);
    await acc.grantRole(await acc.MODULE_ROLE(), owner.address);

    const Router = await ethers.getContractFactory("EventRouter");
    const router = await Router.deploy();
    await router.initialize(await acc.getAddress());

    const coder = ethers.AbiCoder.defaultAbiCoder();

    // ListingCreated
    const payloadListing = coder.encode(
      ["uint256", "address", "address", "uint256"],
      [1n, owner.address, ethers.ZeroAddress, 42n]
    );
    let tx = await router.route(1, payloadListing);
    let rc = await tx.wait();
    let ev = rc?.logs.find((l: any) => l.fragment && l.fragment.name === "EventRouted");
    expect(ev?.args.kind).to.equal(1);
    const [id, seller, token, price] = coder.decode(
      ["uint256", "address", "address", "uint256"],
      ev?.args.payload
    );
    expect(id).to.equal(1n);
    expect(seller).to.equal(owner.address);
    expect(token).to.equal(ethers.ZeroAddress);
    expect(price).to.equal(42n);

    // PlanCancelled
    const planHash = ethers.keccak256(ethers.toUtf8Bytes("plan"));
    const payloadPlan = coder.encode(["address", "bytes32", "uint256"], [owner.address, planHash, 7n]);
    tx = await router.route(2, payloadPlan);
    rc = await tx.wait();
    ev = rc?.logs.find((l: any) => l.fragment && l.fragment.name === "EventRouted");
    expect(ev?.args.kind).to.equal(2);
    const [user, ph, ts] = coder.decode(["address", "bytes32", "uint256"], ev?.args.payload);
    expect(user).to.equal(owner.address);
    expect(ph).to.equal(planHash);
    expect(ts).to.equal(7n);

    // ContestFinalized
    const winners = [owner.address];
    const prizes = [
      {
        prizeType: 0,
        token: owner.address,
        amount: 10n,
        distribution: 0,
        uri: "ipfs://1",
      },
    ];
    const payloadContest = coder.encode(
      [
        "address",
        "address[]",
        "tuple(uint8 prizeType,address token,uint256 amount,uint8 distribution,string uri)[]",
      ],
      [owner.address, winners, prizes]
    );
    tx = await router.route(3, payloadContest);
    rc = await tx.wait();
    ev = rc?.logs.find((l: any) => l.fragment && l.fragment.name === "EventRouted");
    expect(ev?.args.kind).to.equal(3);
    const decoded = coder.decode(
      [
        "address",
        "address[]",
        "tuple(uint8 prizeType,address token,uint256 amount,uint8 distribution,string uri)[]",
      ],
      ev?.args.payload
    );
    expect(decoded[0]).to.equal(owner.address);
    expect(decoded[1][0]).to.equal(owner.address);
    expect(decoded[2][0].amount).to.equal(10n);
  });
});
