import { ethers } from "hardhat";

/**
 * Создает листинг на маркетплейсе
 * @param marketplace Контракт маркетплейса
 * @param token Контракт токена для оплаты или адрес токена
 * @param seller Адрес продавца
 * @param price Цена товара
 * @param uri URI метаданных товара
 */
export async function createListing(marketplace: any, token: any, seller: any, price: bigint, uri: string) {
    console.log(`Создание листинга от продавца ${seller.address} с ценой ${ethers.formatEther(price)} токенов...`);

    try {
        // Получаем адрес токена (может быть как строкой, так и объектом)
        let tokenAddress: string;
        if (typeof token === 'string') {
            tokenAddress = token;
        } else {
            tokenAddress = await token.getAddress();
        }
        console.log(`Используем адрес токена: ${tokenAddress}`);

        // Анализируем доступные методы для создания листинга
        const availableMethods = [];
        const createListingSignatures = [];
        const listSignatures = [];

        // Проверяем интерфейс на наличие методов
        try {
            if (marketplace.interface && marketplace.interface.fragments) {
                for (const key in marketplace.interface.fragments) {
                    const fragment = marketplace.interface.fragments[key];
                    if (fragment.name === 'createListing') {
                        createListingSignatures.push(fragment.format());
                    } else if (fragment.name === 'list') {
                        listSignatures.push(fragment.format());
                    }
                }
            }
        } catch (e) {
            console.log("Не удалось получить методы из интерфейса");
        }

        // Проверяем доступные методы напрямую
        try {
            for (const key in marketplace) {
                if (typeof marketplace[key] === 'function' && !key.startsWith('_')) {
                    availableMethods.push(key);
                }
            }
        } catch (e) {
            console.log("Не удалось получить методы напрямую");
        }

        console.log("Доступные методы:", availableMethods);
        console.log("Сигнатуры createListing:", createListingSignatures);
        console.log("Сигнатуры list:", listSignatures);

        // Определяем какой метод использовать
        const hasCreateListing = availableMethods.includes('createListing') || createListingSignatures.length > 0;
        const hasList = availableMethods.includes('list') || listSignatures.length > 0;

        // Проверяем метод создания листинга
        let tx;
        if (hasCreateListing) {
            console.log(`Вызываем метод createListing с токеном ${tokenAddress}, ценой ${ethers.formatEther(price)} и URI ${uri}`);
            try {
                // Пробуем разные сигнатуры метода createListing
                if (createListingSignatures.includes('createListing(address,uint256,uint256,string)')) {
                    tx = await marketplace.connect(seller).createListing(
                        tokenAddress,
                        price,
                        0, // kind
                        uri
                    );
                } else {
                    // Пробуем вызвать метод без параметра kind
                    tx = await marketplace.connect(seller).createListing(
                        tokenAddress,
                        price,
                        uri
                    );
                }
            } catch (e) {
                console.log(`Ошибка при вызове createListing: ${e instanceof Error ? e.message : 'Неизвестная ошибка'}`);
                throw e;
            }
        } else if (hasList) {
            // Используем альтернативный метод list, если createListing отсутствует
            console.log(`Вызываем метод list с токеном ${tokenAddress} и ценой ${ethers.formatEther(price)}`);
            try {
                tx = await marketplace.connect(seller).list(
                    tokenAddress,
                    price
                );
            } catch (e) {
                console.log(`Ошибка при вызове list: ${e instanceof Error ? e.message : 'Неизвестная ошибка'}`);
                throw e;
            }
        } else {
            throw new Error("Методы createListing и list не найдены в контракте маркетплейса");
        }

        console.log("Транзакция отправлена:", tx.hash);
        const receipt = await tx.wait();

        // Получаем ID листинга из событий
        let listingId = 0n;
        if (receipt && receipt.logs) {
            for (const log of receipt.logs) {
                if (log.fragment && log.fragment.name === "ListingCreated") {
                    listingId = log.args[0];
                    break;
                }
            }
        } else {
            console.log("Не удалось получить ID листинга из событий, используем значение по умолчанию");
        }

        console.log(`Листинг успешно создан с ID: ${listingId}`);
        return listingId;
    } catch (error) {
        console.error("Ошибка при создании листинга:",
            error instanceof Error ? error.message : "Неизвестная ошибка");
        throw error;
    }
}

/**
 * Покупка товара на маркетплейсе
 * @param marketplace Контракт маркетплейса
 * @param token Контракт токена
 * @param buyer Покупатель
 * @param listingId ID листинга
 * @param price Цена товара
 */
export async function purchaseListing(marketplace: any, token: any, buyer: any, listingId: bigint, price: bigint) {
    console.log(`Покупка листинга ${listingId} покупателем ${buyer.address}...`);

    try {
        // Получаем адрес маркетплейса
        const marketplaceAddress = await marketplace.getAddress();
        console.log(`Адрес маркетплейса: ${marketplaceAddress}`);

        // Получаем баланс покупателя
        const buyerBalance = await token.balanceOf(buyer.address);
        console.log(`Баланс покупателя: ${ethers.formatEther(buyerBalance)} токенов`);

        if (buyerBalance < price) {
            throw new Error(`Недостаточно токенов для покупки. Требуется ${ethers.formatEther(price)}, доступно ${ethers.formatEther(buyerBalance)}`);
        }

        // Проверяем структуру листинга
        try {
            const listing = await marketplace.getListing(listingId);
            console.log(`Листинг ${listingId}:`, listing);
        } catch (e) {
            console.log(`Невозможно получить информацию о листинге: ${e instanceof Error ? e.message : 'Неизвестная ошибка'}`);
        }

        // Сбрасываем все существующие одобрения
        console.log(`Сбрасываем все одобрения для токена`);
        await token.connect(buyer).approve(marketplaceAddress, 0);

        // Проверяем интерфейс токена
        const tokenName = await token.name();
        const tokenSymbol = await token.symbol();
        console.log(`Токен: ${tokenName} (${tokenSymbol})`);

        // Делаем новое одобрение с очень большим запасом
        // Увеличиваем одобрение в 10 раз от требуемой цены
        const approvalAmount = price * 10n;
        console.log(`Устанавливаем одобрение: ${ethers.formatEther(approvalAmount)} токенов для ${marketplaceAddress}`);

        // Отправляем транзакцию одобрения и ждем её подтверждения
        const approveTx = await token.connect(buyer).approve(marketplaceAddress, approvalAmount);
        console.log(`Транзакция одобрения отправлена: ${approveTx.hash}`);
        await approveTx.wait();

        // Проверяем, что одобрение действительно установлено
        const newAllowance = await token.allowance(buyer.address, marketplaceAddress);
        console.log(`Новое одобрение: ${ethers.formatEther(newAllowance)} токенов`);

        if (newAllowance < price) {
            throw new Error(`Не удалось установить правильное одобрение. Текущее: ${ethers.formatEther(newAllowance)}, требуется: ${ethers.formatEther(price)}`);
        }

        // Добавляем более длительную задержку перед покупкой (3 секунды)
        console.log("Ожидаем обновления состояния блокчейна (3 секунды)...");
        await new Promise(resolve => setTimeout(resolve, 3000));

        // Объявляем переменную tx до ее использования
        let tx;

        // Выводим информацию о маркетплейсе
        console.log(`Адрес маркетплейса: ${await marketplace.getAddress()}`);
        console.log(`Адрес покупателя: ${buyer.address}`);

        // Анализируем доступные методы маркетплейса
        const availableMethods = [];
        const availableBuySignatures = [];
        const availablePurchaseSignatures = [];

        // Пробуем получить информацию о методах маркетплейса
        try {
            if (marketplace.interface) {
                // Проверяем наличие фрагментов
                for (const key in marketplace.interface.fragments) {
                    const fragment = marketplace.interface.fragments[key];
                    if (fragment.name === 'buy') {
                        availableBuySignatures.push(fragment.format());
                    } else if (fragment.name === 'purchase') {
                        availablePurchaseSignatures.push(fragment.format());
                    }
                }
            }
        } catch (e) {
            console.log("Не удалось получить методы из интерфейса");
        }

        // Собираем все доступные методы
        try {
            for (const key in marketplace) {
                if (typeof marketplace[key] === 'function' && !key.startsWith('_')) {
                    availableMethods.push(key);
                }
            }
        } catch (e) {
            console.log("Не удалось получить методы напрямую");
        }

        console.log("Доступные методы маркетплейса:", availableMethods);
        console.log("Сигнатуры buy:", availableBuySignatures);
        console.log("Сигнатуры purchase:", availablePurchaseSignatures);

        // Выполняем покупку с помощью различных стратегий

        // Стратегия 1: Используем функцию покупки в зависимости от доступных методов
        try {
            // Попытка 1: Проверяем, доступен ли метод purchase
            if (availableMethods.includes('purchase') || availablePurchaseSignatures.length > 0) {
                console.log("Используем метод purchase...");
                let purchaseTx = await marketplace.connect(buyer).purchase(listingId, {
                    gasLimit: 1000000
                });
                console.log("Транзакция отправлена:", purchaseTx.hash);
                await purchaseTx.wait();
            }
            // Попытка 2: Проверяем, доступен ли метод buy
            else if (availableMethods.includes('buy') || availableBuySignatures.length > 0) {
                console.log("Используем метод buy...");

                // Определяем точную сигнатуру функции buy
                if (availableBuySignatures.includes('buy(uint256,uint256)')) {
                    console.log("Вызываем buy(uint256,uint256)");
                    let buyTx = await marketplace.connect(buyer)["buy(uint256,uint256)"](listingId, 0, {
                        gasLimit: 1000000
                    });
                    console.log("Транзакция отправлена:", buyTx.hash);
                    await buyTx.wait();
                } else if (availableBuySignatures.includes('buy(uint256)')) {
                    console.log("Вызываем buy(uint256)");
                    let buyTx = await marketplace.connect(buyer)["buy(uint256)"](listingId, {
                        gasLimit: 1000000
                    });
                    console.log("Транзакция отправлена:", buyTx.hash);
                    await buyTx.wait();
                } else {
                    console.log("Вызываем buy с одним параметром");
                    let buyTx = await marketplace.connect(buyer).buy(listingId, {
                        gasLimit: 1000000
                    });
                    console.log("Транзакция отправлена:", buyTx.hash);
                    await buyTx.wait();
                }
            }
            // Если методы не найдены, пробуем использовать интерфейс напрямую
            else {
                // Последняя попытка с прямым доступом к функциям
                const availableFunctions = Object.keys(marketplace.functions || {});

                if (availableFunctions.includes('purchase')) {
                    console.log("Используем функцию purchase из functions...");
                    let functionTx = await marketplace.functions.purchase(listingId, { gasLimit: 1000000 });
                    console.log("Транзакция отправлена:", functionTx.hash);
                    await functionTx.wait();
                } else if (availableFunctions.includes('buy')) {
                    console.log("Используем функцию buy из functions...");
                    let functionTx = await marketplace.functions.buy(listingId, { gasLimit: 1000000 });
                    console.log("Транзакция отправлена:", functionTx.hash);
                    await functionTx.wait();
                } else {
                    throw new Error("Не найдены методы для покупки товара");
                }
            }

            console.log("Покупка успешно завершена!");
            return true;
        } catch (purchaseError) {
            console.error("Все попытки покупки не удались:", 
                purchaseError instanceof Error ? purchaseError.message : "Неизвестная ошибка");
            throw purchaseError;
        }
    } catch (error) {
        console.error("Ошибка при покупке листинга:", 
            error instanceof Error ? error.message : "Неизвестная ошибка");

        // Дополнительная диагностика при ошибке
        try {
            const marketplaceAddress = await marketplace.getAddress();
            const buyerAllowance = await token.allowance(buyer.address, marketplaceAddress);
            const buyerBalance = await token.balanceOf(buyer.address);

            console.error("Диагностическая информация:")
            console.error(` - Адрес маркетплейса: ${marketplaceAddress}`);
            console.error(` - Разрешение для маркетплейса: ${ethers.formatEther(buyerAllowance)} токенов`);
            console.error(` - Баланс покупателя: ${ethers.formatEther(buyerBalance)} токенов`);
        } catch (diagError) {
            console.error("Ошибка при получении диагностической информации:", 
                diagError instanceof Error ? diagError.message : "Неизвестная ошибка");
        }

        throw error;
    }
}
