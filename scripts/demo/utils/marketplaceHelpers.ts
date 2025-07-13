import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";

export interface Product {
  id: number;
  price: bigint;
  tokenAddress: string;
  /** Discount percent in basis points (10000 = 100%) */
  discount?: number;
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

export async function createListing(
  marketplace: Contract,
  seller: Signer,
  details: Product
) {
  const network = await ethers.provider.getNetwork();
  const listing = {
    chainIds: [network.chainId],
    token: details.tokenAddress,
    price: details.price,
    sku: ethers.keccak256(ethers.toUtf8Bytes(details.id.toString())),
    seller: await seller.getAddress(),
    salt: Date.now(),
    expiry: 0,
    discountPercent: details.discount ?? 0,
  } as const;

  const domain = {
    chainId: network.chainId,
    verifyingContract: await marketplace.getAddress(),
  } as const;
  const types = {
    Listing: [
      { name: "chainIds", type: "uint256[]" },
      { name: "token", type: "address" },
      { name: "price", type: "uint256" },
      { name: "sku", type: "bytes32" },
      { name: "seller", type: "address" },
      { name: "salt", type: "uint256" },
      { name: "expiry", type: "uint64" },
      { name: "discountPercent", type: "uint16" },
    ],
  } as const;

  const signature = await (seller as any).signTypedData(domain, types, listing);

  return { listing, signature };
}

export async function purchaseListing(
  marketplace: Contract,
  buyer: Signer,
  listing: any,
  signature: string,
  paymentToken: string
) {
  if (paymentToken !== ethers.ZeroAddress) {
    const token = await ethers.getContractAt("IERC20", paymentToken);
    const amount = await marketplace.getPriceInPreferredCurrency(listing, paymentToken);
    await token.connect(buyer).approve(await marketplace.getAddress(), amount);
  }

  const price = listing.price;
  const tx = await marketplace
    .connect(buyer)
    .buy(listing, signature, paymentToken, price, {
      value: paymentToken === ethers.ZeroAddress ? price : 0n,
    });
  await tx.wait();
}

export async function getBalance(address: string, token: string) {
  if (token === ethers.ZeroAddress) {
    return await ethers.provider.getBalance(address);
  }
  const t = await ethers.getContractAt("IERC20", token);
  return await t.balanceOf(address);
}
