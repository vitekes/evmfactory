import { ethers } from '../../hardhat-connection';
import type { CoreSystem } from '../../typechain-types';

const AUTHOR_ROLE = ethers.id('AUTHOR_ROLE');

async function grantRoleIfMissing(core: CoreSystem, role: string, account: string) {
  const hasRole = await core.hasRole(role, account);
  if (!hasRole) {
    await (await core.grantRole(role, account)).wait();
  }
}

export async function grantFeatureOwner(coreAddress: string, account: string) {
  const core = (await ethers.getContractAt('CoreSystem', coreAddress)) as CoreSystem;
  const role = await core.FEATURE_OWNER_ROLE();
  await grantRoleIfMissing(core, role, account);
}

export async function grantAuthorRole(coreAddress: string, account: string) {
  const core = (await ethers.getContractAt('CoreSystem', coreAddress)) as CoreSystem;
  await grantRoleIfMissing(core, AUTHOR_ROLE, account);
}

export async function grantAutomationRole(coreAddress: string, account: string) {
  const core = (await ethers.getContractAt('CoreSystem', coreAddress)) as CoreSystem;
  const role = await core.AUTOMATION_ROLE();
  await grantRoleIfMissing(core, role, account);
}

export async function grantOperatorRole(coreAddress: string, account: string) {
  const core = (await ethers.getContractAt('CoreSystem', coreAddress)) as CoreSystem;
  const role = await core.OPERATOR_ROLE();
  await grantRoleIfMissing(core, role, account);
}
