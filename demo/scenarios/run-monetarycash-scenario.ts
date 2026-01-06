import { ethers } from '../../hardhat-connection';
import { getDemoAddresses } from '../config/addresses';
import { ensureAllowance, ensureDemoToken, mintIfNeeded } from '../utils/tokens';
import { log } from '../utils/logging';
import type { MonetaryCash } from '../../typechain-types';

async function signActivation(
  monetaryCash: MonetaryCash,
  signer: Awaited<ReturnType<typeof ethers.getSigners>>[number],
  cashId: bigint,
  recipient: string,
  deadline: bigint
) {
  const { chainId } = await ethers.provider.getNetwork();
  const domain = {
    name: 'MonetaryCash',
    version: '1',
    chainId,
    verifyingContract: await monetaryCash.getAddress(),
  } as const;

  const types = {
    ActivateCash: [
      { name: 'cashId', type: 'uint256' },
      { name: 'recipient', type: 'address' },
      { name: 'deadline', type: 'uint256' },
    ],
  } as const;

  const message = { cashId, recipient, deadline } as const;
  return signer.signTypedData(domain, types, message);
}

async function main() {
  const [deployer, recipient, caller] = await ethers.getSigners();
  const addresses = await getDemoAddresses();

  if (!addresses.monetaryCash) {
    throw new Error('MonetaryCash module address is missing');
  }

  const monetaryCash = (await ethers.getContractAt(
    'contracts/modules/monetary/MonetaryCash.sol:MonetaryCash',
    addresses.monetaryCash
  )) as MonetaryCash;

  const backendSignerAddress = await monetaryCash.backendSigner();
  const backendSigner =
    backendSignerAddress.toLowerCase() === deployer.address.toLowerCase()
      ? deployer
      : backendSignerAddress.toLowerCase() === recipient.address.toLowerCase()
        ? recipient
        : backendSignerAddress.toLowerCase() === caller.address.toLowerCase()
          ? caller
          : deployer;

  if (backendSigner.address.toLowerCase() !== backendSignerAddress.toLowerCase()) {
    log.warn(`Backend signer ${backendSignerAddress} not found in local signers; using ${backendSigner.address}.`);
  }

  const amount = ethers.parseEther('5');
  const { address: tokenAddress } = await ensureDemoToken(addresses.testToken, {
    name: 'CashDemoToken',
    symbol: 'CASH',
  });

  await mintIfNeeded(tokenAddress, deployer, deployer.address, amount);
  await ensureAllowance(tokenAddress, deployer, await monetaryCash.getAddress(), amount);

  const latest = await ethers.provider.getBlock('latest');
  if (!latest) {
    throw new Error('block not found');
  }
  const expiresAt = BigInt(latest.timestamp + 3600);
  log.info('Creating ERC-20 cash...');
  await (await monetaryCash.connect(deployer).createCash(tokenAddress, amount, expiresAt)).wait();
  log.success('MonetaryCashCreated (ERC-20).');

  const deadline = BigInt(latest.timestamp + 600);
  const signature = await signActivation(monetaryCash, backendSigner, 1n, recipient.address, deadline);
  log.info('Activating ERC-20 cash...');
  await (await monetaryCash.connect(caller).activateCashWithSig(1, recipient.address, deadline, signature)).wait();
  log.success('MonetaryCashActivated (ERC-20).');

  const token = await ethers.getContractAt('contracts/mocks/TestToken.sol:TestToken', tokenAddress);
  const recipientBalance = await token.balanceOf(recipient.address);
  log.success(`Recipient token balance: ${ethers.formatUnits(recipientBalance, 18)} CASH`);

  log.info('Creating native cash...');
  await (await monetaryCash.connect(deployer).createCash(ethers.ZeroAddress, amount, 0, { value: amount })).wait();
  log.success('MonetaryCashCreated (native).');

  const nativeDeadline = BigInt(latest.timestamp + 600);
  const nativeSignature = await signActivation(monetaryCash, backendSigner, 2n, recipient.address, nativeDeadline);
  log.info('Activating native cash...');
  await (
    await monetaryCash.connect(caller).activateCashWithSig(2, recipient.address, nativeDeadline, nativeSignature)
  ).wait();
  log.success('MonetaryCashActivated (native).');

  const recipientEth = await ethers.provider.getBalance(recipient.address);
  log.success(`Recipient native balance: ${ethers.formatEther(recipientEth)} ETH`);
  log.success('MonetaryCash scenario finished successfully.');
}

main().catch((error) => {
  log.error(`Scenario failed: ${error instanceof Error ? error.message : String(error)}`);
  process.exit(1);
});
