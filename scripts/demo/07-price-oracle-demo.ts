import { ethers } from 'hardhat';
import { executeTransaction } from './utils/contracts';

async function main() {
  console.log('=== Демонстрация: Работа с ценовым оракулом ===');

  // Получаем аккаунты
  const [admin, governor] = await ethers.getSigners();

  // 1. Получаем ранее развернутые контракты
  const priceOracle = await ethers.getContractAt('ChainlinkPriceOracle', '0x...'); // Укажите адрес развернутого ChainlinkPriceOracle

  // 2. Разворачиваем тестовые токены и агрегаторы цен
  console.log('\n=== Создание тестовых токенов и агрегаторов цен ===');

  // Токены
  const TestToken = await ethers.getContractFactory('MockERC20');
  const usdc = await TestToken.deploy('USD Coin', 'USDC', 6);
  const weth = await TestToken.deploy('Wrapped Ether', 'WETH', 18);
  const wbtc = await TestToken.deploy('Wrapped Bitcoin', 'WBTC', 8);

  console.log(`USDC развёрнут по адресу: ${await usdc.getAddress()}`);
  console.log(`WETH развёрнут по адресу: ${await weth.getAddress()}`);
  console.log(`WBTC развёрнут по адресу: ${await wbtc.getAddress()}`);

  // Агрегаторы цен Chainlink
  const MockAggregator = await ethers.getContractFactory('MockV3Aggregator');
  const wethFeed = await MockAggregator.deploy(8, 200000000000); // $2000.00 за ETH
  const wbtcFeed = await MockAggregator.deploy(8, 3000000000000); // $30000.00 за BTC

  console.log(`WETH/USD feed развёрнут по адресу: ${await wethFeed.getAddress()}`);
  console.log(`WBTC/USD feed развёрнут по адресу: ${await wbtcFeed.getAddress()}`);

  // 3. Настройка оракула цен
  console.log('\n=== Настройка ценового оракула ===');

  // Устанавливаем фиды для токенов (базовая валюта - USDC)
  await executeTransaction(priceOracle, 'setPriceFeed', [
    await weth.getAddress(),
    await wethFeed.getAddress(),
    await usdc.getAddress()
  ]);

  await executeTransaction(priceOracle, 'setPriceFeed', [
    await wbtc.getAddress(),
    await wbtcFeed.getAddress(),
    await usdc.getAddress()
  ]);

  console.log(`Установлены ценовые фиды для WETH и WBTC относительно USDC`);

  // 4. Проверка поддержки пар токенов
  console.log('\n=== Проверка поддержки пар токенов ===');

  const isWethUsdcSupported = await priceOracle.isPairSupported(await weth.getAddress(), await usdc.getAddress());
  const isWbtcUsdcSupported = await priceOracle.isPairSupported(await wbtc.getAddress(), await usdc.getAddress());
  const isWethWbtcSupported = await priceOracle.isPairSupported(await weth.getAddress(), await wbtc.getAddress());

  console.log(`WETH/USDC поддерживается: ${isWethUsdcSupported}`);
  console.log(`WBTC/USDC поддерживается: ${isWbtcUsdcSupported}`);
  console.log(`WETH/WBTC поддерживается: ${isWethWbtcSupported}`);

  // 5. Получение цен токенов
  console.log('\n=== Получение цен токенов ===');

  const [wethPrice, wethDecimals] = await priceOracle.getPrice(await weth.getAddress(), await usdc.getAddress());
  const [wbtcPrice, wbtcDecimals] = await priceOracle.getPrice(await wbtc.getAddress(), await usdc.getAddress());

  console.log(`Цена WETH: $${ethers.formatUnits(wethPrice, wethDecimals)}`);
  console.log(`Цена WBTC: $${ethers.formatUnits(wbtcPrice, wbtcDecimals)}`);

  // 6. Конвертация сумм между токенами
  console.log('\n=== Конвертация сумм между токенами ===');

  // Конвертируем 1 WETH в USDC
  const oneWeth = ethers.parseEther('1');
  const wethToUsdc = await priceOracle.convertAmount(await weth.getAddress(), await usdc.getAddress(), oneWeth);

  // Конвертируем 0.1 WBTC в USDC
  const pointOneWbtc = ethers.parseUnits('0.1', 8);
  const wbtcToUsdc = await priceOracle.convertAmount(await wbtc.getAddress(), await usdc.getAddress(), pointOneWbtc);

  // Конвертируем 2000 USDC в WETH
  const twoThousandUsdc = ethers.parseUnits('2000', 6);
  const usdcToWeth = await priceOracle.convertAmount(await usdc.getAddress(), await weth.getAddress(), twoThousandUsdc);

  console.log(`1 WETH = ${ethers.formatUnits(wethToUsdc, 6)} USDC`);
  console.log(`0.1 WBTC = ${ethers.formatUnits(wbtcToUsdc, 6)} USDC`);
  console.log(`2000 USDC = ${ethers.formatEther(usdcToWeth)} WETH`);

  // 7. Обновление цены в агрегаторе
  console.log('\n=== Обновление цены в агрегаторе ===');

  // Обновляем цену ETH до $2200
  await executeTransaction(wethFeed, 'updateAnswer', [220000000000]);

  console.log(`Цена WETH обновлена до $2200`);

  // Проверяем новую цену
  const [newWethPrice, newWethDecimals] = await priceOracle.getPrice(await weth.getAddress(), await usdc.getAddress());
  console.log(`Новая цена WETH: $${ethers.formatUnits(newWethPrice, newWethDecimals)}`);

  // Проверяем конвертацию с новой ценой
  const newWethToUsdc = await priceOracle.convertAmount(await weth.getAddress(), await usdc.getAddress(), oneWeth);
  console.log(`1 WETH = ${ethers.formatUnits(newWethToUsdc, 6)} USDC (после обновления цены)`);

  console.log('\n=== Демонстрация ценового оракула завершена ===');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
