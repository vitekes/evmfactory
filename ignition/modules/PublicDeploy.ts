import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { ethers } from "ethers";
import CoreModule from "./CoreModule";

const PublicDeploy = buildModule("PublicDeploy", (m) => {
  const { access, registry, feeManager, gateway, tokenValidator } = m.useModule(CoreModule);

  const treasury = m.getParameter("treasuryAddress");
  const weth = m.getParameter("wethAddress");
  const usdc = m.getParameter("usdcAddress");
  const usdt = m.getParameter("usdtAddress");
  const wethFeed = m.getParameter("wethPriceFeed");
  const usdcFeed = m.getParameter("usdcPriceFeed");
  const usdtFeed = m.getParameter("usdtPriceFeed");
  const multisig = m.getParameter("multisigAddress");

  const FACTORY_ADMIN = ethers.keccak256(ethers.toUtf8Bytes("FACTORY_ADMIN"));
  const deployer = m.getAccount(0);
  m.call(access, "grantRole", [FACTORY_ADMIN, deployer]);
  m.call(access, "grantRole", [m.staticCall(access, "FEATURE_OWNER_ROLE"), deployer]);
  m.call(access, "grantRole", [m.staticCall(access, "GOVERNOR_ROLE"), deployer]);
  m.call(access, "grantRole", [m.staticCall(access, "GOVERNOR_ROLE"), multisig]);

  const contestValidator = m.contract("ContestValidator", [access, tokenValidator]);
  const contestFactory = m.contract("ContestFactory", [registry, feeManager]);
  const CONTEST_ID = ethers.keccak256(ethers.toUtf8Bytes("Contest"));
  m.call(registry, "registerFeature", [CONTEST_ID, contestFactory, 0]);
  m.call(registry, "setModuleServiceAlias", [CONTEST_ID, "Validator", contestValidator]);

  m.call(tokenValidator, "addToken", [weth]);
  m.call(tokenValidator, "addToken", [usdc]);
  m.call(tokenValidator, "addToken", [usdt]);
import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { ethers } from "ethers";
import CoreModule from "./CoreModule";

/**
 * Модуль для развертывания в публичной сети
 */
const PublicDeploy = buildModule("PublicDeploy", (m) => {
  // Импортируем базовые контракты из CoreModule
  const core = m.useModule(CoreModule);

  // Получаем константы ролей
  const FACTORY_ADMIN = ethers.keccak256(ethers.toUtf8Bytes("FACTORY_ADMIN"));
  const FEATURE_OWNER_ROLE = m.staticCall(core.access, "FEATURE_OWNER_ROLE");
  const GOVERNOR_ROLE = m.staticCall(core.access, "GOVERNOR_ROLE");
  const DEFAULT_ADMIN_ROLE = m.staticCall(core.access, "DEFAULT_ADMIN_ROLE");

  // Получаем адрес развертывателя
  const deployer = m.getAccount(0);

  // Назначаем роли
  m.call(core.access, "grantRole", [DEFAULT_ADMIN_ROLE, deployer]);
  m.call(core.access, "grantRole", [FACTORY_ADMIN, deployer]);
  m.call(core.access, "grantRole", [FEATURE_OWNER_ROLE, deployer]);
  m.call(core.access, "grantRole", [GOVERNOR_ROLE, deployer]);

  // Разворачиваем дополнительные модули для публичной сети
  const CONTEST_ID = ethers.keccak256(ethers.toUtf8Bytes("Contest"));
  const contestValidator = m.contract("ContestValidator", [core.access, core.tokenValidator]);
  const contestFactory = m.contract("ContestFactory", [core.registry, core.feeManager]);

  // Регистрируем модуль конкурсов
  m.call(core.registry, "registerFeature", [CONTEST_ID, contestFactory, 0]);
  m.call(core.registry, "setModuleServiceAlias", [CONTEST_ID, "Validator", contestValidator]);

  return {
    ...core,
    contestFactory,
    contestValidator
  };
});

export default PublicDeploy;
  return { access, registry, feeManager, gateway, contestFactory };
});

export default PublicDeploy;
