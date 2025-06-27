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

  const feeManager = m.contract("CoreFeeManager");
  m.call(feeManager, "initialize", [access]);

  const gateway = m.contract("PaymentGateway");
  m.call(gateway, "initialize", [access, registry, feeManager]);

  const tokenValidator = m.contract("MultiValidator");
  m.call(tokenValidator, "initialize", [access]);

  return { access, registry, feeManager, gateway, tokenValidator };
});

export default CoreModule;
