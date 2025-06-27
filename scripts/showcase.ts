import { ethers, network } from "hardhat";

async function deployCore() {
  const Token = await ethers.getContractFactory("TestToken");
  const token = await Token.deploy("USD Coin", "USDC");

  const ACL = await ethers.getContractFactory("MockAccessControlCenterAuto");
  const acl = await ACL.deploy();

  const Registry = await ethers.getContractFactory("MockRegistry");
  const registry = await Registry.deploy();
  await registry.setCoreService(ethers.keccak256(Buffer.from("AccessControlCenter")), await acl.getAddress());

  const Gateway = await ethers.getContractFactory("MockPaymentGateway");
  const gateway = await Gateway.deploy();

  const PriceFeed = await ethers.getContractFactory("MockPriceFeed");
  const priceFeed = await PriceFeed.deploy();

  const Factory = await ethers.getContractFactory("ContestFactory");
  const factory = await Factory.deploy(await registry.getAddress(), await gateway.getAddress());

  return { factory, token, priceFeed, registry, gateway };
}

// Функция allowToken удалена, так как токен добавляется напрямую

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

  // Регистрация модуля Contest и валидатора
  const CONTEST_ID = ethers.keccak256(ethers.toUtf8Bytes("Contest"));
  await registry.registerFeature(CONTEST_ID, await factory.getAddress(), 0);

  // Создание и регистрация валидатора
  const MultiValidator = await ethers.getContractFactory("MultiValidator");
  const validator = await MultiValidator.deploy();

  // Получение доступа к AccessControlCenter
  const aclAddress = await registry.getCoreService(ethers.keccak256(ethers.toUtf8Bytes("AccessControlCenter")));

  // Инициализируем валидатор
  await validator.initialize(aclAddress);

  // Установка валидатора в реестр
  await registry.setModuleServiceAlias(
    CONTEST_ID, 
    "Validator", 
    await validator.getAddress()
  );

  // Добавляем токен напрямую в валидатор
  await validator.addToken(await token.getAddress());

  await token.approve(await gateway.getAddress(), ethers.parseEther("1000"));
  await priceFeed.setPrice(await token.getAddress(), ethers.parseEther("1"));

  const metadata = "0x";
  const prizes = [
    { prizeType: 0, token: await token.getAddress(), amount: ethers.parseEther("10"), distribution: 0, uri: "" },
    { prizeType: 0, token: await token.getAddress(), amount: ethers.parseEther("5"), distribution: 0, uri: "" },
    { prizeType: 1, token: ethers.ZeroAddress, amount: 0, distribution: 0, uri: "ipfs://promo" }
  ];

  const tx = await factory.createContest(prizes, metadata);
  const rc = await tx.wait();
  const contestAddr = getCreatedContest(rc);
  const escrow = (await ethers.getContractAt("ContestEscrow", contestAddr)) as any;
  console.log("Contest escrow:", contestAddr);

  const finalizeTx = await escrow.finalize([addr1.address, addr2.address, addr3.address], 0n, 0n);
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
