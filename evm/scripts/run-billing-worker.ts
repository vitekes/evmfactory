#!/usr/bin/env ts-node
import fs from 'fs/promises';
import path from 'path';
import { ethers } from 'hardhat';
import type { SubscriptionManager } from '../typechain-types';

type BillingConfig = {
  subscriptionManager: string;
  subscribers: string[];
};

type ChargeResult = {
  user: string;
  planHash: string;
  status: 'charged' | 'retry-scheduled' | 'skipped';
  reason?: string;
};

function isCustomError(error: unknown, key: string): boolean {
  if (!error) return false;
  const message = (error as Error).message ?? String(error);
  return message.includes(key);
}

async function loadConfig(configPath: string): Promise<BillingConfig> {
  const absolutePath = path.isAbsolute(configPath) ? configPath : path.join(process.cwd(), configPath);
  const raw = await fs.readFile(absolutePath, 'utf8');
  const parsed = JSON.parse(raw) as BillingConfig;

  if (!parsed.subscriptionManager) {
    throw new Error('Missing subscriptionManager address in config.');
  }
  if (!Array.isArray(parsed.subscribers) || parsed.subscribers.length === 0) {
    throw new Error('Config must include at least one subscriber address.');
  }
  return parsed;
}

async function loadSubscriptionManager(address: string): Promise<SubscriptionManager> {
  return (await ethers.getContractAt('SubscriptionManager', address)) as SubscriptionManager;
}

async function collectActivePlans(
  manager: SubscriptionManager,
  user: string,
): Promise<{ planHash: string; nextChargeAt: bigint; retryAt: bigint; status: number }> {
  const planIds = await manager.listUserPlans(user);
  for (const planHash of planIds) {
    const state = await manager.getSubscriptionByPlan(user, planHash);
    if (state.status === 1) {
      return { planHash, nextChargeAt: state.nextChargeAt, retryAt: state.retryAt, status: state.status };
    }
  }
  throw new Error(`No active plans found for ${user}`);
}

async function attemptCharge(manager: SubscriptionManager, user: string, planHash: string): Promise<ChargeResult> {
  try {
    const tx = await manager['charge(address,bytes32)'](user, planHash);
    await tx.wait();
    return { user, planHash, status: 'charged' };
  } catch (error) {
    if (isCustomError(error, 'NotDue')) {
      return { user, planHash, status: 'skipped', reason: 'not-due' };
    }
    if (
      isCustomError(error, 'InsufficientBalance') ||
      isCustomError(error, 'PlanInactive') ||
      isCustomError(error, 'PlanNotFound')
    ) {
      const retryTx = await manager.markFailedCharge(user, planHash);
      await retryTx.wait();
      return {
        user,
        planHash,
        status: 'retry-scheduled',
        reason: isCustomError(error, 'InsufficientBalance') ? 'insufficient-balance' : 'plan-inactive',
      };
    }
    throw error;
  }
}

async function main() {
  const configPath = process.argv[2] ?? 'scripts/billing-config.json';
  const config = await loadConfig(configPath);

  const manager = await loadSubscriptionManager(config.subscriptionManager);
  const now = BigInt(Math.floor(Date.now() / 1000));

  const results: ChargeResult[] = [];

  for (const user of config.subscribers) {
    try {
      const { planHash, nextChargeAt, retryAt } = await collectActivePlans(manager, user);
      const dueAt = retryAt !== 0n ? retryAt : nextChargeAt;
      if (dueAt > now) {
        results.push({ user, planHash, status: 'skipped', reason: 'not-due' });
        continue;
      }

      const outcome = await attemptCharge(manager, user, planHash);
      results.push(outcome);
    } catch (error) {
      const reason = (error as Error).message ?? String(error);
      results.push({ user, planHash: ethers.ZeroHash, status: 'skipped', reason });
    }
  }

  console.table(
    results.map((item) => ({
      user: item.user,
      plan: item.planHash,
      status: item.status,
      reason: item.reason ?? '',
    })),
  );
}

main().catch((error) => {
  console.error('Billing worker failed:', error);
  process.exit(1);
});
