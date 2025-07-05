import { loadCoreContracts, getModule } from "./utils/system";
import { loadDemoConfig } from "./utils/config";
import { ethers } from 'hardhat';
import { keccak256, toUtf8Bytes } from 'ethers';
import { executeTransaction } from './utils/contracts';

async function main() {
  console.log('=== Демонстрация: Работа с модулем подписок ===');

  const config = loadDemoConfig();
  const core = await loadCoreContracts();
  const registry = core.registry;
  const moduleId = keccak256(toUtf8Bytes("SubscriptionManager"));
  const module = getModule(moduleId);
  const factoryAddress = module.SubscriptionFactory;
  const factory = await ethers.getContractAt("SubscriptionFactory", factoryAddress);

  // 2. Получаем фабрику подписок
  const factoryAddress = await registry.getModuleServiceByAlias(moduleId, 'SubscriptionFactory');
  const factory = await ethers.getContractAt('SubscriptionFactory', factoryAddress);

  // 3. Создание нового плана подписки
  console.log('\n=== Создание нового плана подписки ===');

  // Параметры плана подписки
  const planId = keccak256(toUtf8Bytes('premium-plan'));
  const monthlyPrice = ethers.parseUnits('10', 6); // 10 USDC в месяц
  const usdcToken = config.tokens.usdc;
  const metadata = toUtf8Bytes(JSON.stringify({
    title: 'Премиум подписка',
    description: 'Полный доступ ко всем функциям сервиса',
    benefits: ['Приоритетная поддержка', 'Неограниченный доступ', 'Эксклюзивный контент']
  }));

  // Создаем план подписки от имени провайдера
  const providerFactory = factory.connect(provider);
  await executeTransaction(providerFactory, 'createSubscriptionPlan', [
    planId,
    monthlyPrice,
    usdcToken,
    30 * 24 * 60 * 60, // 30 дней в секундах
    metadata
  ]);

  console.log(`План подписки создан провайдером ${provider.address} с ID ${planId}`);

  // 4. Получение информации о плане подписки
  const planAddress = await factory.getSubscriptionPlan(planId);
  const plan = await ethers.getContractAt('SubscriptionPlan', planAddress);

  const planInfo = await plan.getPlanInfo();
  console.log('\n=== Информация о плане подписки ===');
  console.log(`Адрес плана: ${planAddress}`);
  console.log(`Провайдер: ${planInfo.provider}`);
  console.log(`Цена: ${ethers.formatUnits(planInfo.price, 6)} USDC в месяц`);
  console.log(`Период: ${planInfo.period / (24 * 60 * 60)} дней`);

  // 5. Процесс подписки
  console.log('\n=== Процесс подписки ===');

  // Сначала подписчик должен одобрить расходование USDC
  const usdc = await ethers.getContractAt('MockERC20', usdcToken);
  const subscriberUsdc = usdc.connect(subscriber);
  await executeTransaction(subscriberUsdc, 'approve', [planAddress, monthlyPrice]);

  // Оформление подписки
  const subscriberPlan = plan.connect(subscriber);
  await executeTransaction(subscriberPlan, 'subscribe', []);

  console.log(`Подписка успешно оформлена пользователем ${subscriber.address}`);

  // 6. Проверка статуса подписки
  const isActive = await plan.isSubscriptionActive(subscriber.address);
  const subscriptionDetails = await plan.getSubscriptionDetails(subscriber.address);

  console.log('\n=== Информация о подписке ===');
  console.log(`Статус подписки: ${isActive ? 'Активна' : 'Неактивна'}`);
  console.log(`Дата начала: ${new Date(Number(subscriptionDetails.startTime) * 1000).toLocaleString()}`);
  console.log(`Дата окончания: ${new Date(Number(subscriptionDetails.endTime) * 1000).toLocaleString()}`);

  // 7. Продление подписки (демонстрация автоматического продления)
  console.log('\n=== Автоматическое продление подписки ===');

  // Имитация вызова от автоматизированного аккаунта
  const automationPlan = plan.connect(automation);
  await executeTransaction(automationPlan, 'processRenewal', [subscriber.address]);

  const newDetails = await plan.getSubscriptionDetails(subscriber.address);
  console.log(`Подписка продлена до: ${new Date(Number(newDetails.endTime) * 1000).toLocaleString()}`);

  console.log('\n=== Демонстрация подписок завершена ===');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
