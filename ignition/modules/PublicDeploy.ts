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

  return { access, registry, feeManager, gateway, contestFactory };
});

export default PublicDeploy;
