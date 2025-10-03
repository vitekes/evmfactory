import { ethers } from 'hardhat';
import type { CoreSystem } from '../../typechain-types';

export async function grantFeatureOwner(coreAddress: string, account: string) {
  const core = (await ethers.getContractAt('CoreSystem', coreAddress)) as CoreSystem;
  const role = await core.FEATURE_OWNER_ROLE();
  const hasRole = await core.hasRole(role, account);
  if (!hasRole) {
    await (await core.grantRole(role, account)).wait();
  }
}
