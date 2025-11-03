import { ethers } from 'hardhat';
import type { Signer } from 'ethers';
import type { TestToken } from '../../typechain-types';
import { log } from './logging';

export interface EnsureTokenOptions {
  name?: string;
  symbol?: string;
  decimals?: number;
  initialSupply?: bigint;
}

export interface EnsureTokenResult {
  address: string;
  freshlyDeployed: boolean;
}

export async function ensureDemoToken(
  existing: string | undefined,
  options: EnsureTokenOptions = {}
): Promise<EnsureTokenResult> {
  if (existing) {
    return { address: existing, freshlyDeployed: false };
  }

  const name = options.name ?? 'DemoToken';
  const symbol = options.symbol ?? 'DEMO';
  const decimals = options.decimals ?? 18;
  const initialSupply = options.initialSupply ?? 0n;

  log.info(`Deploying helper token ${name}/${symbol}...`);
  const TokenFactory = await ethers.getContractFactory('contracts/mocks/TestToken.sol:TestToken');
  const token = (await TokenFactory.deploy(name, symbol, decimals, initialSupply)) as TestToken;
  await token.waitForDeployment();
  const address = await token.getAddress();
  log.success(`[token] deployed at ${address}`);
  return { address, freshlyDeployed: true };
}

export async function mintIfNeeded(tokenAddress: string, minter: Signer, recipient: string, amount: bigint) {
  const token = (await ethers.getContractAt(
    'contracts/mocks/TestToken.sol:TestToken',
    tokenAddress,
    minter
  )) as TestToken;
  const balance = await token.balanceOf(recipient);
  if (balance < amount) {
    await (await token.mint(recipient, amount - balance)).wait();
  }
}

export async function ensureAllowance(tokenAddress: string, owner: Signer, spender: string, amount: bigint) {
  const token = (await ethers.getContractAt(
    'contracts/mocks/TestToken.sol:TestToken',
    tokenAddress,
    owner
  )) as TestToken;
  const ownerAddress = await owner.getAddress();
  const allowance = await token.allowance(ownerAddress, spender);
  if (allowance < amount) {
    await (await token.approve(spender, amount)).wait();
  }
}
