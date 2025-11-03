import { ethers } from 'hardhat';
import type { Donate, CoreSystem, PaymentGateway, PaymentOrchestrator, TestToken } from '../../typechain-types';
import { getDemoAddresses } from '../config/addresses';
import { getDemoSigners } from '../utils/signers';
import { log } from '../utils/logging';
import { ensureDemoToken, mintIfNeeded, ensureAllowance } from '../utils/tokens';
import { configureDonationProcessors, submitDonation } from '../utils/donations';

async function ensureDonateInstance(
  addresses: Awaited<ReturnType<typeof getDemoAddresses>>,
  deployer: Awaited<ReturnType<typeof getDemoSigners>>['deployer'],
): Promise<Donate> {
  const moduleId = ethers.id('Donate');
  const core = (await ethers.getContractAt('CoreSystem', addresses.core, deployer)) as CoreSystem;
  const gateway = (await ethers.getContractAt('PaymentGateway', addresses.paymentGateway, deployer)) as PaymentGateway;

  if (addresses.donate) {
    log.info(`Using existing Donate module at ${addresses.donate}`);
    return (await ethers.getContractAt('Donate', addresses.donate, deployer)) as Donate;
  }

  log.warn('Donate address not provided. Deploying a demo instance...');
  const DonateFactory = await ethers.getContractFactory('Donate', deployer);
  const donate = (await DonateFactory.deploy(addresses.core, addresses.paymentGateway, moduleId)) as Donate;
  await donate.waitForDeployment();
  const donateAddress = await donate.getAddress();
  log.success(`[donate] deployed at ${donateAddress}`);

  const featureOwnerRole = await core.FEATURE_OWNER_ROLE();
  const deployerAddress = await deployer.getAddress();
  const deployerHadRole = await core.hasRole(featureOwnerRole, deployerAddress);
  const moduleHadRole = await core.hasRole(featureOwnerRole, donateAddress);

  try {
    if (!deployerHadRole) {
      await (await core.grantRole(featureOwnerRole, deployerAddress)).wait();
      log.info('Granted FEATURE_OWNER_ROLE to deployer');
    }
    if (!moduleHadRole) {
      await (await core.grantRole(featureOwnerRole, donateAddress)).wait();
      log.info('Granted FEATURE_OWNER_ROLE to Donate');
    }
  } catch (error) {
    log.warn(`Unable to adjust feature owner roles automatically: ${String(error)}`);
  }

  try {
    await (await core.registerFeature(moduleId, donateAddress, 0)).wait();
  } catch (error) {
    log.warn(`registerFeature skipped: ${String(error)}`);
  }

  try {
    await (await core.setService(moduleId, 'PaymentGateway', addresses.paymentGateway)).wait();
  } catch (error) {
    log.warn(`setService skipped: ${String(error)}`);
  }

  try {
    await (await gateway.setModuleAuthorization(moduleId, donateAddress, true)).wait();
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

  return donate;
}

async function main() {
  const addresses = await getDemoAddresses();
  const { deployer, secondary: donor, tertiary: beneficiary } = await getDemoSigners();

  const donate = await ensureDonateInstance(addresses, deployer);
  const moduleId = ethers.id('Donate');
  const orchestrator = (await ethers.getContractAt(
    'PaymentOrchestrator',
    addresses.paymentOrchestrator,
    deployer,
  )) as PaymentOrchestrator;

  const { address: tokenAddress } = await ensureDemoToken(addresses.testToken, {
    name: 'DonateDemoToken',
    symbol: 'DDN',
  });
  const testToken = (await ethers.getContractAt(
    'contracts/mocks/TestToken.sol:TestToken',
    tokenAddress,
    deployer,
  )) as TestToken;

  await configureDonationProcessors(orchestrator, moduleId, [tokenAddress], await deployer.getAddress(), 250);

  const donationAmount = ethers.parseUnits('50', 18);
  await mintIfNeeded(tokenAddress, deployer, await donor.getAddress(), donationAmount * 2n);
  await ensureAllowance(tokenAddress, donor, addresses.paymentGateway, donationAmount * 2n);

  const metadata = ethers.keccak256(ethers.toUtf8Bytes('DONATE:DEMO'));
  const event = await submitDonation(
    donate,
    donor,
    await beneficiary.getAddress(),
    tokenAddress,
    donationAmount,
    metadata
  );

  const beneficiaryBalance = await testToken.balanceOf(await beneficiary.getAddress());
  const deployerBalance = await testToken.balanceOf(await deployer.getAddress());
  log.info(`Beneficiary balance: ${ethers.formatUnits(beneficiaryBalance, 18)} tokens.`);
  log.info(`Platform fee balance (deployer): ${ethers.formatUnits(deployerBalance, 18)} tokens.`);
  log.success('Donate scenario finished successfully.');
}

main().catch((error) => {
  const message = error instanceof Error ? error.message : String(error);
  log.error(`Donate scenario failed: ${message}`);
  process.exitCode = 1;
});
