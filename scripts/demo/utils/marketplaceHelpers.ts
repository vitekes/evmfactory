import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";

export interface Product {
  id: number;
  price: bigint;
  tokenAddress: string;
  discount?: bigint;
}

/**
 * Deploy core contracts and a marketplace instance.
 * Deployment order:
 * 1. CoreSystem
 * 2. ProcessorRegistry
 * 3. PaymentOrchestrator
 * 4. PaymentGateway
 * 5. Marketplace
 */
export async function getMarketplaceContract(): Promise<Contract> {
  const [deployer] = await ethers.getSigners();

  const CoreSystem = await ethers.getContractFactory("CoreSystem");
  const core = await CoreSystem.deploy(deployer.address);
  await core.waitForDeployment();

  const featureOwner = await core.FEATURE_OWNER_ROLE();
  await core.grantRole(featureOwner, deployer.address);

  const ProcessorRegistry = await ethers.getContractFactory("ProcessorRegistry");
  const registry = await ProcessorRegistry.deploy();
  await registry.waitForDeployment();

  const PaymentOrchestrator = await ethers.getContractFactory("PaymentOrchestrator");
  const orchestrator = await PaymentOrchestrator.deploy(await registry.getAddress());
  await orchestrator.waitForDeployment();

  const PaymentGateway = await ethers.getContractFactory("PaymentGateway");
  const gateway = await PaymentGateway.deploy(await orchestrator.getAddress());
  await gateway.waitForDeployment();

  const Marketplace = await ethers.getContractFactory("Marketplace");
  const moduleId = ethers.keccak256(ethers.toUtf8Bytes("Marketplace"));
  const marketplace = await Marketplace.deploy(await core.getAddress(), await gateway.getAddress(), moduleId);
  await marketplace.waitForDeployment();

  await core.registerFeature(moduleId, await marketplace.getAddress(), 1);
  await core.setService(moduleId, "PaymentGateway", await gateway.getAddress());

  return marketplace;
}

export async function createProduct(
  marketplace: Contract,
  seller: Signer,
  details: Product
) {
  const tx = await marketplace
    .connect(seller)
    .createProduct(details.id, details.price, details.tokenAddress, details.discount ?? 0n);
  await tx.wait();
}

export async function purchaseProduct(
  marketplace: Contract,
  buyer: Signer,
  productId: number,
  paymentToken: string,
  amount: bigint
) {
  if (paymentToken !== ethers.ZeroAddress) {
    const token = await ethers.getContractAt("IERC20", paymentToken);
    await token.connect(buyer).approve(marketplace.getAddress(), amount);
  }
  const tx = await marketplace
    .connect(buyer)
    .purchase(productId, amount, { value: paymentToken === ethers.ZeroAddress ? amount : 0n });
  await tx.wait();
}

export async function getBalance(address: string, token: string) {
  if (token === ethers.ZeroAddress) {
    return await ethers.provider.getBalance(address);
  }
  const t = await ethers.getContractAt("IERC20", token);
  return await t.balanceOf(address);
}
