import { ethers } from 'hardhat';
import type { ContestFactory, ContestEscrow, CoreSystem, TestToken } from '../../typechain-types';
import { getDemoAddresses } from '../config/addresses';
import { getDemoSigners } from '../utils/signers';
import { log } from '../utils/logging';
import { mintIfNeeded, ensureAllowance } from '../utils/tokens';

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
  const { deployer: creator, secondary: firstWinner, tertiary: secondWinner } = await getDemoSigners();

  log.info(`Core address: ${addresses.core}`);
  log.info(`ContestFactory address: ${addresses.contestFactory}`);

  const tokenAddress = await ensureTestToken(addresses.testToken);

  const core = (await ethers.getContractAt('CoreSystem', addresses.core, creator)) as CoreSystem;

  const featureOwnerRole = await core.FEATURE_OWNER_ROLE();
  const creatorAddress = await creator.getAddress();
  const hasCreatorRole = await core.hasRole(featureOwnerRole, creatorAddress);
  log.info(`Creator has feature owner role: ${hasCreatorRole}`);
  if (!hasCreatorRole) {
    await (await core.grantRole(featureOwnerRole, creatorAddress)).wait();
    log.info('Granted feature owner role to creator');
  }

  const contestFactoryAddress = addresses.contestFactory;
  const hasFactoryRole = await core.hasRole(featureOwnerRole, contestFactoryAddress);
  log.info(`ContestFactory has feature owner role: ${hasFactoryRole}`);
  if (!hasFactoryRole) {
    await (await core.grantRole(featureOwnerRole, contestFactoryAddress)).wait();
    log.info('Granted feature owner role to ContestFactory');
  }

  const factory = (await ethers.getContractAt('ContestFactory', addresses.contestFactory, creator)) as ContestFactory;
  const token = (await ethers.getContractAt('contracts/mocks/TestToken.sol:TestToken', tokenAddress)) as TestToken;

  const tokenPrizeAmount = ethers.parseEther('50');
  const ethPrizeAmount = ethers.parseEther('1');

  await mintIfNeeded(tokenAddress, creator, await creator.getAddress(), tokenPrizeAmount);
  await ensureAllowance(tokenAddress, creator, addresses.contestFactory, tokenPrizeAmount);

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

  log.info('Creating contest and funding escrow...');
  const createTx = await factory.connect(creator).createContest(prizes, '0x', { value: ethPrizeAmount });
  const createReceipt = await createTx.wait();

  const contestCreated = createReceipt?.logs
    .map((logEntry) => {
      try {
        return factory.interface.parseLog(logEntry);
      } catch {
        return null;
      }
    })
    .find((parsed) => parsed?.name === 'ContestCreated');

  if (!contestCreated) {
    throw new Error('ContestCreated event not emitted');
  }

  const contestId = contestCreated.args.contestId as bigint;
  const instanceId = ethers.zeroPadValue(ethers.toBeHex(contestId), 32);

  const [escrowAddress] = await core.connect(creator).getFeature(instanceId);
  log.success(`Contest created. Escrow: ${escrowAddress}`);

  const escrow = (await ethers.getContractAt('ContestEscrow', escrowAddress)) as ContestEscrow;
  const winners = [await firstWinner.getAddress(), await secondWinner.getAddress()];
  const winnerTokenBalanceBefore = await token.balanceOf(winners[0]);
  const winnerEthBalanceBefore = await ethers.provider.getBalance(winners[1]);

  log.info('Finalizing contest and distributing prizes...');
  const finalizeTx = await escrow.connect(creator).finalize(winners, 0);
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
