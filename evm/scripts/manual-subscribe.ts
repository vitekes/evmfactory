import { ethers } from 'hardhat';
import type { Signer } from 'ethers';

async function sendTransaction(signer: Signer, to: string, txRequest: ethers.TransactionRequest) {
  const provider = signer.provider;
  if (!provider) throw new Error('Signer is missing provider');

  const from = await signer.getAddress();
  const normalizedTo = normalizeHexAddress(to);
  const tx = {
    from,
    to: normalizedTo,
    data: txRequest.data ? ethers.hexlify(txRequest.data) : undefined,
    value: txRequest.value !== undefined ? ethers.toBeHex(txRequest.value) : undefined,
    gas: txRequest.gasLimit !== undefined ? ethers.toBeHex(txRequest.gasLimit) : undefined,
  };

  const hash = await provider.send('eth_sendTransaction', [tx]);
  await waitForReceipt(provider, hash);
  return hash;
}

function normalizeHexAddress(address: string): string {
  if (!address.startsWith('0x')) {
    throw new Error(`Address must be hex string, got: ${address}`);
  }
  const body = address.slice(2);
  if (body.length % 2 === 1) {
    return `0x0${body}`;
  }
  return address;
}

async function waitForReceipt(provider: ethers.Provider, hash: string) {
  // Hardhat's ethers provider stub doesn't implement waitForTransaction.
  for (;;) {
    const receipt = await provider.send('eth_getTransactionReceipt', [hash]);
    if (receipt) {
      return receipt;
    }
    await new Promise((resolve) => setTimeout(resolve, 200));
  }
}

async function ensureAuthorRole(coreAddress: string, admin: Signer, merchant: string) {
  const core = await ethers.getContractAt('CoreSystem', coreAddress, admin);
  const authorRole = ethers.id('AUTHOR_ROLE');
  const hasRole = await core.hasRole(authorRole, merchant);

  if (!hasRole) {
    const txRequest = await core.getFunction('grantRole').populateTransaction(authorRole, merchant);
    const txHash = await sendTransaction(admin, coreAddress, txRequest);
    console.log('Granted AUTHOR_ROLE to merchant:', merchant, txHash);
  } else {
    console.log('Merchant already has AUTHOR_ROLE');
  }
}

async function authorizeSubscriptionModule(
  gatewayAddress: string,
  admin: Signer,
  moduleAddress: string,
) {
  const gateway = await ethers.getContractAt('PaymentGateway', gatewayAddress, admin);
  const moduleId = ethers.id('SubscriptionManager');
  const txRequest = await gateway
    .getFunction('setModuleAuthorization')
    .populateTransaction(moduleId, moduleAddress, true);
  const txHash = await sendTransaction(admin, gatewayAddress, txRequest);
  console.log('SubscriptionManager authorized in PaymentGateway:', txHash);
}

async function main() {
  const [adminSigner, merchantSigner, subscriberSigner] = await ethers.getSigners();
  const merchant = await merchantSigner.getAddress();
  const subscriber = await subscriberSigner.getAddress();

  const addresses = {
    core: '0x5FbDB2315678afecb367f032d93F642f64180aa3',
    paymentGateway: '0x2279B70a67DB372996a5FaB50D91eAA73d2eBe6',
    planManager: '0x9A9f2CCfdE556A7E9Ff0848998Aa4a0CFD8863AE',
    subscriptionManager: '0x9A676e781A523b5d0C0e43731313A708CB607508',
  };

  await ensureAuthorRole(addresses.core, adminSigner, merchant);
  await authorizeSubscriptionModule(addresses.paymentGateway, adminSigner, addresses.subscriptionManager);

  const planManager = await ethers.getContractAt('PlanManager', addresses.planManager, merchantSigner);
  const subscriptionManagerMerchant = await ethers.getContractAt(
    'SubscriptionManager',
    addresses.subscriptionManager,
    merchantSigner,
  );
  const subscriptionManagerSubscriber = subscriptionManagerMerchant.connect(subscriberSigner);

  const network = await ethers.provider.getNetwork();
  const expiry = BigInt(Math.floor(Date.now() / 1000) + 3600);

  const plan = {
    chainIds: [network.chainId],
    price: ethers.parseEther('0.01'),
    period: 30n * 24n * 60n * 60n,
    token: ethers.ZeroAddress,
    merchant,
    salt: 12345n,
    expiry,
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

  const planHash = await subscriptionManagerMerchant.hashPlan(plan);
  console.log('Plan hash:', planHash);

  const signature = await merchantSigner.signTypedData(domain, types, plan);
  console.log('Plan signature:', signature);

  let storedPlan: Awaited<ReturnType<typeof planManager.getPlan>> | null;
  try {
    storedPlan = await planManager.getPlan(planHash);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (message.includes('PlanNotFound')) {
      storedPlan = null;
    } else {
      throw error;
    }
  }

  if (!storedPlan || storedPlan.merchant === ethers.ZeroAddress) {
    console.log('Plan not found, creating...');
    const txCreateRequest = await planManager
      .getFunction('createPlan')
      .populateTransaction(plan, signature, 'https://example.com/metadata');
    const txHash = await sendTransaction(merchantSigner, addresses.planManager, txCreateRequest);
    console.log('Plan created:', txHash);
  } else {
    console.log('Plan already registered for merchant:', storedPlan.merchant);
  }

  console.log('Subscribing user...');
  const subscribeRequest = await subscriptionManagerSubscriber
    .getFunction('subscribe')
    .populateTransaction(plan, signature, '0x', { value: plan.price });
  const subscribeHash = await sendTransaction(subscriberSigner, addresses.subscriptionManager, subscribeRequest);
  console.log('Subscription tx:', subscribeHash);

  const activePlan = await subscriptionManagerSubscriber.getActivePlan(subscriber, merchant);
  console.log('Active plan hash for user:', activePlan);
}

main().catch((error) => {
  console.error('Script failed:', error);
  process.exitCode = 1;
});
