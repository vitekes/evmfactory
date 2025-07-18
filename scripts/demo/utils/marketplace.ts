import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";

export interface Product {
  id: number;
  price: bigint;
  tokenAddress: string;
  /** Discount percent in basis points (10000 = 100%) */
  discount?: number;
}

export interface Listing {
  chainIds: bigint[];
  token: string;
  price: bigint;
  sku: string;
  seller: string;
  salt: number;
  expiry: number;
  discountPercent: number;
}

/**
 * Создание листинга товара в маркетплейсе
 */
export async function createListing(
  marketplace: Contract,
  seller: Signer,
  details: Product
): Promise<{ listing: Listing; signature: string }> {
  console.log("📝 Создание листинга...");
  console.log("🛍️ Товар ID:", details.id);
  console.log("💰 Цена:", ethers.formatEther(details.price), "ETH");
  console.log("🏪 Продавец:", await seller.getAddress());

  const network = await ethers.provider.getNetwork();
  const listing = {
    chainIds: [network.chainId],
    token: details.tokenAddress,
    price: details.price,
    sku: ethers.keccak256(ethers.toUtf8Bytes(details.id.toString())),
    seller: await seller.getAddress(),
    salt: Date.now(),
    expiry: 0,
    discountPercent: details.discount ?? 0,
  } as const;

  const domain = {
    chainId: network.chainId,
    verifyingContract: await marketplace.getAddress(),
  };

  const types = {
    Listing: [
      { name: "chainIds", type: "uint256[]" },
      { name: "token", type: "address" },
      { name: "price", type: "uint256" },
      { name: "sku", type: "bytes32" },
      { name: "seller", type: "address" },
      { name: "salt", type: "uint256" },
      { name: "expiry", type: "uint64" },
      { name: "discountPercent", type: "uint16" },
    ],
  };

  const signature = await seller.signTypedData(domain, types, listing);
  console.log("✅ Листинг создан и подписан");

  return { listing, signature };
}

/**
 * Покупка товара в маркетплейсе
 */
export async function purchaseListing(
  marketplace: Contract,
  buyer: Signer,
  listing: any,
  signature: string,
  paymentToken: string,
  gateway?: Contract
): Promise<any> {
  console.log("🛒 Покупка товара...");
  console.log("👤 Покупатель:", await buyer.getAddress());
  console.log("💳 Токен оплаты:", paymentToken === ethers.ZeroAddress ? "Native ETH" : paymentToken);

  // Если используется ERC20 токен, нужно дать approve
  if (paymentToken !== ethers.ZeroAddress) {
    const token = await ethers.getContractAt("IERC20", paymentToken);
    const amount = await marketplace.getPriceInPreferredCurrency(listing, paymentToken);
    console.log("💰 Сумма к оплате:", ethers.formatEther(amount), "токенов");

    // Approve должен быть выдан PaymentGateway, а не marketplace
    const approveTarget = gateway ? await gateway.getAddress() : await marketplace.getAddress();
    await token.connect(buyer).approve(approveTarget, amount);
    console.log("✅ Approve выдан для ERC20 токена");
  }

  const price = listing.price;
  console.log("💰 Цена листинга:", ethers.formatEther(price), "ETH");

  const tx = await marketplace.connect(buyer).buy(listing, signature, paymentToken, price, {
    value: paymentToken === ethers.ZeroAddress ? price : 0n,
  });

  const receipt = await tx.wait();
  console.log("✅ Покупка завершена! Хеш транзакции:", receipt?.hash);

  return receipt;
}

/**
 * Создание листинга со скидкой
 */
export async function createDiscountedListing(
  marketplace: Contract,
  seller: Signer,
  productId: number,
  originalPrice: bigint,
  discountPercent: number,
  tokenAddress: string = ethers.ZeroAddress
): Promise<{ listing: Listing; signature: string }> {
  console.log("🏷️ Создание листинга со скидкой...");
  console.log("💰 Оригинальная цена:", ethers.formatEther(originalPrice), "ETH");
  console.log("🎯 Скидка:", discountPercent / 100, "%");

  const discountedPrice = originalPrice - (originalPrice * BigInt(discountPercent)) / 10000n;
  console.log("💸 Цена со скидкой:", ethers.formatEther(discountedPrice), "ETH");

  const product: Product = {
    id: productId,
    price: discountedPrice,
    tokenAddress,
    discount: discountPercent
  };

  return await createListing(marketplace, seller, product);
}

/**
 * Создание множественных листингов для тестирования
 */
export async function createMultipleListings(
  marketplace: Contract,
  seller: Signer,
  count: number,
  basePrice: bigint = ethers.parseEther("0.1"),
  tokenAddress: string = ethers.ZeroAddress
): Promise<Array<{ listing: Listing; signature: string; productId: number }>> {
  console.log(`📦 Создание ${count} листингов...`);

  const listings = [];

  for (let i = 1; i <= count; i++) {
    const product: Product = {
      id: i,
      price: basePrice * BigInt(i), // Увеличиваем цену для каждого товара
      tokenAddress,
      discount: i % 3 === 0 ? 1000 : 0 // Каждый третий товар со скидкой 10%
    };

    const { listing, signature } = await createListing(marketplace, seller, product);
    listings.push({ listing, signature, productId: i });

    // Небольшая задержка между созданием листингов
    await new Promise(resolve => setTimeout(resolve, 100));
  }

  console.log(`✅ Создано ${count} листингов`);
  return listings;
}

/**
 * Получение информации о листинге
 */
export async function getListingInfo(listing: Listing): Promise<void> {
  console.log("📋 Информация о листинге:");
  console.log("  🆔 SKU:", listing.sku);
  console.log("  💰 Цена:", ethers.formatEther(listing.price), "ETH");
  console.log("  🪙 Токен:", listing.token === ethers.ZeroAddress ? "Native ETH" : listing.token);
  console.log("  🏪 Продавец:", listing.seller);
  console.log("  🏷️ Скидка:", listing.discountPercent / 100, "%");
  console.log("  ⏰ Срок действия:", listing.expiry === 0 ? "Без ограничений" : new Date(listing.expiry * 1000));
}

/**
 * Расчет финальной цены с учетом скидки
 */
export function calculateFinalPrice(originalPrice: bigint, discountPercent: number): bigint {
  if (discountPercent === 0) return originalPrice;
  return originalPrice - (originalPrice * BigInt(discountPercent)) / 10000n;
}

/**
 * Проверка валидности листинга
 */
export async function validateListing(
  marketplace: Contract,
  listing: Listing,
  signature: string
): Promise<boolean> {
  try {
    // Здесь можно добавить проверки валидности листинга
    // Например, проверить подпись, срок действия, и т.д.
    console.log("🔍 Проверка валидности листинга...");

    // Проверяем, что срок действия не истек
    if (listing.expiry > 0 && listing.expiry < Math.floor(Date.now() / 1000)) {
      console.log("❌ Листинг истек");
      return false;
    }

    // Проверяем, что цена больше 0
    if (listing.price <= 0) {
      console.log("❌ Некорректная цена");
      return false;
    }

    console.log("✅ Листинг валиден");
    return true;
  } catch (error) {
    console.log("❌ Ошибка при проверке листинга:", error);
    return false;
  }
}
