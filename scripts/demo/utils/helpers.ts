import { ethers } from "hardhat";

export async function deployMockToken(name: string, symbol: string, supply: bigint) {
  const Token = await ethers.getContractFactory("MockERC20");
  const token = await Token.deploy(name, symbol, supply);
  await token.waitForDeployment();
  return token;
}

export async function deployMockOracle() {
  const Oracle = await ethers.getContractFactory("MockPriceOracle");
  const oracle = await Oracle.deploy();
  await oracle.waitForDeployment();
  return oracle;
}
