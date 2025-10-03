import { ethers } from 'hardhat';
import type { ContestFactory, ContestEscrow, TestToken } from '../../typechain-types';
import { getDemoAddresses } from '../config/addresses';
import { getDemoSigners } from '../utils/signers';
import { log } from '../utils/logging';
import { mintIfNeeded, ensureAllowance } from '../utils/tokens';
import { grantFeatureOwner } from '../utils/core';

async function ensureTestToken(existing?: string): Promise<string> {
  if (existing) {
    return existing;
  }

  log.info('Deploying helper TestToken for contest demo...');
  const TokenFactory = await ethers.getContractFactory('contracts/mocks/TestToken.sol:TestToken');
  const token = (await TokenFactory.deploy('ContestToken', 'CTK', 18, 0)) as TestToken;
  await token.waitForDeployment();
  const address = await token.getAddress();
  log.success(`[token] deployed at ${address}`);
  return address;
}

async function main() {
  const addresses = await getDemoAddresses();
  const { deployer, secondary: manager, tertiary: winner } = await getDemoSigners();

  log.info(`Core address: ${addresses.core}`);
  log.info(`ContestFactory address: ${addresses.contestFactory}`);

  const tokenAddress = await ensureTestToken(addresses.testToken);
  await grantFeatureOwner(addresses.core, await manager.getAddress());

  const factory = (await ethers.getContractAt(
    'ContestFactory',
    addresses.contestFactory,
    manager,
  )) as ContestFactory;
  const token = (await ethers.getContractAt(
    'contracts/mocks/TestToken.sol:TestToken',
    tokenAddress,
  )) as TestToken;

  const tokenPrizeAmount = ethers.parseEther('50');
  const ethPrizeAmount = ethers.parseEther('1');

  await mintIfNeeded(tokenAddress, deployer, await manager.getAddress(), tokenPrizeAmount);
  await ensureAllowance(tokenAddress, manager, addresses.contestFactory, tokenPrizeAmount);

  const prizes: ContestFactory.PrizeInfoStruct[] = [
    {
      prizeType: 0,
      token: tokenAddress,
      amount: tokenPrizeAmount,
      distribution: 0,
      uri: '',
    },
    {
      prizeType: 0,
      token: ethers.ZeroAddress,
      amount: ethPrizeAmount,
      distribution: 0,
      uri: '',
    },
  ];

  log.info('Estimating escrow address...');
  const predictedEscrow = await factory.connect(manager).createContest.staticCall(prizes, '0x', { value: ethPrizeAmount });

  log.info('Creating contest and funding escrow...');
  const createTx = await factory.connect(manager).createContest(prizes, '0x', { value: ethPrizeAmount });
  await createTx.wait();
  log.success(`Contest created. Escrow: ${predictedEscrow}`);

  const escrow = (await ethers.getContractAt('ContestEscrow', predictedEscrow)) as ContestEscrow;
  const winners = [await winner.getAddress(), await manager.getAddress()];
  const winnerTokenBalanceBefore = await token.balanceOf(winners[0]);
  const winnerEthBalanceBefore = await ethers.provider.getBalance(winners[1]);

  log.info('Finalizing contest and distributing prizes...');
  const finalizeTx = await escrow.connect(manager).finalize(winners, 0);
  await finalizeTx.wait();
  log.success('Contest finalized.');

  const winnerTokenDelta = (await token.balanceOf(winners[0])) - winnerTokenBalanceBefore;
  const winnerEthDelta = (await ethers.provider.getBalance(winners[1])) - winnerEthBalanceBefore;
  log.info(`Winner 1 received ${ethers.formatEther(winnerTokenDelta)} tokens.`);
  log.info(`Winner 2 received ${ethers.formatEther(winnerEthDelta)} ETH.`);

  log.success('Contest scenario finished successfully.');
}

main().catch((error) => {
  const message = error instanceof Error ? error.message : String(error);
  log.error(`Contest scenario failed: ${message}`);
  process.exitCode = 1;
});
