import { ethers } from 'hardhat';
import type { SubscriptionManager, TestToken, PaymentGateway } from '../../typechain-types';
import { getDemoAddresses } from '../config/addresses';
import { getDemoSigners } from '../utils/signers';
import { log } from '../utils/logging';
import { mintIfNeeded, ensureAllowance } from '../utils/tokens';
import { authorizeModule } from '../utils/gateway';

async function ensureTestToken(existing?: string): Promise<string> {
  if (existing) {
    return existing;
  }

  log.info('Deploying helper TestToken for subscription demo...');
  const TokenFactory = await ethers.getContractFactory('contracts/mocks/TestToken.sol:TestToken');
  const token = (await TokenFactory.deploy('SubToken', 'SUB', 18, 0)) as TestToken;
  await token.waitForDeployment();
  const tokenAddress = await token.getAddress();
  log.success(`[token] deployed at ${tokenAddress}`);
  return tokenAddress;
}

async function parsePaymentEvent(receipt: Awaited<ReturnType<typeof ethers.ContractTransactionResponse.prototype.wait>>, gateway: PaymentGateway) {
  if (!receipt) return;
  const parsed = receipt.logs
    .map((logEntry) => {
      try {
        return gateway.interface.parseLog(logEntry);
      } catch {
        return null;
      }
    })
    .find((entry) => entry?.name === 'PaymentProcessed');

  if (parsed) {
    const net = parsed.args.netAmount as bigint;
    const token = parsed.args.token as string;
    log.info(`PaymentProcessed => ${token === ethers.ZeroAddress ? ethers.formatEther(net) + ' ETH' : ethers.formatEther(net) + ' tokens'}`);
  }
}

async function main() {
  const addresses = await getDemoAddresses();
  const { deployer, secondary: merchant, tertiary: subscriber } = await getDemoSigners();

  const tokenAddress = await ensureTestToken(addresses.testToken);

  const subscriptionManager = (await ethers.getContractAt(
    'SubscriptionManager',
    addresses.subscriptionManager,
  )) as SubscriptionManager;
  const paymentGatewayAddress = addresses.paymentGateway;

  const planPrice = ethers.parseEther('25');
  const planPeriodSeconds = BigInt(7 * 24 * 60 * 60);

  log.info('Authorizing SubscriptionManager in PaymentGateway...');
  await authorizeModule(
    paymentGatewayAddress,
    ethers.id('SubscriptionManager'),
    await subscriptionManager.getAddress(),
    deployer,
  );

  await mintIfNeeded(tokenAddress, deployer, await subscriber.getAddress(), planPrice * 3n);
  await ensureAllowance(tokenAddress, subscriber, paymentGatewayAddress, planPrice * 3n);

  const token = (await ethers.getContractAt(
    'contracts/mocks/TestToken.sol:TestToken',
    tokenAddress,
  )) as TestToken;

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

  const domain = {
    chainId: network.chainId,
    verifyingContract: addresses.subscriptionManager,
  } as const;

  const types = {
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

  log.info('Signing subscription plan...');
  const signature = await merchant.signTypedData(domain, types, plan);

  log.info('Subscribing...');
  const subscribeTx = await subscriptionManager.connect(subscriber).subscribe(plan, signature, '0x');
  const subscribeReceipt = await subscribeTx.wait();
  log.success('Subscription created.');

  const gateway = (await ethers.getContractAt('PaymentGateway', paymentGatewayAddress)) as PaymentGateway;
  await parsePaymentEvent(subscribeReceipt, gateway);

  const merchantAfterSubscribe = await token.balanceOf(await merchant.getAddress());
  log.info(`Merchant balance after subscribe: ${ethers.formatEther(merchantAfterSubscribe)} tokens.`);

  log.info('Advancing time and charging again...');
  await ethers.provider.send('evm_increaseTime', [Number(planPeriodSeconds)]);
  await ethers.provider.send('evm_mine', []);

  const chargeTx = await subscriptionManager.connect(deployer).charge(await subscriber.getAddress());
  const chargeReceipt = await chargeTx.wait();
  log.success('Recurring charge executed.');
  await parsePaymentEvent(chargeReceipt, gateway);

  const merchantBalance = await token.balanceOf(await merchant.getAddress());
  const subscriberBalance = await token.balanceOf(await subscriber.getAddress());
  log.info(`Merchant balance after charge: ${ethers.formatEther(merchantBalance)} tokens.`);
  log.info(`Subscriber balance: ${ethers.formatEther(subscriberBalance)} tokens.`);
  log.warn('Note: current processor chain does not forward funds to the merchant automatically. This demo only verifies successful charges.');

  log.success('Subscription scenario finished successfully.');
}

main().catch((error) => {
  const message = error instanceof Error ? error.message : String(error);
  log.error(`Subscription scenario failed: ${message}`);
  process.exitCode = 1;
});
