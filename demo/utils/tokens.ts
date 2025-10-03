import { ethers } from 'hardhat';
import type { Signer } from 'ethers';
import type { TestToken } from '../../typechain-types';

export async function mintIfNeeded(tokenAddress: string, minter: Signer, recipient: string, amount: bigint) {
  const token = (await ethers.getContractAt('contracts/mocks/TestToken.sol:TestToken', tokenAddress, minter)) as TestToken;
  const balance = await token.balanceOf(recipient);
  if (balance < amount) {
    await (await token.mint(recipient, amount - balance)).wait();
  }
}

export async function ensureAllowance(tokenAddress: string, owner: Signer, spender: string, amount: bigint) {
  const token = (await ethers.getContractAt('contracts/mocks/TestToken.sol:TestToken', tokenAddress, owner)) as TestToken;
  const ownerAddress = await owner.getAddress();
  const allowance = await token.allowance(ownerAddress, spender);
  if (allowance < amount) {
    await (await token.approve(spender, amount)).wait();
  }
}
