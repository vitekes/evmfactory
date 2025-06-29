import { Contract } from "ethers";
import { CONSTANTS } from "./constants";

/**
 * Проверяет и выдает все необходимые роли для указанного адреса
 * @param acl Контракт управления доступом
 * @param address Адрес, которому нужно выдать роли
 */
export async function ensureRoles(acl: any, address: string) {
    console.log(`Проверка и выдача ролей для адреса ${address}...`);

    try {
        // Получаем идентификаторы всех ролей
        const governorRole = await acl.GOVERNOR_ROLE();
        const defaultAdminRole = await acl.DEFAULT_ADMIN_ROLE();
        const moduleRole = await acl.MODULE_ROLE();
        const featureOwnerRole = await acl.FEATURE_OWNER_ROLE();
        const factoryAdminRole = CONSTANTS.FACTORY_ADMIN;

        // Проверяем каждую роль и выдаем при необходимости
        const roles = [
            { name: "GOVERNOR_ROLE", id: governorRole },
            { name: "DEFAULT_ADMIN_ROLE", id: defaultAdminRole },
            { name: "MODULE_ROLE", id: moduleRole },
            { name: "FEATURE_OWNER_ROLE", id: featureOwnerRole },
            { name: "FACTORY_ADMIN", id: factoryAdminRole }
        ];

        for (const role of roles) {
            const hasRole = await acl.hasRole(role.id, address);
            console.log(`- ${role.name}: ${hasRole ? 'уже выдана' : 'отсутствует'}`);

            if (!hasRole) {
                console.log(`  🔄 Выдаем роль ${role.name} адресу ${address}...`);
                const tx = await acl.grantRole(role.id, address);
                await tx.wait();

                // Проверяем, что роль действительно выдана
                const roleGranted = await acl.hasRole(role.id, address);
                console.log(`  ${roleGranted ? '✓' : '✗'} Роль ${role.name} ${roleGranted ? 'успешно выдана' : 'НЕ ВЫДАНА!'}`);

                if (!roleGranted && role.name === "FACTORY_ADMIN") {
                    throw new Error(`Не удалось выдать роль FACTORY_ADMIN адресу ${address}`);
                }
            }
        }

        // Дополнительная проверка роли FACTORY_ADMIN
        const hasFactoryAdmin = await acl.hasRole(factoryAdminRole, address);
        if (!hasFactoryAdmin) {
            console.log(`⚠️ ВНИМАНИЕ: Роль FACTORY_ADMIN не была выдана адресу ${address} даже после попытки выдачи!`);
            console.log(`  🔄 Повторная попытка выдачи роли FACTORY_ADMIN...`);
            await acl.grantRole(factoryAdminRole, address);

            const roleGranted = await acl.hasRole(factoryAdminRole, address);
            console.log(`  ${roleGranted ? '✓' : '✗'} Роль FACTORY_ADMIN ${roleGranted ? 'успешно выдана' : 'НЕ ВЫДАНА после повторной попытки!'}`);
        }

        console.log(`Все необходимые роли для ${address} проверены и выданы`);
    } catch (error) {
        console.error("Ошибка при выдаче ролей:", error instanceof Error ? error.message : "Неизвестная ошибка");
        throw error;
    }
}
