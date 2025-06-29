import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { ethers } from "ethers";

const CoreModule = buildModule("CoreModule", (m) => {
  m.getParameter("treasuryAddress", ethers.ZeroAddress);
  m.getParameter("platformFeePercentage", 0);
  m.getParameter("minContestDuration", 0);
  m.getParameter("maxContestDuration", 0);

  const deployer = m.getAccount(0);

  const access = m.contract("AccessControlCenter");
  m.call(access, "initialize", [deployer]);

  const registry = m.contract("Registry");
  m.call(registry, "initialize", [access]);
import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { ethers } from "ethers";

/**
 * Модуль развертывания основных контрактов системы
 */
const CoreModule = buildModule("CoreModule", async (m) => {
  // Константы модулей и сервисов
  const ACCESS_SERVICE = ethers.keccak256(ethers.toUtf8Bytes("AccessControlCenter"));
  const PAYMENT_GATEWAY_SERVICE = ethers.keccak256(ethers.toUtf8Bytes("PaymentGateway"));
  const VALIDATOR_SERVICE = ethers.keccak256(ethers.toUtf8Bytes("SERVICE_VALIDATOR"));
  const MARKETPLACE_ID = ethers.keccak256(ethers.toUtf8Bytes("Marketplace"));

  // Развертывание базовых контрактов
  const access = m.contract("AccessControlCenter", []);
  const registry = m.contract("Registry", [access]);
  const feeManager = m.contract("CoreFeeManager", []);
  m.call(feeManager, "initialize", [access]);

  // Регистрация базовых сервисов в реестре
  m.call(registry, "setCoreService", [ACCESS_SERVICE, access]);
  m.call(registry, "setCoreService", [PAYMENT_GATEWAY_SERVICE, feeManager]);

  // Развертывание и инициализация платежного шлюза
  const gateway = m.contract("PaymentGateway", []);
  m.call(gateway, "initialize", [access, registry, feeManager]);

  // Развертывание валидатора токенов
  const tokenValidator = m.contract("MultiValidator", []);
  m.call(tokenValidator, "initialize", [access]);

  // Регистрация маркетплейса
  const marketplaceFactory = m.contract("MarketplaceFactory", [registry, gateway]);
  m.call(registry, "registerFeature", [MARKETPLACE_ID, marketplaceFactory, 0]);
  m.call(registry, "setModuleService", [MARKETPLACE_ID, VALIDATOR_SERVICE, tokenValidator]);

  // Настройка прайс-фида для тестовой сети (опционально)
  const priceFeed = m.contract("MockPriceFeed", []);

  return {
    access,
    registry,
    feeManager,
    gateway,
    tokenValidator,
    marketplaceFactory,
    priceFeed
  };
});

export default CoreModule;
  const feeManager = m.contract("CoreFeeManager");
  m.call(feeManager, "initialize", [access]);

  const gateway = m.contract("PaymentGateway");
  m.call(gateway, "initialize", [access, registry, feeManager]);

  const tokenValidator = m.contract("MultiValidator");
  m.call(tokenValidator, "initialize", [access]);

  return { access, registry, feeManager, gateway, tokenValidator };
});

export default CoreModule;
