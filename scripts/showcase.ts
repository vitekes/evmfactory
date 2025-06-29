import { ethers, network } from "hardhat";

async function deployCore() {
  const Token = await ethers.getContractFactory("TestToken");
  const token = await Token.deploy("USD Coin", "USDC");

  // Создаем и инициализируем систему контроля доступа
  const ACL = await ethers.getContractFactory("AccessControlCenter");
  const acl = await ACL.deploy();
  const [deployerSigner] = await ethers.getSigners();
  await acl.initialize(deployerSigner.address); // Инициализируем ACL с первым аккаунтом как админом

  // Создаем реестр сервисов
  const Registry = await ethers.getContractFactory("Registry");
  const registry = await Registry.deploy();
  await registry.initialize(await acl.getAddress()); // Инициализируем реестр с ACL

  // Регистрируем ACL в реестре
  await registry.setCoreService(ethers.keccak256(ethers.toUtf8Bytes("AccessControlCenter")), await acl.getAddress());

  // Создаем платежный шлюз
  const Gateway = await ethers.getContractFactory("MockPaymentGateway");
  const gateway = await Gateway.deploy();

  // Создаем ценовой фид
  const PriceFeed = await ethers.getContractFactory("MockPriceFeed");
  const priceFeed = await PriceFeed.deploy();

  // Создаем фабрику контестов
  const Factory = await ethers.getContractFactory("ContestFactory");
  const factory = await Factory.deploy(await registry.getAddress(), await gateway.getAddress());

  return { factory, token, priceFeed, registry, gateway, acl };
}

// Функция allowToken удалена, так как токен добавляется напрямую

function getCreatedContest(rc: any) {
  try {
    // Сначала ищем событие по имени фрагмента
    const ev = rc?.logs.find((l: any) => {
      try {
        return l.fragment && l.fragment.name === "ContestCreated";
      } catch (e) {
        return false;
      }
    });

    if (ev?.args?.[1]) {
      return ev.args[1]; // Возвращаем адрес контеста (индекс 1)
    }

    // Если не нашли через фрагмент, пробуем анализировать topics
    // ContestCreated имеет сигнатуру: ContestCreated(address indexed creator, address contest, uint256 deadline)
    for (const log of rc?.logs || []) {
      if (log.topics && log.topics[0] === ethers.id("ContestCreated(address,address,uint256)")) {
        const iface = new ethers.Interface(["event ContestCreated(address indexed creator, address contest, uint256 deadline)"]);
        const decoded = iface.parseLog({topics: log.topics, data: log.data});
        return decoded?.args?.contest;
      }
    }

    return null;
  } catch (e) {
    console.error("Ошибка при извлечении адреса контеста:", e);
    return null;
  }
}

function getContestDeadline(rc: any) {
  try {
    // Сначала ищем событие по имени фрагмента
    const ev = rc?.logs.find((l: any) => {
      try {
        return l.fragment && l.fragment.name === "ContestCreated";
      } catch (e) {
        return false;
      }
    });

    if (ev?.args?.[2]) {
      return ev.args[2]; // Возвращаем дедлайн (индекс 2)
    }

    // Если не нашли через фрагмент, пробуем анализировать topics
    for (const log of rc?.logs || []) {
      if (log.topics && log.topics[0] === ethers.id("ContestCreated(address,address,uint256)")) {
        const iface = new ethers.Interface(["event ContestCreated(address indexed creator, address contest, uint256 deadline)"]);
        const decoded = iface.parseLog({topics: log.topics, data: log.data});
        return decoded?.args?.deadline;
      }
    }

    return null;
  } catch (e) {
    console.error("Ошибка при извлечении дедлайна контеста:", e);
    return null;
  }
}

async function main() {
  const [deployer, addr1, addr2, addr3] = await ethers.getSigners();
  const { factory, token, priceFeed, registry, gateway } = await deployCore();

  // Регистрация модуля Contest и валидатора
  const CONTEST_ID = ethers.keccak256(ethers.toUtf8Bytes("Contest"));
  await registry.registerFeature(CONTEST_ID, await factory.getAddress(), 0);

  // Создание и регистрация валидатора
  const MultiValidator = await ethers.getContractFactory("MultiValidator");
  const validator = await MultiValidator.deploy();

  // Получение доступа к AccessControlCenter
  const aclAddress = await registry.getCoreService(ethers.keccak256(ethers.toUtf8Bytes("AccessControlCenter")));
  const acl = await ethers.getContractAt("AccessControlCenter", aclAddress);

  // Выдаем права создателю скрипта на управление контрактами
  await acl.grantRole(await acl.GOVERNOR_ROLE(), deployer.address);

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

  console.log("Создание контеста...");
  const tx = await factory.createContest(prizes, metadata);
  console.log("Транзакция отправлена:", tx.hash);
  const rc = await tx.wait();
  console.log("Транзакция подтверждена");

  const contestAddr = getCreatedContest(rc);
  if (!contestAddr) {
    throw new Error("Не удалось получить адрес созданного контеста");
  }
  console.log("Получен адрес контеста:", contestAddr);

  const escrow = (await ethers.getContractAt("ContestEscrow", contestAddr)) as any;
  console.log("Contest escrow:", contestAddr);

  console.log("Финализация контеста...");
  const finalizeTx = await escrow.finalize([addr1.address, addr2.address, addr3.address], 0n, 0n);
  console.log("Транзакция финализации отправлена:", finalizeTx.hash);
  const receipt = await finalizeTx.wait();
  console.log("Транзакция финализации подтверждена");

  console.log("События финализации:")
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
