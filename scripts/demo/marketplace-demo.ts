import {ethers} from "hardhat";
import {deployCore, registerModule} from "./utils/deployer";
import {safeExecute} from "./utils/helpers";
import {CONSTANTS} from "./utils/constants";
import {ensureRoles} from "./utils/roles";
import {createMarketplace} from "./utils/marketplace";
import {createListing, purchaseListing} from "./utils/listing";

/**
 * Главная функция демонстрации маркетплейса
 */
async function main() {
    // Получаем аккаунты для тестирования
    const [deployer, seller, buyer] = await ethers.getSigners();
    console.log("Демонстрация функциональности маркетплейса");
    console.log("=========================================\n");
    console.log(`Деплоер: ${deployer.address}`);
    console.log(`Продавец: ${seller.address}`);
    console.log(`Покупатель: ${buyer.address}\n`);

    // 1. Деплой базовых контрактов
    console.log("1. Разворачиваем базовые контракты системы");
    console.log("----------------------------------------\n");
    const {token, registry, gateway, validator, acl} = await deployCore();

    // Отправляем токены продавцу и покупателю
    await safeExecute("отправка токенов участникам", async () => {
        // Увеличиваем количество токенов для покупателя, чтобы гарантировать достаточный баланс
        await token.transfer(seller.address, ethers.parseEther("50"));
        await token.transfer(buyer.address, ethers.parseEther("200"));
        console.log(`Отправлено 50 токенов продавцу ${seller.address}`);
        console.log(`Отправлено 200 токенов покупателю ${buyer.address}`);

        // Проверяем баланс покупателя после перевода
        const buyerBalance = await token.balanceOf(buyer.address);
        console.log(`Баланс покупателя после перевода: ${ethers.formatEther(buyerBalance)} токенов`);
    });

    // 2. Деплой фабрики маркетплейса
    console.log("\n2. Разворачиваем фабрику маркетплейса");
    console.log("--------------------------------------\n");
    const marketplaceFactory = await safeExecute("деплой фабрики маркетплейса", async () => {
        const Factory = await ethers.getContractFactory("MarketplaceFactory");
        const factory = await Factory.deploy(
            await registry.getAddress(),
            await gateway.getAddress()
        );
        await factory.waitForDeployment();
        console.log(`Фабрика маркетплейса развернута: ${await factory.getAddress()}`);
        return factory;
    });

    // 3. Регистрация модуля маркетплейса в реестре
    console.log("\n3. Регистрируем модуль маркетплейса в реестре");
    console.log("-------------------------------------------\n");
    try {
        console.log(`ID модуля маркетплейса: ${CONSTANTS.MARKETPLACE_ID}`);
        await registerModule(
            registry,
            CONSTANTS.MARKETPLACE_ID,
            await marketplaceFactory.getAddress(),
            await validator.getAddress(),
            await gateway.getAddress()
        );
    } catch (error) {
        console.error("Критическая ошибка при регистрации модуля маркетплейса:", error);
        throw error;
    }

    // 4. Создание маркетплейса
    console.log("\n4. Создаем новый маркетплейс");
    console.log("----------------------------\n");

    // Явно выдаем роль FACTORY_ADMIN перед созданием маркетплейса
    await safeExecute("выдача роли FACTORY_ADMIN", async () => {
        const [deployer] = await ethers.getSigners();
        console.log(`Подготовка: выдаем роль FACTORY_ADMIN аккаунту ${deployer.address}`);

        // Получаем контракт ACL
        const aclAddress = await registry.getCoreService(ethers.keccak256(ethers.toUtf8Bytes("AccessControlCenter")));
        const acl = await ethers.getContractAt("AccessControlCenter", aclAddress);

        // Используем константу для идентификатора роли
        const factoryAdminRole = CONSTANTS.FACTORY_ADMIN;

        // Проверяем наличие роли
        const hasRole = await acl.hasRole(factoryAdminRole, deployer.address);
        console.log(`Аккаунт ${deployer.address} ${hasRole ? 'уже имеет' : 'не имеет'} роль FACTORY_ADMIN`);

        if (!hasRole) {
            const tx = await acl.grantRole(factoryAdminRole, deployer.address);
            await tx.wait();
            console.log(`Роль FACTORY_ADMIN выдана аккаунту ${deployer.address}`);

            // Проверяем, что роль действительно выдана
            const roleGranted = await acl.hasRole(factoryAdminRole, deployer.address);
            console.log(`Проверка: роль FACTORY_ADMIN ${roleGranted ? 'успешно выдана' : 'НЕ ВЫДАНА!'}`);
        }
    });

    // Создаем маркетплейс используя оптимизированную функцию, которая автоматически выбирает
    // метод создания (через фабрику или напрямую)
    const marketplaceAddress = await safeExecute("создание маркетплейса", async () => {
        return await createMarketplace(marketplaceFactory, registry, validator, gateway);
    });

    // 5. Получаем контракт маркетплейса
    const marketplace = await ethers.getContractAt("Marketplace", marketplaceAddress) as any;
    console.log(`\nМаркетплейс готов к использованию: ${marketplaceAddress}`);

    // Анализируем API маркетплейса для понимания доступных методов
    console.log("Анализ API маркетплейса:");
    try {
        // Получаем все методы маркетплейса
        const marketplaceMethods = [];
        for (const key in marketplace) {
            if (typeof marketplace[key] === 'function' && !key.startsWith('_')) {
                marketplaceMethods.push(key);
            }
        }
        console.log("Доступные методы маркетплейса:", marketplaceMethods);

        // Проверяем наличие методов для работы с листингами
        const hasCreateListing = marketplaceMethods.includes('createListing');
        const hasList = marketplaceMethods.includes('list');
        const hasGetListing = marketplaceMethods.includes('getListing');
        const hasListings = marketplaceMethods.includes('listings');

        console.log(`Методы листинга - createListing: ${hasCreateListing}, list: ${hasList}, getListing: ${hasGetListing}, listings: ${hasListings}`);
    } catch (e) {
        console.log("Ошибка при анализе API маркетплейса:", e instanceof Error ? e.message : "Неизвестная ошибка");
    }

    // 6. Создание листинга
    console.log("\n5. Создаем листинг товара");
    console.log("-------------------------\n");
    const price = ethers.parseEther("10");
    const uri = "https://example.com/item/1";

    // Перед созданием листинга проверяем, что все параметры в порядке
    console.log(`Адрес токена: ${await token.getAddress()}`);
    console.log(`Адрес продавца: ${seller.address}`);
    console.log(`Цена: ${ethers.formatEther(price)} токенов`);

    const listingId = await safeExecute("создание листинга", async () => {
        // Передаем токен как объект, а не как строковый адрес
        return await createListing(marketplace, token, seller, price, uri);
    });

    // 7. Покупка товара
    console.log("\n7. Покупаем товар");
    console.log("-----------------\n");

    // Проверяем структуру маркетплейса и токена перед покупкой
    console.log("Подготовка к покупке товара...");

    // Проверка адресов
    // Используем уже объявленную переменную marketplaceAddress
    console.log(`Адрес маркетплейса: ${marketplaceAddress}`);
    const tokenAddress = await token.getAddress();
    console.log(`Адрес токена: ${tokenAddress}`);

    // Проверка листинга
    try {
        console.log(`Получаем информацию о листинге ${listingId}...`);
        const listing = await marketplace.getListing(listingId);
        console.log("Информация о листинге:", listing);
    } catch (listingError) {
        console.log(`Не удалось получить информацию о листинге: ${listingError instanceof Error ? listingError.message : 'Неизвестная ошибка'}`);
    }

    // Проверка балансов
    const buyerBalance = await token.balanceOf(buyer.address);
    const sellerBalance = await token.balanceOf(seller.address);
    console.log(`Баланс покупателя перед покупкой: ${ethers.formatEther(buyerBalance)} токенов`);
    console.log(`Баланс продавца перед покупкой: ${ethers.formatEther(sellerBalance)} токенов`);

    // Проверка и установка максимального одобрения токенов напрямую
    try {
        console.log("Устанавливаем максимальное одобрение токенов для маркетплейса...");
        const maxApproval = ethers.MaxUint256; // Максимально возможное значение uint256
        const approveTx = await (token as any).connect(buyer).approve(marketplaceAddress, maxApproval);
        await approveTx.wait();

        const newAllowance = await token.allowance(buyer.address, marketplaceAddress);
        console.log(`Новое одобрение: ${newAllowance} токенов`);
    } catch (approveError) {
        console.log(`Ошибка при установке одобрения: ${approveError instanceof Error ? approveError.message : 'Неизвестная ошибка'}`);
    }

    // Выполняем покупку с обработкой ошибок
    try {
        await safeExecute("покупка товара", async () => {
            // Выполняем покупку через общую функцию
            await purchaseListing(marketplace, token, buyer, listingId, price);
        });
    } catch (purchaseError) {
        console.error("Не удалось выполнить покупку товара, но продолжаем демонстрацию");
    }

    // 8. Проверка балансов
    console.log("\n8. Проверяем итоговые балансы");
    console.log("-----------------------------\n");
    try {
        const finalSellerBalance = await token.balanceOf(seller.address);
        const finalBuyerBalance = await token.balanceOf(buyer.address);

        console.log(`Баланс продавца: ${ethers.formatEther(finalSellerBalance)} токенов`);
        console.log(`Баланс покупателя: ${ethers.formatEther(finalBuyerBalance)} токенов`);
    } catch (balanceError) {
        console.error("Ошибка при проверке итоговых балансов:", 
            balanceError instanceof Error ? balanceError.message : "Неизвестная ошибка");
    }

    console.log("\n✅ Демонстрация маркетплейса успешно завершена!");
}

// Запуск демонстрации
main().catch((error) => {
    console.error("Ошибка при выполнении демонстрации:", error);
    process.exitCode = 1;
});