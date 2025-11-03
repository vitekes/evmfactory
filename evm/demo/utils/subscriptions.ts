import { ethers } from 'hardhat';
import type { ContractTransactionReceipt, Signer } from 'ethers';
import type { PaymentGateway, PlanManager, SubscriptionManager } from '../../typechain-types';
import { log } from './logging';
import { logPaymentProcessed, parsePaymentProcessed, type PaymentProcessedEvent } from './payments';

const PLAN_TYPES = {
  Plan: [
    { name: 'chainIds', type: 'uint256[]' },
    { name: 'price', type: 'uint256' },
    { name: 'period', type: 'uint256' },
    { name: 'token', type: 'address' },
    { name: 'merchant', type: 'address' },
    { name: 'salt', type: 'uint256' },
    { name: 'expiry', type: 'uint64' },
  ],
} as const;

export async function signPlan(
  merchant: Signer,
  subscriptionManagerAddress: string,
  plan: SubscriptionManager.PlanStruct
): Promise<string> {
  const provider = merchant.provider;
  if (!provider) throw new Error('Merchant signer missing provider');
  const network = await provider.getNetwork();
  const domain = {
    chainId: network.chainId,
    verifyingContract: subscriptionManagerAddress,
  } as const;
  return merchant.signTypedData(domain, PLAN_TYPES, plan);
}

export async function ensurePlanRegistered(
  planManager: PlanManager,
  subscriptionManager: SubscriptionManager,
  merchant: Signer,
  plan: SubscriptionManager.PlanStruct,
  signature: string,
  metadataUri: string
): Promise<string> {
  const planHash = await subscriptionManager.hashPlan(plan);

  let exists = false;
  try {
    const stored = await planManager.getPlan(planHash);
    exists = stored.merchant !== ethers.ZeroAddress;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (!message.includes('PlanNotFound')) {
      throw error;
    }
  }

  if (exists) {
    log.info(`Plan ${planHash} already registered, skipping creation.`);
    return planHash;
  }

  log.info(`Registering plan ${planHash}...`);
  await (
    await planManager
      .connect(merchant)
      .createPlan(plan, signature, metadataUri)
  ).wait();
  log.success(`Plan ${planHash} registered.`);
  return planHash;
}

export async function subscribeWithLogging(
  subscriptionManager: SubscriptionManager,
  subscriber: Signer,
  plan: SubscriptionManager.PlanStruct,
  signature: string,
  gateway: PaymentGateway,
  metadata: string
): Promise<{ receipt: ContractTransactionReceipt; event: PaymentProcessedEvent | null }> {
  log.info('Subscribing user to plan...');
  const tx = await subscriptionManager.connect(subscriber).subscribe(plan, signature, metadata);
  const receipt = await tx.wait();
  log.success('Subscription transaction confirmed.');

  const event = parsePaymentProcessed(receipt, gateway);
  logPaymentProcessed(event);
  return { receipt, event };
}

export async function chargeNextCycle(
  subscriptionManager: SubscriptionManager,
  operator: Signer,
  subscriber: string,
  planHash: string,
  gateway: PaymentGateway
): Promise<{ receipt: ContractTransactionReceipt; event: PaymentProcessedEvent | null }> {
  log.info('Triggering recurring charge...');
  const tx = await subscriptionManager.connect(operator)['charge(address,bytes32)'](subscriber, planHash);
  const receipt = await tx.wait();
  log.success('Recurring charge mined.');
  const event = parsePaymentProcessed(receipt, gateway);
  logPaymentProcessed(event);
  return { receipt, event };
}

export async function fastForward(seconds: bigint) {
  log.info(`Fast-forwarding time by ${seconds.toString()} seconds...`);
  await ethers.provider.send('evm_increaseTime', [Number(seconds)]);
  await ethers.provider.send('evm_mine', []);
}
