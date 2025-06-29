import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { ethers } from "ethers";
import CoreModule from "./CoreModule";

/**
 * Модуль для развертывания в публичной сети
 */
const PublicDeploy = buildModule("PublicDeploy", (m) => {
  const core = m.useModule(CoreModule);

  const FACTORY_ADMIN = ethers.keccak256(ethers.toUtf8Bytes("FACTORY_ADMIN"));
  const FEATURE_OWNER_ROLE = m.staticCall(core.access, "FEATURE_OWNER_ROLE");
  const GOVERNOR_ROLE = m.staticCall(core.access, "GOVERNOR_ROLE");
  const DEFAULT_ADMIN_ROLE = m.staticCall(core.access, "DEFAULT_ADMIN_ROLE");

  const deployer = m.getAccount(0);
  m.call(core.access, "grantRole", [DEFAULT_ADMIN_ROLE, deployer]);
  m.call(core.access, "grantRole", [FACTORY_ADMIN, deployer]);
  m.call(core.access, "grantRole", [FEATURE_OWNER_ROLE, deployer]);
  m.call(core.access, "grantRole", [GOVERNOR_ROLE, deployer]);

  const CONTEST_ID = ethers.keccak256(ethers.toUtf8Bytes("Contest"));
  const contestValidator = m.contract("ContestValidator", [core.access, core.tokenValidator]);
  const contestFactory = m.contract("ContestFactory", [core.registry, core.feeManager]);

  m.call(core.registry, "registerFeature", [CONTEST_ID, contestFactory, 0]);
  m.call(core.registry, "setModuleServiceAlias", [CONTEST_ID, "Validator", contestValidator]);

  return {
    ...core,
    contestFactory,
    contestValidator,
  };
});

export default PublicDeploy;
