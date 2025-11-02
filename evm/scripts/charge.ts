import { ethers } from 'hardhat';
import type { Signer } from 'ethers';
import type { SubscriptionManager, PlanManager, CoreSystem } from '../typechain-types';

async function ensureAutomationRole(core: CoreSystem, adminSigner: Signer, automationAddress: string) {
  const AUTOMATION_ROLE = ethers.id('AUTOMATION_ROLE');
  const hasRole = await core.hasRole(AUTOMATION_ROLE, automationAddress);
  if (hasRole) {
    return;
  }

  try {
    const tx = await core.connect(adminSigner).grantRole(AUTOMATION_ROLE, automationAddress);
    await tx.wait();
    console.log(`Granted AUTOMATION_ROLE to ${automationAddress}`);
  } catch (error) {
    console.warn('Failed to grant AUTOMATION_ROLE automatically. Continuing assuming it is already set.', error);
  }
}

async function ensureNativeDeposit(
  subscriptionManager: SubscriptionManager,
  planManager: PlanManager,
  subscriberSigner: Signer,
) {
  const subscriberAddress = await subscriberSigner.getAddress();
  const planHashes = await subscriptionManager.listUserPlans(subscriberAddress);

  let activePlanHash: string | null = null;

  for (const hash of planHashes) {
    const state = await subscriptionManager.getSubscriptionByPlan(subscriberAddress, hash);
    if (state.status === 1) {
      if (activePlanHash) {
        throw new Error('Multiple active plans detected; use charge(user, planHash) instead.');
      }
      activePlanHash = hash;
    }
  }

  if (!activePlanHash) {
    throw new Error('No active plan found for subscriber');
  }

  const plan = await planManager.getPlan(activePlanHash);
  if (plan.token !== ethers.ZeroAddress) {
    // ERC20 plans rely on allowances and do not need native deposits.
    return;
  }

  const requiredBalance = plan.price;
  const currentDeposit = await subscriptionManager.getNativeDeposit(subscriberAddress);

  if (currentDeposit >= requiredBalance) {
    return;
  }

  const difference = requiredBalance - currentDeposit;
  const tx = await subscriptionManager.connect(subscriberSigner).depositNativeFunds({ value: difference });
  await tx.wait();

  const updatedDeposit = await subscriptionManager.getNativeDeposit(subscriberAddress);
  console.log(
    `Deposited ${ethers.formatEther(difference)} ETH for ${subscriberAddress}. New balance: ${ethers.formatEther(
      updatedDeposit,
    )} ETH`,
  );
}

async function main() {
  const signers = await ethers.getSigners();
  const adminSigner = signers[0]!;
  const subscriberSigner = signers[2]!;
  const automationAddress = await adminSigner.getAddress();

  const subscriptionManagerAddress = '0x9A676e781A523b5d0C0e43731313A708CB607508';

  const subscriptionManager = (await ethers.getContractAt(
    'SubscriptionManager',
    subscriptionManagerAddress,
    adminSigner,
  )) as SubscriptionManager;

  const coreAddress = await subscriptionManager.core();
  const core = (await ethers.getContractAt('CoreSystem', coreAddress, adminSigner)) as CoreSystem;

  await ensureAutomationRole(core, adminSigner, automationAddress);

  const MODULE_ID = await subscriptionManager.MODULE_ID();
  const planManagerAddress = await core.getService(MODULE_ID, 'PlanManager');
  if (planManagerAddress === ethers.ZeroAddress) {
    throw new Error('PlanManager not configured in CoreSystem');
  }

  const planManager = (await ethers.getContractAt('PlanManager', planManagerAddress, adminSigner)) as PlanManager;

  await ensureNativeDeposit(subscriptionManager, planManager, subscriberSigner);

  const subscriberAddress = await subscriberSigner.getAddress();
  console.log(`Charging subscription for ${subscriberAddress}...`);
  const chargeTx = await subscriptionManager.charge(subscriberAddress);
  const receipt = await chargeTx.wait();
  console.log(`Charge transaction hash: ${receipt?.hash}`);
}

main().catch((error) => {
  console.error('Charge script failed:', error);
  process.exitCode = 1;
});
