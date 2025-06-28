import { ethers, network } from "hardhat";

async function deployCore() {
  // Создаем тестовый токен
  const Token = await ethers.getContractFactory("TestToken");
  const token = await Token.deploy("USD Coin", "USDC");

  // Создаем и инициализируем систему контроля доступа
  const ACL = await ethers.getContractFactory("AccessControlCenter");
  const acl = await ACL.deploy();
  const [deployer] = await ethers.getSigners();
  await acl.initialize(deployer.address);

  // Создаем реестр сервисов
  const Registry = await ethers.getContractFactory("Registry");
  const registry = await Registry.deploy();
  await registry.initialize(await acl.getAddress());

  // Регистрируем ACL в реестре
  await registry.setCoreService(ethers.keccak256(ethers.toUtf8Bytes("AccessControlCenter")), acl.address);

  // Создаем платежный шлюз
  const Gateway = await ethers.getContractFactory("MockPaymentGateway");
  const gateway = await Gateway.deploy();

  // Создаем ценовой фид
  const PriceFeed = await ethers.getContractFactory("MockPriceFeed");
  const priceFeed = await PriceFeed.deploy();

  // Создаем фабрику подписок (предполагается, что она уже существует в проекте)
  const SubscriptionFactory = await ethers.getContractFactory("SubscriptionFactory");
  const subscriptionFactory = await SubscriptionFactory.deploy(registry.address, gateway.address);

  return { subscriptionFactory, token, priceFeed, registry, gateway, acl };
}

async function main() {
  const [deployer, seller, buyer] = await ethers.getSigners();
  console.log("Деплой базовых контрактов...");
  const { subscriptionFactory, token, priceFeed, registry, gateway, acl } = await deployCore();

  console.log("Настройка прав доступа...");
  // Выдаем необходимые роли
  const GOVERNOR_ROLE = await acl.GOVERNOR_ROLE();
  await acl.grantRole(GOVERNOR_ROLE, deployer.address);
  await acl.grantRole(GOVERNOR_ROLE, seller.address);

  console.log("Регистрация модуля подписок...");
  // Регистрируем модуль подписок
  const SUBSCRIPTION_ID = ethers.keccak256(ethers.toUtf8Bytes("Subscription"));
  await registry.registerFeature(SUBSCRIPTION_ID, subscriptionFactory.address, 0);

  console.log("Создание и настройка валидатора...");
  // Создание и инициализация валидатора
  const MultiValidator = await ethers.getContractFactory("MultiValidator");
  const validator = await MultiValidator.deploy();
  await validator.initialize(acl.address);

  console.log("Регистрация валидатора в реестре...");
  // Регистрируем валидатор в реестре
  const SERVICE_VALIDATOR = ethers.keccak256(ethers.toUtf8Bytes("Validator"));
  await registry.setModuleServiceAlias(
    SUBSCRIPTION_ID, 
    "Validator", 
    validator.address
  );

  // Добавляем токен в валидатор
  await validator.addToken(token.address);

  console.log("Настройка цен и апрувов...");
  // Получаем адрес токена как строку для корректной работы с getContractAt
  const tokenAddress = await token.getAddress();
  const erc20Interface = new ethers.Interface(["function approve(address spender, uint256 amount) external returns (bool)"]);
  const gatewayAddress = await gateway.getAddress();

  // Вызываем approve напрямую через интерфейс
  const approveData = erc20Interface.encodeFunctionData("approve", [gatewayAddress, ethers.parseEther("1000")]);
  await deployer.sendTransaction({
    to: tokenAddress,
    data: approveData
  });

  await priceFeed.setPrice(tokenAddress, ethers.parseEther("1"));

  console.log("Создание плана подписки...");
  // Параметры плана подписки
  const metadata = ethers.toUtf8Bytes(JSON.stringify({
    features: ["Премиум-контент", "Приоритетная поддержка", "Ранний доступ"]
  }));

  // Создаем план подписки от имени продавца, используя низкоуровневый вызов
  const factoryInterface = new ethers.Interface(["function deploy(bytes calldata data) external returns (address)"]);
  const factoryData = factoryInterface.encodeFunctionData("deploy", [
    ethers.AbiCoder.defaultAbiCoder().encode(
      ['string', 'string', 'address', 'uint256', 'uint256', 'uint256', 'bytes'],
      [
        "Премиум-подписка",
        "Доступ ко всем премиум-функциям",
        tokenAddress,
        ethers.parseEther("10"),
        BigInt(30 * 24 * 60 * 60), // 30 дней в секундах
        BigInt(1000), // максимум подписчиков
        metadata
      ]
    )
  ]);

  const planTx = await seller.sendTransaction({
    to: await subscriptionFactory.getAddress(),
    data: factoryData,
    gasLimit: 1000000
  });

  console.log("Транзакция создания плана отправлена:", planTx.hash);
  const planRc = await planTx.wait();
  console.log("Транзакция подтверждена");

  // Получаем адрес созданного плана подписки из событий
  const planAddress = getPlanAddress(planRc);
  if (!planAddress) {
    throw new Error("Не удалось получить адрес созданного плана подписки");
  }
  console.log(`План подписки создан по адресу: ${planAddress}`);

  // Получаем информацию о плане подписки через низкоуровневые вызовы
  const planInterface = new ethers.Interface([
    "function title() view returns (string)",
    "function price() view returns (uint256)",
    "function duration() view returns (uint256)"
  ]);

  const titleData = planInterface.encodeFunctionData("title", []);
  const titleResult = await ethers.provider.call({ to: planAddress, data: titleData });
  const title = planInterface.decodeFunctionResult("title", titleResult)[0];

  const priceData = planInterface.encodeFunctionData("price", []);
  const priceResult = await ethers.provider.call({ to: planAddress, data: priceData });
  const price = planInterface.decodeFunctionResult("price", priceResult)[0];

  const durationData = planInterface.encodeFunctionData("duration", []);
  const durationResult = await ethers.provider.call({ to: planAddress, data: durationData });
  const duration = planInterface.decodeFunctionResult("duration", durationResult)[0];

  console.log("Детали плана подписки:");
  console.log("  Название:", title);
  console.log("  Цена:", ethers.formatEther(price), "USDC");
  console.log("  Продолжительность:", duration.toString(), "секунд");

  console.log("Подготовка к покупке подписки...");
  // Перевод токенов покупателю
  const transferInterface = new ethers.Interface(["function transfer(address to, uint256 amount) external returns (bool)"]);
  const transferData = transferInterface.encodeFunctionData("transfer", [buyer.address, ethers.parseEther("100")]);
  await deployer.sendTransaction({
    to: tokenAddress,
    data: transferData
  });

  // Покупатель дает разрешение на списание токенов
  const buyerApproveInterface = new ethers.Interface(["function approve(address spender, uint256 amount) external returns (bool)"]);
  const buyerApproveData = buyerApproveInterface.encodeFunctionData("approve", [gatewayAddress, ethers.parseEther("100")]);
  await buyer.sendTransaction({
    to: tokenAddress,
    data: buyerApproveData
  });

  console.log("Покупка подписки...");
  // Используем стандартный метод интерфейса IModule для взаимодействия
  const moduleInterface = new ethers.Interface([
    "function purchase(uint256 quantity, bytes calldata data) external returns (uint256)"
  ]);
  const encodedCall = moduleInterface.encodeFunctionData("purchase", [1, "0x"]);
  const subscribeTx = await buyer.sendTransaction({
    to: planAddress,
    data: encodedCall,
    gasLimit: 500000
  });
  console.log("Транзакция подписки отправлена:", subscribeTx.hash);
  const subscribeRc = await subscribeTx.wait();
  console.log("Транзакция подписки подтверждена");

  console.log("Проверка статуса подписки...");
  // Используем низкоуровневый метод вызова для проверки статуса
  const statusInterface = new ethers.Interface(["function isActive(address user) view returns (bool)"]);
  const data = statusInterface.encodeFunctionData("isActive", [buyer.address]);
  const result = await ethers.provider.call({ to: planAddress, data });
  const isSubscribed = statusInterface.decodeFunctionResult("isActive", result)[0];
  console.log(`Пользователь ${buyer.address} подписан: ${isSubscribed}`);

  // Получаем информацию о подписке через низкоуровневые вызовы
  const timeInterface = new ethers.Interface([
    "function getStartTime(address user) view returns (uint256)",
    "function getEndTime(address user) view returns (uint256)"
  ]);

  const startTimeData = timeInterface.encodeFunctionData("getStartTime", [buyer.address]);
  const startTimeResult = await ethers.provider.call({ to: planAddress, data: startTimeData });
  const startTime = timeInterface.decodeFunctionResult("getStartTime", startTimeResult)[0];

  const endTimeData = timeInterface.encodeFunctionData("getEndTime", [buyer.address]);
  const endTimeResult = await ethers.provider.call({ to: planAddress, data: endTimeData });
  const endTime = timeInterface.decodeFunctionResult("getEndTime", endTimeResult)[0];

  console.log("Детали подписки:");
  console.log("  Дата начала:", startTime.toString());
  console.log("  Дата окончания:", endTime.toString());
  console.log("  Активна:", isSubscribed);

  console.log("Проверка баланса продавца...");
  // Проверяем баланс продавца (должен увеличиться)
  const balanceInterface = new ethers.Interface(["function balanceOf(address account) view returns (uint256)"]);
  const balanceData = balanceInterface.encodeFunctionData("balanceOf", [seller.address]);
  const balanceResult = await ethers.provider.call({ to: tokenAddress, data: balanceData });
  const sellerBalance = balanceInterface.decodeFunctionResult("balanceOf", balanceResult)[0];
  console.log(`Баланс продавца: ${ethers.formatEther(sellerBalance)} USDC`);
}

// Функция для получения адреса созданного плана подписки из событий
function getPlanAddress(rc: any) {
  try {
    // Сначала ищем событие по имени фрагмента
    const ev = rc?.logs.find((l: any) => {
      try {
        return l.fragment && l.fragment.name === "ModuleDeployed";
      } catch (e) {
        return false;
      }
    });

    if (ev?.args?.[1]) {
      return ev.args[1]; // Возвращаем адрес плана (индекс 1)
    }

    // Если не нашли через фрагмент, пробуем анализировать topics
    for (const log of rc?.logs || []) {
      if (log.topics && log.topics[0] === ethers.id("ModuleDeployed(address,address)")) {
        const iface = new ethers.Interface(["event ModuleDeployed(address indexed creator, address module)"]);
        const decoded = iface.parseLog({topics: log.topics, data: log.data});
        return decoded?.args?.module;
      }
    }

    return null;
  } catch (e) {
    console.error("Ошибка при извлечении адреса плана подписки:", e);
    return null;
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
