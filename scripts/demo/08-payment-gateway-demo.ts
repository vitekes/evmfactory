import { ethers } from 'hardhat';
import { keccak256, toUtf8Bytes } from 'ethers';
import { executeTransaction } from './utils/contracts';

async function main() {
  console.log('=== Демонстрация: Работа с платежным шлюзом ===');

  // Получаем аккаунты
  const [admin, governor, operator, relayer, payer, recipient] = await ethers.getSigners();

  // 1. Получаем ранее развернутые контракты
  const registry = await ethers.getContractAt('Registry', '0x...'); // Укажите адрес развернутого Registry
  const SERVICE_PAYMENT_GATEWAY = keccak256(toUtf8Bytes('PaymentGateway'));
  const paymentGatewayAddress = await registry.getCoreService(SERVICE_PAYMENT_GATEWAY);
  const paymentGateway = await ethers.getContractAt('PaymentGateway', paymentGatewayAddress);

  const validator = await ethers.getContractAt('MultiValidator', '0x...'); // Укажите адрес развернутого MultiValidator
  const MODULE_ID = keccak256(toUtf8Bytes('Marketplace')); // Используем маркетплейс как пример модуля

  // 2. Создание тестовых токенов
  console.log('\n=== Создание тестовых токенов ===');

  const TestToken = await ethers.getContractFactory('MockERC20');
  const usdc = await TestToken.deploy('USD Coin', 'USDC', 6);

  console.log(`USDC развёрнут по адресу: ${await usdc.getAddress()}`);

  // Добавляем токен в валидатор
  const governorValidator = validator.connect(governor);
  await executeTransaction(governorValidator, 'addToken', [await usdc.getAddress()]);

  // Чеканим токены для плательщика
  await executeTransaction(usdc, 'mint', [payer.address, ethers.parseUnits('10000', 6)]);

  console.log(`Токен USDC добавлен в валидатор и выпущено 10,000 USDC для ${payer.address}`);

  // 3. Прямой платеж через PaymentGateway
  console.log('\n=== Прямой платеж через PaymentGateway ===');

  // Одобряем USDC для использования шлюзом
  const payerUsdc = usdc.connect(payer);
  const paymentAmount = ethers.parseUnits('100', 6); // 100 USDC
  await executeTransaction(payerUsdc, 'approve', [paymentGatewayAddress, paymentAmount]);

  // Выполняем платеж от имени плательщика
  const payerGateway = paymentGateway.connect(payer);
  await executeTransaction(payerGateway, 'processPayment', [
    MODULE_ID,
    await usdc.getAddress(),
    payer.address,
    paymentAmount,
    '0x' // Пустая подпись для прямого платежа
  ]);

  console.log(`Прямой платеж на 100 USDC выполнен от ${payer.address}`);

  // 4. Получение информации о комиссии
  const feeManager = await ethers.getContractAt('CoreFeeManager', await paymentGateway.feeManager());
  const moduleFee = await feeManager.getModuleFee(MODULE_ID);

  console.log('\n=== Информация о комиссиях ===');
  console.log(`Комиссия для модуля ${MODULE_ID}: ${moduleFee} базовых пунктов`);

  // 5. Получение цены в разных валютах
  console.log('\n=== Конвертация валют ===');

  // Получаем цену в USDC для некоторого базового токена
  const baseTokenAddress = await usdc.getAddress(); // В этом примере используем тот же USDC
  const baseAmount = ethers.parseUnits('50', 6); // 50 единиц базовой валюты

  const priceInUsdc = await paymentGateway.getPriceInCurrency(
    MODULE_ID,
    baseTokenAddress,
    await usdc.getAddress(),
    baseAmount
  );

  console.log(`Цена 50 единиц базовой валюты в USDC: ${ethers.formatUnits(priceInUsdc, 6)} USDC`);

  // 6. Платеж с использованием релейера
  console.log('\n=== Платеж через релейера ===');

  // Подготовка подписи для делегированного платежа
  const domainSeparator = await paymentGateway.DOMAIN_SEPARATOR();
  const currentNonce = await paymentGateway.nonces(payer.address, MODULE_ID);

  // В реальном приложении нужно сформировать EIP-712 подпись
  // Для демонстрационных целей мы пропустим этот шаг

  // Релейер выполняет платеж от имени пользователя
  const relayerGateway = paymentGateway.connect(relayer);
  await executeTransaction(relayerGateway, 'processPayment', [
    MODULE_ID,
    await usdc.getAddress(),
    payer.address,
    ethers.parseUnits('50', 6), // 50 USDC
    '0x' // В реальном сценарии здесь была бы подпись
  ]);

  console.log(`Релейер ${relayer.address} выполнил платеж 50 USDC от имени ${payer.address}`);

  // 7. Проверка поддержки пары токенов
  console.log('\n=== Проверка поддержки пары токенов ===');

  const isUsdcSupported = await paymentGateway.isPairSupported(
    MODULE_ID,
    baseTokenAddress,
    await usdc.getAddress()
  );

  console.log(`Пара токенов поддерживается: ${isUsdcSupported}`);

  console.log('\n=== Демонстрация платежного шлюза завершена ===');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
