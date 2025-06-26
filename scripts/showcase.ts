import { ethers, network } from "hardhat";

async function deployCore() {
  const Token = await ethers.getContractFactory("TestToken");
  const token = await Token.deploy("USD Coin", "USDC");

  const ACL = await ethers.getContractFactory("MockAccessControlCenter");
  const acl = await ACL.deploy();

  const Registry = await ethers.getContractFactory("MockRegistry");
  const registry = await Registry.deploy();
  await registry.setCoreService(ethers.keccak256(Buffer.from("AccessControlCenter")), await acl.getAddress());

  const Gateway = await ethers.getContractFactory("MockPaymentGateway");
  const gateway = await Gateway.deploy();

  const PriceFeed = await ethers.getContractFactory("MockPriceFeed");
  const priceFeed = await PriceFeed.deploy();

  const Validator = await ethers.getContractFactory("MultiValidator");
  const validatorLogic = await Validator.deploy();

  const Factory = await ethers.getContractFactory("ContestFactory");
  const factory = await Factory.deploy(await registry.getAddress(), await gateway.getAddress(), await validatorLogic.getAddress());

  await factory.setPriceFeed(await priceFeed.getAddress());
  await factory.setUsdFeeBounds(ethers.parseEther("5"), ethers.parseEther("10"));

  return { factory, token, priceFeed, registry, gateway };
}

async function allowToken(factory: any, registry: any, token: any) {
  const moduleId = ethers.keccak256(ethers.toUtf8Bytes("Contest"));
  const validatorAddr = await registry.getModuleService(moduleId, "Validator");
  await network.provider.request({ method: "hardhat_impersonateAccount", params: [await factory.getAddress()] });
  const signer = await ethers.getSigner(await factory.getAddress());
  const validator = (await ethers.getContractAt("MultiValidator", validatorAddr)) as any;
  await validator.connect(signer).addToken(await token.getAddress());
  await network.provider.request({ method: "hardhat_stopImpersonatingAccount", params: [await factory.getAddress()] });
}

function getCreatedContest(rc: any) {
  const ev = rc?.logs.find((l: any) => l.fragment && l.fragment.name === "ContestCreated");
  return ev?.args[1]; // Возвращаем адрес контеста (индекс 1)
}

function getContestDeadline(rc: any) {
  const ev = rc?.logs.find((l: any) => l.fragment && l.fragment.name === "ContestCreated");
  return ev?.args[2]; // Возвращаем дедлайн (индекс 2)
}

async function main() {
  const [, addr1, addr2, addr3] = await ethers.getSigners();
  const { factory, token, priceFeed, registry, gateway } = await deployCore();
  await allowToken(factory, registry, token);

  await token.approve(await gateway.getAddress(), ethers.parseEther("1000"));
  await priceFeed.setPrice(await token.getAddress(), ethers.parseEther("1"));

  const params = { judges: [] as string[], metadata: "0x", commissionToken: await token.getAddress() };
  const prizes = [
    { prizeType: 0, token: await token.getAddress(), amount: ethers.parseEther("10"), distribution: 0, uri: "" },
    { prizeType: 0, token: await token.getAddress(), amount: ethers.parseEther("5"), distribution: 0, uri: "" },
    { prizeType: 1, token: ethers.ZeroAddress, amount: 0, distribution: 0, uri: "ipfs://promo" }
  ];

  const tx = await factory.createCustomContest(prizes, params);
  const rc = await tx.wait();
  const contestAddr = getCreatedContest(rc);
  const escrow = (await ethers.getContractAt("ContestEscrow", contestAddr)) as any;
  console.log("Contest escrow:", contestAddr);

  const finalizeTx = await escrow.finalize([addr1.address, addr2.address, addr3.address], 0n);
  const receipt = await finalizeTx.wait();

  console.log("Finalize events:");
  for (const log of receipt?.logs ?? []) {
    if (log.fragment) {
      console.log(`  ${log.fragment.name} ->`, log.args);
    }
  }

  const bal1 = await token.balanceOf(addr1.address);
  const bal2 = await token.balanceOf(addr2.address);
  console.log("Winner1 balance:", ethers.formatEther(bal1));
  console.log("Winner2 balance:", ethers.formatEther(bal2));
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
