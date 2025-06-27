import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { ethers } from "ethers";
import CoreModule from "./CoreModule";

const LocalDeploy = buildModule("LocalDeploy", (m) => {
  const { access, registry, feeManager, gateway, tokenValidator } = m.useModule(CoreModule);

  const FACTORY_ADMIN = ethers.keccak256(ethers.toUtf8Bytes("FACTORY_ADMIN"));
  const deployer = m.getAccount(0);
  m.call(access, "grantRole", [FACTORY_ADMIN, deployer]);
  m.call(access, "grantRole", [m.staticCall(access, "FEATURE_OWNER_ROLE"), deployer]);
  m.call(access, "grantRole", [m.staticCall(access, "GOVERNOR_ROLE"), deployer]);

  const token = m.contract("TestToken", ["Demo", "DEMO"]);

  const contestValidator = m.contract("ContestValidator", [access, tokenValidator]);
  const contestFactory = m.contract("ContestFactory", [registry, feeManager]);
  const CONTEST_ID = ethers.keccak256(ethers.toUtf8Bytes("Contest"));
  m.call(registry, "registerFeature", [CONTEST_ID, contestFactory, 0]);
  m.call(registry, "setModuleServiceAlias", [CONTEST_ID, "Validator", contestValidator]);

  return { access, registry, feeManager, gateway, token, contestFactory };
});

export default LocalDeploy;
