import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { ethers } from "ethers";

/**
 * Модуль развертывания основных контрактов системы
 */
const CoreModule = buildModule("CoreModule", (m) => {
  // Используем константы соответствующие CoreDefs.sol
  const ACCESS_SERVICE = ethers.keccak256(
    ethers.toUtf8Bytes("AccessControlCenter")
  );
  const PAYMENT_GATEWAY_SERVICE = ethers.keccak256(
    ethers.toUtf8Bytes("PaymentGateway")
  );
  const FEE_MANAGER_SERVICE = ethers.keccak256(
    ethers.toUtf8Bytes("CoreFeeManager")
  );
  const VALIDATOR_SERVICE = ethers.keccak256(
    ethers.toUtf8Bytes("Validator")
  );
  const PRICE_ORACLE_SERVICE = ethers.keccak256(
    ethers.toUtf8Bytes("PriceOracle")
  );
  const MARKETPLACE_ID = ethers.keccak256(ethers.toUtf8Bytes("Marketplace"));

  const access = m.contract("AccessControlCenter", []);
  const registry = m.contract("Registry", [access]);
  const feeManager = m.contract("CoreFeeManager", []);
  m.call(feeManager, "initialize", [access]);

  m.call(registry, "setCoreService", [ACCESS_SERVICE, access]);
  m.call(registry, "setCoreService", [FEE_MANAGER_SERVICE, feeManager]);

  // Развертывание и инициализация платежного шлюза
  // Используется напрямую без ImportedERC1967Proxy, так как контракт уже поддерживает обновляемость через UUPS
  const gateway = m.contract("PaymentGateway", []);
  m.call(gateway, "initialize", [access, registry, feeManager]);
  m.call(registry, "setCoreService", [PAYMENT_GATEWAY_SERVICE, gateway]);

  const tokenValidator = m.contract("MultiValidator", []);
  m.call(tokenValidator, "initialize", [access]);

  // Разворачиваем оракул цен Chainlink и регистрируем его
  const priceOracle = m.contract("ChainlinkPriceOracle", [access]);

  // Регистрируем маркетплейс и связанные сервисы
  const marketplaceFactory = m.contract("MarketplaceFactory", [registry, gateway]);
  m.call(registry, "registerFeature", [MARKETPLACE_ID, marketplaceFactory, 0]);
  m.call(registry, "setModuleService", [MARKETPLACE_ID, VALIDATOR_SERVICE, tokenValidator]);
  m.call(registry, "setModuleService", [MARKETPLACE_ID, PRICE_ORACLE_SERVICE, priceOracle]);
  m.call(registry, "setModuleServiceAlias", [MARKETPLACE_ID, "Validator", tokenValidator]);
  m.call(registry, "setModuleServiceAlias", [MARKETPLACE_ID, "PriceOracle", priceOracle]);
  m.call(registry, "setModuleServiceAlias", [MARKETPLACE_ID, "PaymentGateway", gateway]);

  return {
    access,
    registry,
    feeManager,
    gateway,
    tokenValidator,
    marketplaceFactory,
    priceOracle,
  };
});

export default CoreModule;
