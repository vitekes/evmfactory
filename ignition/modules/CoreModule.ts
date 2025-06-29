import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { ethers } from "ethers";

/**
 * Модуль развертывания основных контрактов системы
 */
const CoreModule = buildModule("CoreModule", (m) => {
  const ACCESS_SERVICE = ethers.keccak256(
    ethers.toUtf8Bytes("AccessControlCenter")
  );
  const PAYMENT_GATEWAY_SERVICE = ethers.keccak256(
    ethers.toUtf8Bytes("PaymentGateway")
  );
  const VALIDATOR_SERVICE = ethers.keccak256(
    ethers.toUtf8Bytes("SERVICE_VALIDATOR")
  );
  const MARKETPLACE_ID = ethers.keccak256(ethers.toUtf8Bytes("Marketplace"));

  const access = m.contract("AccessControlCenter", []);
  const registry = m.contract("Registry", [access]);
  const feeManager = m.contract("CoreFeeManager", []);
  m.call(feeManager, "initialize", [access]);

  m.call(registry, "setCoreService", [ACCESS_SERVICE, access]);
  m.call(registry, "setCoreService", [PAYMENT_GATEWAY_SERVICE, feeManager]);

  const gateway = m.contract("PaymentGateway", []);
  m.call(gateway, "initialize", [access, registry, feeManager]);

  const tokenValidator = m.contract("MultiValidator", []);
  m.call(tokenValidator, "initialize", [access]);

  const marketplaceFactory = m.contract("MarketplaceFactory", [registry, gateway]);
  m.call(registry, "registerFeature", [MARKETPLACE_ID, marketplaceFactory, 0]);
  m.call(registry, "setModuleService", [MARKETPLACE_ID, VALIDATOR_SERVICE, tokenValidator]);

  const priceFeed = m.contract("MockPriceFeed", []);

  return {
    access,
    registry,
    feeManager,
    gateway,
    tokenValidator,
    marketplaceFactory,
    priceFeed,
  };
});

export default CoreModule;
