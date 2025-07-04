import { ethers } from 'ethers';
import * as dotenv from 'dotenv';

// Загружаем ABI EventRouter
const eventRouterAbi = [
  'event EventRouted(uint8 indexed kind, bytes payload)',
  'enum EventKind { Unknown, ListingCreated, SubscriptionCharged, ContestFinalized, PaymentProcessed, TokenConverted, SubscriptionCreated, MarketplaceSale, UserRegistered }'
];

// Определения типов для декодирования событий
type EventKind = {
  Unknown: 0,
  ListingCreated: 1,
  SubscriptionCharged: 2,
  ContestFinalized: 3,
  PaymentProcessed: 4,
  TokenConverted: 5,
  SubscriptionCreated: 6,
  MarketplaceSale: 7,
  UserRegistered: 8
};

async function main() {
  dotenv.config();

  // Настройка подключения к сети
  const provider = new ethers.providers.JsonRpcProvider(process.env.RPC_URL);
  const eventRouterAddress = process.env.EVENT_ROUTER_ADDRESS;

  if (!eventRouterAddress) {
    throw new Error('EVENT_ROUTER_ADDRESS не указан в .env');
  }

  console.log(`Подключение к EventRouter по адресу: ${eventRouterAddress}`);

  // Создаем экземпляр контракта
  const eventRouter = new ethers.Contract(eventRouterAddress, eventRouterAbi, provider);

  // Прослушивание всех событий
  eventRouter.on('EventRouted', (kind, payload, event) => {
    console.log(`Получено событие типа: ${kind}`);

    // Декодирование в зависимости от типа события
    try {
      switch (Number(kind)) {
        case 1: // ListingCreated
          const listingData = decodeListingCreated(payload);
          console.log('Листинг создан:', listingData);
          break;

        case 2: // SubscriptionCharged
          const subscriptionData = decodeSubscriptionCharged(payload);
          console.log('Подписка списана:', subscriptionData);
          break;

        case 3: // ContestFinalized
          const contestData = decodeContestFinalized(payload);
          console.log('Конкурс финализирован:', contestData);
          break;

        case 4: // PaymentProcessed
          const paymentData = decodePaymentProcessed(payload);
          console.log('Платеж обработан:', paymentData);
          break;

        case 5: // TokenConverted
          const conversionData = decodeTokenConverted(payload);
          console.log('Токен конвертирован:', conversionData);
          break;

        case 6: // SubscriptionCreated
          const newSubscriptionData = decodeSubscriptionCreated(payload);
          console.log('Подписка создана:', newSubscriptionData);
          break;

        case 7: // MarketplaceSale
          const saleData = decodeMarketplaceSale(payload);
          console.log('Продажа в маркетплейсе:', saleData);
          break;

        case 8: // UserRegistered
          const userData = decodeUserRegistered(payload);
          console.log('Пользователь зарегистрирован:', userData);
          break;

        default:
          console.log('Неизвестный тип события');
      }
    } catch (error) {
      console.error('Ошибка при декодировании события:', error);
      console.log('Необработанные данные:', payload);
    }
  });

  // Прослушивание конкретного типа события (например, только MarketplaceSale)
  eventRouter.on(eventRouter.filters.EventRouted(7), (kind, payload, event) => {
    console.log('Новая продажа в маркетплейсе!');
    const saleData = decodeMarketplaceSale(payload);
    // Здесь можно вызвать специфическую бизнес-логику для обработки продаж
    notifySeller(saleData.seller, saleData.price);
    updateInventory(saleData.tokenContract, saleData.tokenId);
  });

  console.log('Слушатель событий запущен. Нажмите Ctrl+C для завершения.');
}

// Функции для декодирования разных типов событий
function decodeListingCreated(payload: string) {
  const [listingId, seller, tokenContract, tokenId, price, currency, expiresAt, metadata] = 
    ethers.utils.defaultAbiCoder.decode(
      ['uint256', 'address', 'address', 'uint256', 'uint256', 'address', 'uint256', 'bytes'],
      payload
    );
  return { listingId, seller, tokenContract, tokenId, price, currency, expiresAt, metadata };
}

function decodeSubscriptionCharged(payload: string) {
  const [subscriber, merchant, planHash, token, amount, nextBillingTime] = 
    ethers.utils.defaultAbiCoder.decode(
      ['address', 'address', 'bytes32', 'address', 'uint256', 'uint256'],
      payload
    );
  return { subscriber, merchant, planHash, token, amount, nextBillingTime };
}

function decodeContestFinalized(payload: string) {
  const [creator, winners, prizes] = 
    ethers.utils.defaultAbiCoder.decode(
      ['address', 'address[]', 'tuple(uint8,address,uint256,string,uint8)[]'],
      payload
    );
  return { creator, winners, prizes };
}

function decodePaymentProcessed(payload: string) {
  const [moduleId, payer, token, amount, netAmount, commissionAmount, referenceCode] = 
    ethers.utils.defaultAbiCoder.decode(
      ['bytes32', 'address', 'address', 'uint256', 'uint256', 'uint256', 'string'],
      payload
    );
  return { moduleId, payer, token, amount, netAmount, commissionAmount, referenceCode };
}

function decodeTokenConverted(payload: string) {
  const [moduleId, fromToken, toToken, amount, result] = 
    ethers.utils.defaultAbiCoder.decode(
      ['bytes32', 'address', 'address', 'uint256', 'uint256'],
      payload
    );
  return { moduleId, fromToken, toToken, amount, result };
}

function decodeSubscriptionCreated(payload: string) {
  const [subscriber, merchant, planHash, paymentToken, paymentAmount, period, nextBillingTime] = 
    ethers.utils.defaultAbiCoder.decode(
      ['address', 'address', 'bytes32', 'address', 'uint256', 'uint256', 'uint256'],
      payload
    );
  return { subscriber, merchant, planHash, paymentToken, paymentAmount, period, nextBillingTime };
}

function decodeMarketplaceSale(payload: string) {
  const [listingId, seller, buyer, tokenContract, tokenId, price, currency, timestamp] = 
    ethers.utils.defaultAbiCoder.decode(
      ['uint256', 'address', 'address', 'address', 'uint256', 'uint256', 'address', 'uint256'],
      payload
    );
  return { listingId, seller, buyer, tokenContract, tokenId, price, currency, timestamp };
}

function decodeUserRegistered(payload: string) {
  const [user, timestamp, metadata] = 
    ethers.utils.defaultAbiCoder.decode(
      ['address', 'uint256', 'bytes'],
      payload
    );
  return { user, timestamp, metadata };
}

// Пример функций, которые могли бы вызываться в ответ на события
function notifySeller(seller: string, price: ethers.BigNumber) {
  console.log(`Оповещение продавца ${seller} о продаже на сумму ${ethers.utils.formatEther(price)} ETH`);
  // Здесь могла бы быть логика отправки уведомления через внешний API
}

function updateInventory(tokenContract: string, tokenId: ethers.BigNumber) {
  console.log(`Обновление инвентаря для токена ${tokenContract}:${tokenId}`);
  // Здесь могла бы быть логика обновления инвентаря в базе данных
}

// Запускаем основную функцию
main().catch((error) => {
  console.error(error);
  process.exit(1);
});
