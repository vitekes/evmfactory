import { loadCoreContracts, getModule } from "./utils/system";
import { loadDemoConfig } from "./utils/config";
import { ethers } from 'hardhat';
import { keccak256, toUtf8Bytes } from 'ethers';
import { executeTransaction } from './utils/contracts';

async function main() {
  console.log('=== Демонстрация: Работа с модулем маркетплейса ===');

  // Получаем аккаунты
  const [admin, governor, operator, automation, relayer, seller, buyer] = await ethers.getSigners();
  const config = loadDemoConfig();
  const core = await loadCoreContracts();
  const registry = core.registry;
  const moduleId = keccak256(toUtf8Bytes("Marketplace"));

  // 2. Получаем фабрику маркетплейса
  const module = getModule(moduleId);
  const factoryAddress = module.MarketplaceFactory;
  const factory = await ethers.getContractAt("MarketplaceFactory", factoryAddress);
  // 3. Создание нового листинга на маркетплейсе
  console.log('\n=== Создание нового листинга ===');

  // Параметры листинга
  const productSKU = keccak256(toUtf8Bytes('product-1'));
  const priceUSDC = ethers.parseUnits('100', 6); // 100 USDC
  const usdcToken = config.tokens.usdc;
  const metadata = toUtf8Bytes(JSON.stringify({
    title: 'Премиум доступ',
    description: 'Доступ к премиум функциям на 30 дней',
    imageUrl: 'https://example.com/images/premium.jpg'
  }));

  // Создаем листинг от имени продавца
  const sellerFactory = factory.connect(seller);
  await executeTransaction(sellerFactory, 'createListing', [productSKU, priceUSDC, usdcToken, metadata]);

  console.log(`Листинг создан продавцом ${seller.address} с SKU ${productSKU}`);

  // 4. Получение информации о листинге
  const listingAddress = await factory.getListing(productSKU);
  const listing = await ethers.getContractAt('Listing', listingAddress);

  const listingInfo = await listing.getListingInfo();
  console.log('\n=== Информация о листинге ===');
  console.log(`Адрес листинга: ${listingAddress}`);
  console.log(`Продавец: ${listingInfo.seller}`);
  console.log(`Цена: ${ethers.formatUnits(listingInfo.price, 6)} USDC`);

  // 5. Процесс покупки
  console.log('\n=== Процесс покупки ===');

  // Сначала покупатель должен одобрить расходование USDC
  const usdc = await ethers.getContractAt('MockERC20', usdcToken);
  const buyerUsdc = usdc.connect(buyer);
  await executeTransaction(buyerUsdc, 'approve', [listingAddress, priceUSDC]);

  // Покупка товара
  const buyerListing = listing.connect(buyer);
  await executeTransaction(buyerListing, 'purchase', []);

  console.log(`Покупка успешно совершена покупателем ${buyer.address}`);

  // 6. Проверка состояния после покупки
  const salesCount = await listing.getSalesCount();
  const lastSale = await listing.getSale(salesCount - 1);

  console.log('\n=== Информация о продаже ===');
  console.log(`Всего продаж: ${salesCount}`);
  console.log(`Последний покупатель: ${lastSale.buyer}`);
  console.log(`Время покупки: ${new Date(Number(lastSale.timestamp) * 1000).toLocaleString()}`);

  console.log('\n=== Демонстрация маркетплейса завершена ===');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
