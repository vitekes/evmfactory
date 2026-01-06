import { ethers } from '../../hardhat-connection';
import type { PaymentGateway } from '../../typechain-types';
import { getDemoAddresses } from '../config/addresses';
import { getDemoSigners } from '../utils/signers';
import { log } from '../utils/logging';
import { ensureDemoToken, mintIfNeeded, ensureAllowance } from '../utils/tokens';
import { authorizeModule } from '../utils/gateway';
import { logPaymentProcessed, parsePaymentProcessed } from '../utils/payments';

async function main() {
  const addresses = await getDemoAddresses();
  const { deployer, secondary: moduleCaller, tertiary: payer } = await getDemoSigners();

  const { address: tokenAddress } = await ensureDemoToken(addresses.testToken, {
    name: 'DemoToken',
    symbol: 'DEMO',
  });

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
  const erc20Event = parsePaymentProcessed(erc20Receipt, gateway);
  logPaymentProcessed(erc20Event);

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
  const nativeEvent = parsePaymentProcessed(nativeReceipt, gateway);
  logPaymentProcessed(nativeEvent);

  log.success('Payment scenario finished successfully.');
}

main().catch((error) => {
  log.error(`Payment scenario failed: ${error instanceof Error ? error.message : String(error)}`);
  process.exitCode = 1;
});
