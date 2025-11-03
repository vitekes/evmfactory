import { ethers } from 'hardhat';
import type { PlanManager, SubscriptionManager, TestToken, PaymentGateway } from '../../typechain-types';
import { getDemoAddresses } from '../config/addresses';
import { getDemoSigners } from '../utils/signers';
import { log } from '../utils/logging';
import { ensureDemoToken, ensureAllowance, mintIfNeeded } from '../utils/tokens';
import { authorizeModule } from '../utils/gateway';
import { grantAuthorRole, grantAutomationRole } from '../utils/core';
import {
  chargeNextCycle,
  ensurePlanRegistered,
  fastForward,
  signPlan,
  subscribeWithLogging,
} from '../utils/subscriptions';

async function main() {
  const addresses = await getDemoAddresses();
  const { deployer, secondary: merchant, tertiary: subscriber } = await getDemoSigners();

  const { address: tokenAddress } = await ensureDemoToken(addresses.testToken, {
    name: 'SubToken',
    symbol: 'SUB',
  });

  const subscriptionManager = (await ethers.getContractAt(
    'SubscriptionManager',
    addresses.subscriptionManager
  )) as SubscriptionManager;
  const planManager = (await ethers.getContractAt('PlanManager', addresses.planManager)) as PlanManager;
  const gateway = (await ethers.getContractAt('PaymentGateway', addresses.paymentGateway)) as PaymentGateway;
  const token = (await ethers.getContractAt(
    'contracts/mocks/TestToken.sol:TestToken',
    tokenAddress
  )) as TestToken;

  const planPrice = ethers.parseEther('25');
  const planPeriodSeconds = BigInt(30 * 24 * 60 * 60);

  log.info('Authorizing SubscriptionManager in PaymentGateway...');
  await authorizeModule(
    addresses.paymentGateway,
    ethers.id('SubscriptionManager'),
    await subscriptionManager.getAddress(),
    deployer
  );

  await mintIfNeeded(tokenAddress, deployer, await subscriber.getAddress(), planPrice * 3n);
  await ensureAllowance(tokenAddress, subscriber, addresses.paymentGateway, planPrice * 3n);

  log.info('Ensuring merchant and automation roles...');
  await grantAuthorRole(addresses.core, await merchant.getAddress());
  await grantAutomationRole(addresses.core, await deployer.getAddress());

  const network = await ethers.provider.getNetwork();
  const plan: SubscriptionManager.PlanStruct = {
    chainIds: [network.chainId],
    price: planPrice,
    period: planPeriodSeconds,
    token: tokenAddress,
    merchant: await merchant.getAddress(),
    salt: 1n,
    expiry: BigInt(Math.floor(Date.now() / 1000) + 3600),
  };

  const signature = await signPlan(merchant, addresses.subscriptionManager, plan);
  const planHash = await ensurePlanRegistered(planManager, subscriptionManager, merchant, plan, signature, 'demo://tier');

  const subscriberBalanceBefore = await token.balanceOf(await subscriber.getAddress());

  const subscribeResult = await subscribeWithLogging(subscriptionManager, subscriber, plan, signature, gateway, '0x');
  const merchantAfterSubscribe = await token.balanceOf(await merchant.getAddress());
  log.info(`Merchant balance after subscribe: ${ethers.formatEther(merchantAfterSubscribe)} tokens.`);
  if (subscribeResult.event) {
    log.info(`Net amount on subscribe: ${ethers.formatEther(subscribeResult.event.netAmount)} tokens.`);
  }

  log.info('Advancing time to next billing period...');
  await fastForward(planPeriodSeconds);

  const chargeResult = await chargeNextCycle(
    subscriptionManager,
    deployer,
    await subscriber.getAddress(),
    planHash,
    gateway
  );

  if (chargeResult.event) {
    log.info(`Net amount on renewal: ${ethers.formatEther(chargeResult.event.netAmount)} tokens.`);
  }

  const merchantBalance = await token.balanceOf(await merchant.getAddress());
  const subscriberBalance = await token.balanceOf(await subscriber.getAddress());
  const totalDebited = subscriberBalanceBefore - subscriberBalance;

  log.info(`Merchant balance after renewal: ${ethers.formatEther(merchantBalance)} tokens.`);
  log.info(`Subscriber balance after renewal: ${ethers.formatEther(subscriberBalance)} tokens.`);
  log.info(`Total debited from subscriber: ${ethers.formatEther(totalDebited)} tokens.`);

  if (!subscribeResult.event || !chargeResult.event) {
    log.warn(
      'One of the payment events was not captured. Check processor configuration if values look unexpected.'
    );
  }

  log.success('Subscription scenario finished successfully.');
}

main().catch((error) => {
  const message = error instanceof Error ? error.message : String(error);
  log.error(`Subscription scenario failed: ${message}`);
  process.exitCode = 1;
});
