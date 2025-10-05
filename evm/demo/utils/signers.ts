import { ethers } from 'hardhat';

export interface DemoSigners {
  deployer: Awaited<ReturnType<typeof ethers.getSigners>>[number];
  secondary: Awaited<ReturnType<typeof ethers.getSigners>>[number];
  tertiary: Awaited<ReturnType<typeof ethers.getSigners>>[number];
}

export async function getDemoSigners(): Promise<DemoSigners> {
  const [deployer, secondary, tertiary] = await ethers.getSigners();
  return { deployer, secondary, tertiary };
}
