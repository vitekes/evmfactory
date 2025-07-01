/**
 * Модуль функций для работы с маркетплейсом
 * 
 * Содержит функции для создания и взаимодействия с маркетплейсом
 */

import { ethers } from "hardhat";
import { Contract } from "ethers";

/** Helper that grants required roles to a marketplace instance */
async function setupMarketplaceRoles(registry: Contract, addr: string) {
    const aclAddress = await registry.getCoreService(
        ethers.keccak256(ethers.toUtf8Bytes("AccessControlCenter"))
    );
    const acl = await ethers.getContractAt("AccessControlCenter", aclAddress);
    const moduleRole = await acl.MODULE_ROLE();
    const featureOwnerRole = await acl.FEATURE_OWNER_ROLE();
    const relayerRole = await acl.RELAYER_ROLE();

    if (!(await acl.hasRole(moduleRole, addr))) {
        const tx = await acl.grantRole(moduleRole, addr);
        await tx.wait();
    }
    if (!(await acl.hasRole(featureOwnerRole, addr))) {
        const tx = await acl.grantRole(featureOwnerRole, addr);
        await tx.wait();
    }
    if (!(await acl.hasRole(relayerRole, addr))) {
        const tx = await acl.grantRole(relayerRole, addr);
        await tx.wait();
    }
}

/**
 * Создает маркетплейс через фабрику или напрямую (если вызов фабрики завершается ошибкой)
 * @param marketplaceFactory Контракт фабрики маркетплейса
 * @param registry Контракт реестра
 * @param validator Контракт валидатора
 * @param gateway Контракт платежного шлюза
 * @returns Адрес созданного маркетплейса
 */
export async function createMarketplace(
    marketplaceFactory: Contract, 
    registry: Contract, 
    validator: Contract,
    gateway: Contract
): Promise<string> {
    console.log("Пытаемся создать маркетплейс через фабрику...");

    try {
        // Пробуем создать маркетплейс через фабрику
        const tx = await marketplaceFactory.createMarketplace();
        const receipt = await tx.wait();

        // Получаем адрес созданного маркетплейса из события в транзакции
        const event = receipt.logs
            .map((log: any) => {
                try {
                    return marketplaceFactory.interface.parseLog(log as any);
                } catch (e) {
                    return null;
                }
            })
            .find((event: any) => event && event.name === "MarketplaceCreated");

        if (event && event.args) {
            const marketplaceAddress = event.args.marketplace;
            console.log(`Маркетплейс успешно создан через фабрику: ${marketplaceAddress}`);
            await setupMarketplaceRoles(registry, marketplaceAddress);
            return marketplaceAddress;
        } else {
            throw new Error("Не удалось найти событие MarketplaceCreated в транзакции");
        }
    } catch (error) {
        console.log(`Не удалось создать маркетплейс через фабрику: ${error instanceof Error ? error.message : 'Неизвестная ошибка'}`);
        console.log("Создаем маркетплейс напрямую...");

        // Создаем маркетплейс напрямую
        return await createMarketplaceDirectly(registry, validator, gateway);
    }
}

/**
 * Создает маркетплейс через прокси (для будущего использования)
 * @param registry Контракт реестра
 * @param validator Контракт валидатора
 * @param gateway Контракт платежного шлюза
 * @returns Адрес созданного маркетплейса через прокси
 */
export async function createMarketplaceViaProxy(
    registry: Contract, 
    validator: Contract,
    gateway: Contract
): Promise<string> {
    console.log("Создание маркетплейса через прокси в настоящее время не реализовано");
    console.log("Используем прямое создание маркетплейса...");

    return await createMarketplaceDirectly(registry, validator, gateway);
}

/**
 * Вспомогательная функция для прямого создания маркетплейса без использования фабрики
 * @param registry Контракт реестра
 * @param validator Контракт валидатора
 * @param gateway Контракт платежного шлюза
 * @returns Адрес созданного маркетплейса
 */
async function createMarketplaceDirectly(
    registry: Contract, 
    validator: Contract,
    gateway: Contract
): Promise<string> {
    // Создаем уникальный идентификатор для маркетплейса
    const instanceId = ethers.keccak256(ethers.toUtf8Bytes(`Marketplace:${Date.now()}`));
    console.log(`Создан идентификатор инстанса: ${instanceId}`);

    // Получаем адреса необходимых контрактов
    const registryAddress = await registry.getAddress();
    const gatewayAddress = await gateway.getAddress();

    // Создаем маркетплейс
    console.log("Деплоим контракт маркетплейса...");
    const Marketplace = await ethers.getContractFactory("Marketplace");
    const marketplace = await Marketplace.deploy(
        registryAddress,
        gatewayAddress,
        instanceId
    );
    await marketplace.waitForDeployment();
    const marketplaceAddress = await marketplace.getAddress();
    console.log(`Маркетплейс создан: ${marketplaceAddress}`);

    // Регистрируем маркетплейс в системе
    console.log("Регистрируем маркетплейс в реестре...");
    await registry.registerFeature(instanceId, marketplaceAddress, 1);

    // Настраиваем сервисы для маркетплейса
    console.log("Настраиваем сервисы для маркетплейса...");
    const validatorAddr = await validator.getAddress();
    await registry.setModuleServiceAlias(instanceId, "Validator", validatorAddr);
    await registry.setModuleServiceAlias(instanceId, "PaymentGateway", gatewayAddress);

    // Получаем контракт управления доступом
    await setupMarketplaceRoles(registry, marketplaceAddress);

    console.log(`Маркетплейс успешно создан и настроен!`);
    return marketplaceAddress;
}
