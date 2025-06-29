import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { ethers } from "ethers";
import CoreModule from "./CoreModule";

/**
 * Модуль для локального развертывания с тестовыми токенами
 */
const LocalDeploy = buildModule("LocalDeploy", (m) => {
  // Импортируем базовые контракты
  const core = m.useModule(CoreModule);

  // Назначаем все необходимые роли развертывателю
  const deployer = m.getAccount(0);
  const FACTORY_ADMIN = ethers.keccak256(ethers.toUtf8Bytes("FACTORY_ADMIN"));
  const FEATURE_OWNER_ROLE = m.staticCall(core.access, "FEATURE_OWNER_ROLE");
  const GOVERNOR_ROLE = m.staticCall(core.access, "GOVERNOR_ROLE");
  const DEFAULT_ADMIN_ROLE = m.staticCall(core.access, "DEFAULT_ADMIN_ROLE");

  m.call(core.access, "grantRole", [DEFAULT_ADMIN_ROLE, deployer]);
  m.call(core.access, "grantRole", [FACTORY_ADMIN, deployer]);
  m.call(core.access, "grantRole", [FEATURE_OWNER_ROLE, deployer]);
  m.call(core.access, "grantRole", [GOVERNOR_ROLE, deployer]);

  // Создаем тестовый токен
  const token = m.contract("TestToken", ["Demo", "DEMO"]);

  // Разворачиваем модуль конкурсов
  const CONTEST_ID = ethers.keccak256(ethers.toUtf8Bytes("Contest"));
  const contestValidator = m.contract("ContestValidator", [core.access, core.tokenValidator]);
  const contestFactory = m.contract("ContestFactory", [core.registry, core.feeManager]);

  // Регистрируем модуль конкурсов
  m.call(core.registry, "registerFeature", [CONTEST_ID, contestFactory, 0]);
  m.call(core.registry, "setModuleServiceAlias", [CONTEST_ID, "Validator", contestValidator]);

  // Добавляем тестовый токен в валидатор
  m.call(core.tokenValidator, "addToken", [token]);

  return {
    ...core,
    token,
    contestFactory,
    contestValidator
  };
});

export default LocalDeploy;
