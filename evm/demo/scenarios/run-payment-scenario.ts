import { ethers } from 'hardhat';
import type { PaymentGateway, TestToken } from '../../typechain-types';
import { getDemoAddresses } from '../config/addresses';
import { getDemoSigners } from '../utils/signers';
import { log } from '../utils/logging';
import { mintIfNeeded, ensureAllowance } from '../utils/tokens';
import { authorizeModule } from '../utils/gateway';

async function ensureTestToken(addressesToken: string | undefined) {
  if (addressesToken) {
    return addressesToken;
  }

  log.info('Deploying helper TestToken for demo...');
  const TokenFactory = await ethers.getContractFactory('contracts/mocks/TestToken.sol:TestToken');
  const token = (await TokenFactory.deploy('DemoToken', 'DEMO', 18, 0)) as TestToken;
  await token.waitForDeployment();
  const tokenAddress = await token.getAddress();
  log.success(`TestToken deployed at ${tokenAddress}`);
  return tokenAddress;
}

async function main() {
  const addresses = await getDemoAddresses();
  const { deployer, secondary: moduleCaller, tertiary: payer } = await getDemoSigners();

  const tokenAddress = await ensureTestToken(addresses.testToken);

  const moduleId = ethers.id('PAYMENT_SCENARIO');
  log.info('Authorizing demo module in PaymentGateway...');
  await authorizeModule(addresses.paymentGateway, moduleId, await moduleCaller.getAddress(), deployer);

  const erc20Amount = ethers.parseUnits('100', 18);
  log.info('Ensuring payer has enough demo tokens...');
  await mintIfNeeded(tokenAddress, deployer, await payer.getAddress(), erc20Amount);
  await ensureAllowance(tokenAddress, payer, addresses.paymentGateway, erc20Amount);

  const gateway = (await ethers.getContractAt(
    'PaymentGateway',
    addresses.paymentGateway,
    moduleCaller,
  )) as PaymentGateway;

  log.info('Sending ERC-20 payment through PaymentGateway...');
  const erc20Tx = await gateway.processPayment(moduleId, tokenAddress, await payer.getAddress(), erc20Amount, '0x');
  const erc20Receipt = await erc20Tx.wait();
  const erc20Log = erc20Receipt?.logs
    .map((logEntry) => {
      try {
        return gateway.interface.parseLog(logEntry);
      } catch {
        return null;
      }
    })
    .find((parsed) => parsed?.name === 'PaymentProcessed');
  if (erc20Log) {
    log.success(
      `ERC-20 payment processed successfully. Net amount: ${ethers.formatUnits(erc20Log.args.netAmount, 18)} tokens.`,
    );
  }

  const nativeAmount = ethers.parseEther('0.5');
  log.info('Sending native (ETH) payment through PaymentGateway...');
  const nativeTx = await gateway.processPayment(
    moduleId,
    ethers.ZeroAddress,
    await moduleCaller.getAddress(),
    nativeAmount,
    '0x',
    { value: nativeAmount },
  );
  const nativeReceipt = await nativeTx.wait();
  const nativeLog = nativeReceipt?.logs
    .map((logEntry) => {
      try {
        return gateway.interface.parseLog(logEntry);
      } catch {
        return null;
      }
    })
    .find((parsed) => parsed?.name === 'PaymentProcessed');
  if (nativeLog) {
    log.success(
      `Native payment processed successfully. Net amount: ${ethers.formatEther(nativeLog.args.netAmount)} ETH.`,
    );
  }

  log.success('Payment scenario finished successfully.');
}

main().catch((error) => {
  log.error(`Payment scenario failed: ${error instanceof Error ? error.message : String(error)}`);
  process.exitCode = 1;
});
