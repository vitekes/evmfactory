import { ethers } from "hardhat";

async function main() {
  const [deployer, buyer, keeper, winner] = await ethers.getSigners();

  console.log("Deploying core modules...");
  const ACL = await ethers.getContractFactory("AccessControlCenter");
  const acl = await ACL.deploy();
  await acl.initialize(deployer.address);
  const FACTORY_ADMIN = ethers.keccak256(ethers.toUtf8Bytes("FACTORY_ADMIN"));
  await acl.grantRole(FACTORY_ADMIN, deployer.address);
  await acl.grantRole(await acl.FEATURE_OWNER_ROLE(), deployer.address);
  await acl.grantRole(await acl.AUTOMATION_ROLE(), keeper.address);

  const Registry = await ethers.getContractFactory("Registry");
  const registry = await Registry.deploy();
  await registry.initialize(await acl.getAddress());

  const Fee = await ethers.getContractFactory("CoreFeeManager");
  const fee = await Fee.deploy();
  await fee.initialize(await acl.getAddress());

  const Gateway = await ethers.getContractFactory("PaymentGateway");
  const gateway = await Gateway.deploy();
  await gateway.initialize(await acl.getAddress(), await registry.getAddress(), await fee.getAddress());

  const Token = await ethers.getContractFactory("TestToken");
  const token = await Token.deploy("Demo", "DEMO");
  await token.transfer(buyer.address, ethers.parseEther("100"));

  console.log("Deploying feature modules...");
  const Validator = await ethers.getContractFactory("MultiValidator");
  const marketValidator: any = await Validator.deploy();
  await acl.grantRole(await acl.DEFAULT_ADMIN_ROLE(), await marketValidator.getAddress());
  await marketValidator.initialize(await acl.getAddress());
  await acl.revokeRole(await acl.DEFAULT_ADMIN_ROLE(), await marketValidator.getAddress());
  await marketValidator.addToken(await token.getAddress());

  const subValidator: any = await Validator.deploy();
  await acl.grantRole(await acl.DEFAULT_ADMIN_ROLE(), await subValidator.getAddress());
  await subValidator.initialize(await acl.getAddress());
  await acl.revokeRole(await acl.DEFAULT_ADMIN_ROLE(), await subValidator.getAddress());
  await subValidator.addToken(await token.getAddress());

  const ContestFactory = await ethers.getContractFactory("ContestFactory");
  const contestFactory = await ContestFactory.deploy(
    await registry.getAddress(),
    await gateway.getAddress()
  );

  const Marketplace = await ethers.getContractFactory("Marketplace");
  const MARKET_ID = ethers.keccak256(ethers.toUtf8Bytes("Market"));
  const market = await Marketplace.deploy(await registry.getAddress(), await gateway.getAddress(), MARKET_ID);
  await registry.setModuleServiceAlias(MARKET_ID, "Validator", await marketValidator.getAddress());

  const SubManager = await ethers.getContractFactory("SubscriptionManager");
  const SUB_ID = ethers.keccak256(ethers.toUtf8Bytes("Sub"));
  const sub = await SubManager.deploy(await registry.getAddress(), await gateway.getAddress(), SUB_ID);
  await registry.setModuleServiceAlias(SUB_ID, "Validator", await subValidator.getAddress());

  console.log("Running marketplace demo...");
  const listingIdTx = await market.list(await token.getAddress(), ethers.parseEther("1"));
  const listingId = (await listingIdTx.wait())?.logs[0].args[0];
  await token.connect(buyer).approve(await gateway.getAddress(), ethers.parseEther("1"));
  await market.connect(buyer).buy(listingId);
  console.log("Buyer purchased listing");

  console.log("Running subscription demo...");
  const plan = {
    chainIds: [31337n],
    price: ethers.parseEther("2"),
    period: 60n,
    token: await token.getAddress(),
    merchant: deployer.address,
    salt: 1n,
    expiry: 0n,
  } as const;
  const planHash = await sub.hashPlan(plan);
  const sigMerchant = await deployer.signMessage(ethers.getBytes(planHash));
  await token.connect(buyer).approve(await gateway.getAddress(), plan.price);
  await sub.connect(buyer).subscribe(plan, sigMerchant, "0x");
  await ethers.provider.send("evm_increaseTime", [61]);
  await ethers.provider.send("evm_mine", []);
  await sub.connect(keeper).chargeBatch([buyer.address]);
  console.log("Subscription charged");

  console.log("Running contest demo...");
  const params = { judges: [] as string[], metadata: "0x", commissionToken: await token.getAddress() };
  await token.approve(await gateway.getAddress(), ethers.parseEther("20"));
  const prizes = [
    { prizeType: 0, token: await token.getAddress(), amount: ethers.parseEther("10"), distribution: 0, uri: "" },
    { prizeType: 0, token: await token.getAddress(), amount: ethers.parseEther("5"), distribution: 0, uri: "" },
  ];
  const tx = await contestFactory.createContest(prizes, params);
  const rc = await tx.wait();
  const created = rc?.logs.find(l => l.fragment && l.fragment.name === "ContestCreated");
  const contestAddr = created?.args[1];
  const esc = (await ethers.getContractAt("ContestEscrow", contestAddr)) as any;
  await gateway.connect(winner); // just to silence ts
  await esc.finalize([winner.address, deployer.address], 0n);
  console.log("Contest finalized, winner balance:", (await token.balanceOf(winner.address)).toString());
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
