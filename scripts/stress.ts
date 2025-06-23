import { ethers, network } from "hardhat";

async function deployCore(useAutomation = false) {
  const Token = await ethers.getContractFactory("TestToken");
  const token = await Token.deploy("USD Coin", "USDC");

  const ACL = await ethers.getContractFactory(
    useAutomation ? "MockAccessControlCenterAuto" : "MockAccessControlCenter"
  );
  const acl = await ACL.deploy();

  const Registry = await ethers.getContractFactory("MockRegistry");
  const registry = await Registry.deploy();
  await registry.setCoreService(
    ethers.keccak256(Buffer.from("AccessControlCenter")),
    await acl.getAddress()
  );

  const Gateway = await ethers.getContractFactory("MockPaymentGateway");
  const gateway = await Gateway.deploy();

  const PriceFeed = await ethers.getContractFactory("MockPriceFeed");
  const priceFeed = await PriceFeed.deploy();

  const Validator = await ethers.getContractFactory("MultiValidator");
  const validatorLogic = await Validator.deploy();

  const Factory = await ethers.getContractFactory("ContestFactory");
  const factory = await Factory.deploy(
    await registry.getAddress(),
    await gateway.getAddress(),
    await validatorLogic.getAddress()
  );

  await factory.setPriceFeed(await priceFeed.getAddress());
  await factory.setUsdFeeBounds(
    ethers.parseEther("5"),
    ethers.parseEther("10")
  );

  return { factory, token, priceFeed, registry, gateway, acl };
}

async function allowToken(factory: any, registry: any, token: any) {
  const moduleId = ethers.keccak256(ethers.toUtf8Bytes("Contest"));
  const validatorAddr = await registry.getModuleService(moduleId, "Validator");
  await network.provider.request({
    method: "hardhat_impersonateAccount",
    params: [await factory.getAddress()],
  });
  const signer = await ethers.getSigner(await factory.getAddress());
  const validator = (await ethers.getContractAt("MultiValidator", validatorAddr)) as any;
  await validator.connect(signer).addToken(await token.getAddress());
  await network.provider.request({
    method: "hardhat_stopImpersonatingAccount",
    params: [await factory.getAddress()],
  });
}

function getCreatedContest(rc: any) {
  const ev = rc?.logs.find(
    (l: any) => l.fragment && l.fragment.name === "ContestCreated"
  );
  return ev?.args[1];
}

async function massFinalize(count = 1000) {
  const [creator] = await ethers.getSigners();
  const { factory, token, priceFeed, registry, gateway } = await deployCore();
  await allowToken(factory, registry, token);

  await token.approve(await gateway.getAddress(), ethers.parseEther("1000000"));
  await priceFeed.setPrice(await token.getAddress(), ethers.parseEther("1"));

  const params = {
    judges: [] as string[],
    metadata: "0x",
    commissionToken: await token.getAddress(),
  };
  const prizes = [
    {
      prizeType: 0,
      token: await token.getAddress(),
      amount: ethers.parseEther("1"),
      distribution: 0,
      uri: "",
    },
  ];

  const contests: string[] = [];
  console.log(`Creating ${count} contests...`);
  for (let i = 0; i < count; i++) {
    const tx = await factory.createCustomContest(prizes, params);
    const rc = await tx.wait();
    contests.push(getCreatedContest(rc));
  }

  console.log("Finalizing contests...");
  for (const addr of contests) {
    const esc = (await ethers.getContractAt("ContestEscrow", addr)) as any;
    const poolBefore = await esc.gasPool();
    await (await esc.finalize([creator.address])).wait();
    const poolAfter = await esc.gasPool();
    console.log(`Finalized ${addr} gasPool ${poolBefore} -> ${poolAfter}`);
  }
}

async function batchCharge(users = 10000, chunk = 100) {
  const [owner, merchant] = await ethers.getSigners();
  const Token = await ethers.getContractFactory("TestToken");
  const token = await Token.deploy("Test", "TST");

  const ACL = await ethers.getContractFactory("MockAccessControlCenterAuto");
  const acl = await ACL.deploy();

  const Registry = await ethers.getContractFactory("MockRegistry");
  const registry = await Registry.deploy();
  await registry.setCoreService(
    ethers.keccak256(Buffer.from("AccessControlCenter")),
    await acl.getAddress()
  );

  const Gateway = await ethers.getContractFactory("MockPaymentGateway");
  const gateway = await Gateway.deploy();

  const moduleId = ethers.keccak256(ethers.toUtf8Bytes("Sub"));
  const Manager = await ethers.getContractFactory("SubscriptionManager");
  const manager = await Manager.deploy(
    await registry.getAddress(),
    await gateway.getAddress(),
    moduleId
  );

  const plan = {
    chainIds: [31337n],
    price: ethers.parseEther("1"),
    period: 100n,
    token: await token.getAddress(),
    merchant: merchant.address,
    salt: 1n,
    expiry: 0n,
  } as const;
  const planHash = await manager.hashPlan(plan);
  const sigMerchant = await merchant.signMessage(ethers.getBytes(planHash));

  const wallets: any[] = [];
  for (let i = 0; i < users; i++) {
    const w = ethers.Wallet.createRandom().connect(ethers.provider);
    wallets.push(w);
    await owner.sendTransaction({ to: w.address, value: ethers.parseEther("1") });
    await token.transfer(w.address, ethers.parseEther("5"));
    await token.connect(w).approve(await gateway.getAddress(), ethers.parseEther("5"));
    await manager.connect(w).subscribe(plan, sigMerchant, "0x");
  }

  await manager.setBatchLimit(chunk);

  console.log(`Charging ${users} subscribers in batches of ${chunk}`);
  for (let i = 0; i < users; i += chunk) {
    const slice = wallets.slice(i, i + chunk).map((w) => w.address);
    await (await manager.chargeBatch(slice)).wait();
    console.log(`Charged ${i}..${i + slice.length - 1}`);
  }
}

async function parallelBuys(buyers = 500) {
  const [seller] = await ethers.getSigners();
  const Token = await ethers.getContractFactory("TestToken");
  const token = await Token.deploy("Sale", "SALE");

  const ACL = await ethers.getContractFactory("MockAccessControlCenterAuto");
  const acl = await ACL.deploy();

  const Registry = await ethers.getContractFactory("MockRegistry");
  const registry = await Registry.deploy();
  await registry.setCoreService(
    ethers.keccak256(Buffer.from("AccessControlCenter")),
    await acl.getAddress()
  );

  const Gateway = await ethers.getContractFactory("MockPaymentGateway");
  const gateway = await Gateway.deploy();

  const moduleId = ethers.keccak256(ethers.toUtf8Bytes("Market"));
  const Market = await ethers.getContractFactory("Marketplace");
  const market = await Market.deploy(
    await registry.getAddress(),
    await gateway.getAddress(),
    moduleId
  );

  const listingTx = await market.list(await token.getAddress(), ethers.parseEther("1"));
  const rc = await listingTx.wait();
  const ev = rc?.logs.find((l: any) => l.fragment && l.fragment.name === "MarketplaceListingCreated");
  const listingId = ev?.args[0];

  const wallets: any[] = [];
  for (let i = 0; i < buyers; i++) {
    const w = ethers.Wallet.createRandom().connect(ethers.provider);
    wallets.push(w);
    await seller.sendTransaction({ to: w.address, value: ethers.parseEther("1") });
    await token.transfer(w.address, ethers.parseEther("2"));
    await token.connect(w).approve(await gateway.getAddress(), ethers.parseEther("2"));
  }

  console.log(`Executing ${buyers} parallel purchases...`);
  await Promise.all(
    wallets.map(async (w) => {
      const tx = await market.connect(w).buy(listingId);
      await tx.wait();
    })
  );
  console.log("All purchases processed");
}

async function storageGrowth(entries = 5000) {
  const Storage = await ethers.getContractFactory("ResourceStorage");
  const storage = await Storage.deploy();

  let gasFirst = await storage.setResource.estimateGas(1, "init", "0");
  for (let i = 0; i < entries; i++) {
    await storage.setResource(1, `key${i}`, `val${i}`);
  }
  let gasLast = await storage.setResource.estimateGas(1, `key${entries}`, "val");
  console.log(`Gas first: ${gasFirst} last: ${gasLast}`);
}

async function main() {
  const scenario = process.argv[2];
  switch (scenario) {
    case "contest":
      await massFinalize(parseInt(process.env.COUNT || "1000"));
      break;
    case "subscription":
      await batchCharge(
        parseInt(process.env.USERS || "10000"),
        parseInt(process.env.CHUNK || "100")
      );
      break;
    case "market":
      await parallelBuys(parseInt(process.env.BUYERS || "500"));
      break;
    case "storage":
      await storageGrowth(parseInt(process.env.ENTRIES || "5000"));
      break;
    default:
      console.log("Specify scenario: contest | subscription | market | storage");
  }
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
