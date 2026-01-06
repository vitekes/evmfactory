import { ethers } from '../../hardhat-connection';
import type { Marketplace, TestToken, CoreSystem, PaymentGateway } from '../../typechain-types';
import { getDemoAddresses } from '../config/addresses';
import { getDemoSigners } from '../utils/signers';
import { log } from '../utils/logging';
import { mintIfNeeded, ensureAllowance } from '../utils/tokens';

async function ensureTestToken(existing?: string): Promise<string> {
  if (existing) {
    return existing;
  }

  log.info('Deploying helper TestToken for marketplace demo...');
  const TokenFactory = await ethers.getContractFactory('contracts/mocks/TestToken.sol:TestToken');
  const token = (await TokenFactory.deploy('MarketToken', 'MKT', 18, 0)) as TestToken;
  await token.waitForDeployment();
  const address = await token.getAddress();
  log.success(`[token] deployed at ${address}`);
  return address;
}

async function ensureMarketplace(
  addresses: Awaited<ReturnType<typeof getDemoAddresses>>,
  deployer: Awaited<ReturnType<typeof getDemoSigners>>[number],
): Promise<Marketplace> {
  const moduleId = ethers.id('Marketplace');
  const core = (await ethers.getContractAt('CoreSystem', addresses.core, deployer)) as CoreSystem;
  const gateway = (await ethers.getContractAt('PaymentGateway', addresses.paymentGateway, deployer)) as PaymentGateway;

  if (addresses.marketplace) {
    log.info(`Using existing Marketplace at ${addresses.marketplace}`);
    return (await ethers.getContractAt('Marketplace', addresses.marketplace, deployer)) as Marketplace;
  }

  log.warn('Marketplace address not provided. Deploying a demo instance...');
  const Factory = await ethers.getContractFactory('Marketplace', deployer);
  const marketplace = (await Factory.deploy(addresses.core, addresses.paymentGateway, moduleId)) as Marketplace;
  await marketplace.waitForDeployment();
  const marketplaceAddress = await marketplace.getAddress();
  log.success(`[marketplace] deployed at ${marketplaceAddress}`);

  const featureOwnerRole = await core.FEATURE_OWNER_ROLE();
  const deployerAddress = await deployer.getAddress();
  const deployerHadRole = await core.hasRole(featureOwnerRole, deployerAddress);
  const moduleHadRole = await core.hasRole(featureOwnerRole, marketplaceAddress);

  try {
    if (!deployerHadRole) {
      await (await core.grantRole(featureOwnerRole, deployerAddress)).wait();
      log.info('Granted FEATURE_OWNER_ROLE to deployer');
    }
    if (!moduleHadRole) {
      await (await core.grantRole(featureOwnerRole, marketplaceAddress)).wait();
      log.info('Granted FEATURE_OWNER_ROLE to Marketplace');
    }
  } catch (error) {
    log.warn(`Unable to adjust feature owner roles automatically: ${String(error)}`);
  }

  try {
    await (await core.registerFeature(moduleId, marketplaceAddress, 0)).wait();
  } catch (error) {
    log.warn(`registerFeature skipped: ${String(error)}`);
  }

  try {
    await (await core.setService(moduleId, 'PaymentGateway', addresses.paymentGateway)).wait();
  } catch (error) {
    log.warn(`setService skipped: ${String(error)}`);
  }

  try {
    await (await gateway.setModuleAuthorization(moduleId, marketplaceAddress, true)).wait();
  } catch (error) {
    log.warn(`setModuleAuthorization skipped: ${String(error)}`);
  }

  if (!deployerHadRole) {
    try {
      await (await core.revokeRole(featureOwnerRole, deployerAddress)).wait();
      log.info('Revoked FEATURE_OWNER_ROLE from deployer');
    } catch (error) {
      log.warn(`revokeRole skipped: ${String(error)}`);
    }
  }

  return marketplace;
}

async function main() {
  const addresses = await getDemoAddresses();
  const { deployer, secondary: seller, tertiary: buyer } = await getDemoSigners();

  const tokenAddress = await ensureTestToken(addresses.testToken);
  const marketplace = await ensureMarketplace(addresses, deployer);
  const token = (await ethers.getContractAt('contracts/mocks/TestToken.sol:TestToken', tokenAddress)) as TestToken;

  const price = ethers.parseEther('25');
  await mintIfNeeded(tokenAddress, deployer, await buyer.getAddress(), price * 2n);
  await ensureAllowance(tokenAddress, buyer, addresses.paymentGateway, price * 2n);

  log.info('Preparing listing signature...');
  const listing = {
    chainIds: [(await ethers.provider.getNetwork()).chainId],
    token: tokenAddress,
    price,
    sku: ethers.keccak256(ethers.toUtf8Bytes('DEMO-MARKET-SKU')),
    seller: await seller.getAddress(),
    salt: 1n,
    expiry: BigInt(Math.floor(Date.now() / 1000) + 3600),
    discountPercent: 0,
  } as const;

  const domain = {
    chainId: (await ethers.provider.getNetwork()).chainId,
    verifyingContract: await marketplace.getAddress(),
  } as const;

  const types = {
    Listing: [
      { name: 'chainIds', type: 'uint256[]' },
      { name: 'token', type: 'address' },
      { name: 'price', type: 'uint256' },
      { name: 'sku', type: 'bytes32' },
      { name: 'seller', type: 'address' },
      { name: 'salt', type: 'uint256' },
      { name: 'expiry', type: 'uint64' },
      { name: 'discountPercent', type: 'uint16' },
    ],
  } as const;

  const signature = await seller.signTypedData(domain, types, listing);

  log.info('Buying listing via Marketplace (ERC-20)...');
  await (await marketplace.connect(buyer).buy(listing, signature, tokenAddress, 0)).wait();

  const sellerBalance = await token.balanceOf(await seller.getAddress());
  log.success(`Seller received ${ethers.formatEther(sellerBalance)} tokens for SKU demo.`);

  log.info('Attempting to repurchase the same listing (should fail)...');
  await marketplace
    .connect(deployer)
    .buy(listing, signature, tokenAddress, 0)
    .then(() => log.error('Unexpected success!'))
    .catch((error) => {
      const message = error instanceof Error ? error.message : String(error);
      log.info(`Second purchase reverted as expected: ${message}`);
    });

  log.success('Marketplace scenario finished successfully.');
}

main().catch((error) => {
  const message = error instanceof Error ? error.message : String(error);
  log.error(`Marketplace scenario failed: ${message}`);
  process.exitCode = 1;
});
