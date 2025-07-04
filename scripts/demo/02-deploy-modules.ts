import { ethers } from 'hardhat';
import { deployCore, setupCoreConnections, registerModule } from './utils/system';
import { deployMarketplaceModule, deploySubscriptionModule, deployContestModule } from './utils/modules';

async function main() {
  console.log('=== Демонстрация: Развертывание и настройка модулей ===');

  // Получаем администратора
  const [admin] = await ethers.getSigners();

  // 1. Получаем ядро системы (предполагается, что оно уже развернуто)
  const coreContracts = await deployCore(); // В реальном сценарии здесь будет загрузка существующих контрактов
  await setupCoreConnections(coreContracts);

  // 2. Развертывание модуля маркетплейса
  const marketplace = await deployMarketplaceModule(coreContracts);

  // 3. Развертывание модуля подписок
  const subscription = await deploySubscriptionModule(coreContracts);

  // 4. Развертывание модуля конкурсов
  const contest = await deployContestModule(coreContracts);

  // 5. Регистрация модулей в системе
  await registerModule(coreContracts, {
    moduleId: marketplace.moduleId,
    name: marketplace.name,
    factoryAddress: await marketplace.factory.getAddress(),
    services: {
      'MarketplaceFactory': await marketplace.factory.getAddress()
    }
  });

  await registerModule(coreContracts, {
    moduleId: subscription.moduleId,
    name: subscription.name,
    factoryAddress: await subscription.factory.getAddress(),
    services: {
      'SubscriptionFactory': await subscription.factory.getAddress()
    }
  });

  await registerModule(coreContracts, {
    moduleId: contest.moduleId,
    name: contest.name,
    factoryAddress: await contest.factory.getAddress(),
    validator: contest.validator,
    services: {
      'ContestFactory': await contest.factory.getAddress(),
      'ContestValidator': await contest.validator.getAddress()
    }
  });

  console.log('\n=== Все модули успешно развернуты и зарегистрированы ===');
  console.log('Перейдите к демонстрационным сценариям для каждого модуля');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
