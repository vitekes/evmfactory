import { ethers, network } from "hardhat";

async function deployCore() {
  console.log("Деплой токена...");
  const Token = await ethers.getContractFactory("TestToken");
  const token = await Token.deploy("USD Coin", "USDC");
  await token.waitForDeployment();
  console.log(`Токен задеплоен по адресу: ${await token.getAddress()}`);

  console.log("Деплой системы контроля доступа...");
  const ACL = await ethers.getContractFactory("AccessControlCenter");
  const acl = await ACL.deploy();
  await acl.waitForDeployment();
  console.log(`ACL задеплоен по адресу: ${await acl.getAddress()}`);
  const [deployer] = await ethers.getSigners();
  console.log(`Инициализация ACL с админом: ${deployer.address}`);
  await acl.initialize(deployer.address);

  console.log("Деплой реестра сервисов...");
  const Registry = await ethers.getContractFactory("Registry");
  const registry = await Registry.deploy();
  await registry.waitForDeployment();
  console.log(`Реестр задеплоен по адресу: ${await registry.getAddress()}`);

  console.log("Инициализация реестра...");
  const aclAddress = await acl.getAddress();
  await registry.initialize(aclAddress);

  console.log("Регистрация ACL в реестре...");
  await registry.setCoreService(ethers.keccak256(ethers.toUtf8Bytes("AccessControlCenter")), aclAddress);

  console.log("Выдача роли FACTORY_ADMIN деплоеру...");
  const FACTORY_ADMIN = ethers.keccak256(ethers.toUtf8Bytes("FACTORY_ADMIN"));
  await acl.grantRole(FACTORY_ADMIN, deployer.address);

  console.log("Деплой платежного шлюза...");
  const Gateway = await ethers.getContractFactory("MockPaymentGateway");
  const gateway = await Gateway.deploy();
  await gateway.waitForDeployment();
  console.log(`Платежный шлюз задеплоен по адресу: ${await gateway.getAddress()}`);

  console.log("Деплой ценового фида...");
  const PriceFeed = await ethers.getContractFactory("MockPriceFeed");
  const priceFeed = await PriceFeed.deploy();
  await priceFeed.waitForDeployment();
  console.log(`Ценовой фид задеплоен по адресу: ${await priceFeed.getAddress()}`);

  console.log("Деплой менеджера комиссий...");
  const FeeManager = await ethers.getContractFactory("CoreFeeManager");
  const feeManager = await FeeManager.deploy();
  await feeManager.waitForDeployment();
  console.log(`Менеджер комиссий задеплоен по адресу: ${await feeManager.getAddress()}`);
  await feeManager.initialize(aclAddress);

  console.log("Настройка платежного шлюза...");
  await gateway.setFeeManager(await feeManager.getAddress());

  console.log("Регистрация сервисов для модуля маркетплейса...");
  const MARKETPLACE_ID = ethers.keccak256(ethers.toUtf8Bytes("Marketplace"));
  const gatewayAddress = await gateway.getAddress();
  // Регистрируем платежный шлюз как сервис для модуля маркетплейса до деплоя фабрики
  await registry.setModuleServiceAlias(
    MARKETPLACE_ID,
    "PaymentGateway",
    gatewayAddress
  );

  console.log("Деплой фабрики маркетплейса...");
  const MarketplaceFactory = await ethers.getContractFactory("MarketplaceFactory");
  const registryAddress = await registry.getAddress();
  const marketplaceFactory = await MarketplaceFactory.deploy(registryAddress, gatewayAddress);
  await marketplaceFactory.waitForDeployment();
  console.log(`Фабрика маркетплейса задеплоена по адресу: ${await marketplaceFactory.getAddress()}`);

  // Регистрируем фабрику в системе
  await registry.registerFeature(MARKETPLACE_ID, await marketplaceFactory.getAddress(), 0);

  console.log("Создание экземпляра маркетплейса...");
  const createMarketplaceTx = await marketplaceFactory.createMarketplace();
  await createMarketplaceTx.wait();

  // Получение адреса созданного маркетплейса из событий
  const receipt = await ethers.provider.getTransactionReceipt(createMarketplaceTx.hash);
  let marketplaceAddress = null;
  if (receipt && receipt.logs) {
    for (const log of receipt.logs) {
      try {
        // Пытаемся декодировать событие MarketplaceCreated
        const iface = new ethers.Interface(["event MarketplaceCreated(address indexed creator, address marketplace)"]);
        const parsedLog = iface.parseLog({ topics: log.topics, data: log.data });
        if (parsedLog && parsedLog.name === "MarketplaceCreated") {
          marketplaceAddress = parsedLog.args.marketplace;
          break;
        }
      } catch (e) {
        // Игнорируем ошибки парсинга логов
      }
    }
  }
  console.log(`Маркетплейс создан по адресу: ${marketplaceAddress}`);

  return { marketplaceFactory, token, priceFeed, registry, gateway, acl };
}

async function main() {
  // Объявляем переменную на уровне функции для доступа во всех блоках
  let marketplaceAddress: string = ""; // Инициализируем пустой строкой

  const [deployer, seller, buyer] = await ethers.getSigners();
  console.log("Деплой базовых контрактов...");
  const { marketplaceFactory, token, priceFeed, registry, gateway, acl } = await deployCore();

  console.log("Настройка прав доступа...");
  // Выдаем необходимые роли
  const GOVERNOR_ROLE = await acl.GOVERNOR_ROLE();
  await acl.grantRole(GOVERNOR_ROLE, deployer.address);
  await acl.grantRole(GOVERNOR_ROLE, seller.address);

  // Выдаем роль FACTORY_ADMIN продавцу и деплоеру
  const FACTORY_ADMIN = ethers.keccak256(ethers.toUtf8Bytes("FACTORY_ADMIN"));
  await acl.grantRole(FACTORY_ADMIN, deployer.address);
  await acl.grantRole(FACTORY_ADMIN, seller.address);

  console.log("Регистрация модуля маркетплейса...");
  // Регистрируем модуль маркетплейса
  const MARKETPLACE_ID = ethers.keccak256(ethers.toUtf8Bytes("Marketplace"));

  console.log("Создание и настройка валидатора...");
  // Создание и инициализация валидатора
  const MultiValidator = await ethers.getContractFactory("MultiValidator");
  const validator = await MultiValidator.deploy();
  await validator.waitForDeployment();
  console.log(`Валидатор задеплоен по адресу: ${await validator.getAddress()}`);
  // Получаем адрес ACL из переменной acl
  await validator.initialize(await acl.getAddress());

  // Получаем адрес токена для добавления в валидатор
  const tokenAddress = await token.getAddress();
  // Добавляем токен в валидатор для проверки
  await validator.addToken(tokenAddress);

  console.log("Регистрация валидатора в реестре...");
  // Регистрируем валидатор в реестре
  const SERVICE_VALIDATOR = ethers.keccak256(ethers.toUtf8Bytes("Validator"));
  await registry.setModuleServiceAlias(
    MARKETPLACE_ID, 
    "Validator", 
    await validator.getAddress()
  );

  // Регистрируем сервис платежного шлюза для маркетплейса
  await registry.setModuleServiceAlias(
    MARKETPLACE_ID,
    "PaymentGateway",
    await gateway.getAddress()
  );

  // Добавляем токен в валидатор
  await validator.addToken(token.address);

  console.log("Настройка цен и апрувов...");
  // Получаем адрес токена как строку для корректной работы с getContractAt
  // Уже объявлено выше: const tokenAddress = await token.getAddress();
  // Передаем метаданные как строку в дополнительном параметре
  const erc20Interface = new ethers.Interface(["function approve(address spender, uint256 amount) external returns (bool)"]);
  const gatewayAddress = await gateway.getAddress();

  // Вызываем approve напрямую через интерфейс
  const approveData = erc20Interface.encodeFunctionData("approve", [gatewayAddress, ethers.parseEther("1000")]);
  await deployer.sendTransaction({
    to: tokenAddress,
    data: approveData
  });

  await priceFeed.setPrice(tokenAddress, ethers.parseEther("1"));

  console.log("Создание маркетплейса...");
  // Создаем маркетплейс с помощью фабрики
  const marketFactory = await ethers.getContractAt("MarketplaceFactory", await marketplaceFactory.getAddress(), seller);
  const createTx = await marketFactory.createMarketplace();
  console.log(`Транзакция создания маркетплейса отправлена: ${createTx.hash}`);
  const createRc = await createTx.wait();
  console.log("Транзакция подтверждена");

  // Получаем адрес созданного маркетплейса из событий
  for (const log of createRc?.logs || []) {
    try {
      if (log.fragment && log.fragment.name === "MarketplaceCreated") {
        marketplaceAddress = log.args.marketplace;
        break;
      }
    } catch (e) {}
  }

  // Если не нашли через фрагмент, пробуем через темы
  if (!marketplaceAddress || marketplaceAddress === "") {
    for (const log of createRc?.logs || []) {
      if (log.topics && log.topics[0] === ethers.id("MarketplaceCreated(address,address)")) {
        const iface = new ethers.Interface(["event MarketplaceCreated(address indexed creator, address marketplace)"]);
        try {
          const decoded = iface.parseLog({topics: log.topics, data: log.data});
          marketplaceAddress = decoded?.args?.marketplace;
          break;
        } catch (e) {
          console.error("Ошибка при декодировании лога:", e);
        }
      }
    }
  }

  if (!marketplaceAddress || marketplaceAddress === "") {
    throw new Error("Не удалось получить адрес созданного маркетплейса");
  }
  console.log(`Маркетплейс создан по адресу: ${marketplaceAddress}`);

  console.log("Создание товара на маркетплейсе...");
  // Метаданные листинга
  const metadata = ethers.toUtf8Bytes(JSON.stringify({
    title: "Premium Ebook Bundle",
    description: "Коллекция из 5 электронных книг по программированию",
    imageUrl: "https://example.com/image.jpg",
    features: ["PDF и EPUB форматы", "Доступ навсегда", "Обновления включены"]
  }));

  // Создаем товар через контракт маркетплейса
  const marketplace = await ethers.getContractAt("Marketplace", marketplaceAddress, seller);
  const listingTx = await marketplace.list(tokenAddress, ethers.parseEther("25"));
  console.log(`Транзакция создания товара отправлена: ${listingTx.hash}`);
  const listingRc = await listingTx.wait();
  console.log("Транзакция подтверждена");

  // Получаем ID созданного листинга из событий
  let listingId = null;
  for (const log of listingRc?.logs || []) {
    try {
      if (log.fragment && log.fragment.name === "MarketplaceListingCreated") {
        listingId = log.args.id;
        break;
      }
    } catch (e) {}
  }

  // Если не нашли через фрагмент, пробуем через темы
  if (listingId === null) {
    for (const log of listingRc?.logs || []) {
      if (log.topics && log.topics[0] === ethers.id("MarketplaceListingCreated(uint256,address,address,uint256)")) {
        try {
          const iface = new ethers.Interface(["event MarketplaceListingCreated(uint256 id, address indexed seller, address token, uint256 price)"]);
          const decoded = iface.parseLog({topics: log.topics, data: log.data});
          listingId = decoded?.args?.id;
          break;
        } catch (e) {
          console.error("Ошибка при декодировании лога:", e);
        }
      }
    }
  }

  if (listingId === null) {
    throw new Error("Не удалось получить ID созданного товара");
  }
  console.log(`Товар создан с ID: ${listingId}`);

  // Получаем информацию о товаре напрямую через контракт
  const listing = await marketplace.listings(listingId);
  console.log("Данные о товаре получены");

  const sellerAddress = listing[0]; // seller
  const tokenAddr = listing[1];     // token
  const itemPrice = listing[2];     // price
  const active = listing[3];        // active

  console.log("Детали товара:");
  console.log("  ID:", listingId.toString());
  console.log("  Продавец:", sellerAddress);
  console.log("  Токен:", tokenAddr);
  console.log("  Цена:", ethers.formatEther(itemPrice), "USDC");
  console.log("  Активен:", active);

  console.log("Подготовка к покупке...");
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

  console.log("Покупка товара...");
  // Покупаем товар напрямую через контракт
  const marketplaceForBuyer = await ethers.getContractAt("Marketplace", marketplaceAddress, buyer);

  const purchaseTx = await marketplaceForBuyer.buy(listingId);
  console.log("Транзакция покупки отправлена:", purchaseTx.hash);
  const purchaseRc = await purchaseTx.wait();
  console.log("Транзакция покупки подтверждена");

  console.log("Проверка покупки...");
  // После покупки проверяем, что товар стал неактивным через контракт
  const marketplaceAfterBuy = await ethers.getContractAt("Marketplace", marketplaceAddress);
  const listingAfter = await marketplaceAfterBuy.listings(listingId);
  const activeAfter = listingAfter[3]; // active

  console.log("Результат покупки:");
  console.log("  Товар активен после покупки:", activeAfter);

  // Ищем событие покупки
  let buyerFromEvent = null;
  for (const log of purchaseRc?.logs || []) {
    try {
      if (log.fragment && log.fragment.name === "MarketplaceListingSold") {
        buyerFromEvent = log.args.buyer;
        console.log("  Покупатель из события:", buyerFromEvent);
        console.log("  ID товара из события:", log.args.id.toString());
        break;
      }
    } catch (e) {}
  }

  // Если не нашли через фрагмент, пробуем через темы
  if (buyerFromEvent === null) {
    for (const log of purchaseRc?.logs || []) {
      if (log.topics && log.topics[0] === ethers.id("MarketplaceListingSold(uint256,address)")) {
        try {
          const iface = new ethers.Interface(["event MarketplaceListingSold(uint256 indexed id, address indexed buyer)"]);
          const decoded = iface.parseLog({topics: log.topics, data: log.data});
          buyerFromEvent = decoded?.args?.buyer;
          console.log("  Покупатель из события:", buyerFromEvent);
          console.log("  ID товара из события:", decoded?.args?.id.toString());
          break;
        } catch (e) {
          console.error("Ошибка при декодировании лога:", e);
        }
      }
    }
  }

  console.log("Проверка балансов...");
  // Проверяем балансы через контракт токена
  const sellerBalance = await token.balanceOf(seller.address);
  const buyerBalance = await token.balanceOf(buyer.address);

  console.log(`Баланс продавца: ${ethers.formatEther(sellerBalance)} USDC`);
  console.log(`Баланс покупателя: ${ethers.formatEther(buyerBalance)} USDC`);

  // Проверяем, что товар больше не активен
  console.log("Финальная проверка товара:");
  const finalListing = await marketplaceAfterBuy.listings(listingId);
  console.log(`  ID: ${listingId}`);
  console.log(`  Активен: ${finalListing[3]}`);

  console.log("Демонстрация маркетплейса успешно завершена!");

  // В простой имплементации маркетплейса нет выполнения заказа
  // После покупки сделка считается завершенной
  console.log("Сделка завершена успешно");
}

// Функция main завершена


main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
