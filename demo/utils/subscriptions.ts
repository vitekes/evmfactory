import { ethers } from '../../hardhat-connection';
import type { ContractTransactionReceipt, Signer } from 'ethers';
import type { PaymentGateway, PlanManager, SubscriptionManager } from '../../typechain-types';
import { log } from './logging';
import { logPaymentProcessed, parsePaymentProcessed, type PaymentProcessedEvent } from './payments';

export async function subscribeWithLogging(
  subscriptionManager: SubscriptionManager,
  subscriber: Signer,
  plan: SubscriptionManager.PlanStruct,
  signature: string,
  gateway: PaymentGateway,
  permit: string,
  planUri?: string
): Promise<{ receipt: ContractTransactionReceipt; event: PaymentProcessedEvent | null }> {
  log.info('Subscribing user to plan...');
  const tx =
    planUri !== undefined
      ? await subscriptionManager
          .connect(subscriber)
          [
            'subscribe((uint256[],uint256,uint256,address,address,uint256,uint64),bytes,bytes,string)'
          ](plan, signature, permit, planUri)
      : await subscriptionManager.connect(subscriber).subscribe(plan, signature, permit);
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

export async function logPlanSnapshot(planManager: PlanManager, planHash: string) {
  const plan = await planManager.getPlan(planHash);
  log.info(
    `Plan stored on-chain: merchant=${plan.merchant}, price=${plan.price.toString()}, period=${plan.period}, token=${plan.token}, uri=${plan.uri}`,
  );
}
