const { ethers } = require("hardhat");

async function getMarketplaceContract() {
  const [deployer] = await ethers.getSigners();

  console.log("Deployer address:", deployer.address);

  // CoreSystem - это контракт без фабрики, нужно просто использовать адрес deployer
  const coreSystemAddress = deployer.address;
  console.log("Using deployer address as CoreSystem address:", coreSystemAddress);
  if (!coreSystemAddress) {
    throw new Error("CoreSystem address is undefined");
  }

  // Deploy ProcessorRegistry using deploy() method (ethers v6)
  const ProcessorRegistryFactory = await ethers.getContractFactory("ProcessorRegistry");
  const processorRegistry = await ProcessorRegistryFactory.deploy();
  await processorRegistry.deploymentTransaction();
  const processorRegistryAddress = processorRegistry.target;
  console.log("ProcessorRegistry deployed at:", processorRegistryAddress);
  if (!processorRegistryAddress) {
    throw new Error("ProcessorRegistry address is undefined after deployment");
  }

  // Deploy PaymentOrchestrator with ProcessorRegistry address (ethers v6)
  const PaymentOrchestratorFactory = await ethers.getContractFactory("PaymentOrchestrator");
  const paymentOrchestrator = await PaymentOrchestratorFactory.deploy(processorRegistryAddress);
  await paymentOrchestrator.deploymentTransaction();
  const paymentOrchestratorAddress = paymentOrchestrator.target;
  console.log("PaymentOrchestrator deployed at:", paymentOrchestratorAddress);
  if (!paymentOrchestratorAddress) {
    throw new Error("PaymentOrchestrator address is undefined after deployment");
  }

  // Deploy PaymentGateway with PaymentOrchestrator address (ethers v6)
  const PaymentGatewayFactory = await ethers.getContractFactory("PaymentGateway");
  const paymentGateway = await PaymentGatewayFactory.deploy(paymentOrchestratorAddress);
  await paymentGateway.deploymentTransaction();
  const paymentGatewayAddress = paymentGateway.target;
  console.log("PaymentGateway deployed at:", paymentGatewayAddress);
  if (!paymentGatewayAddress) {
    throw new Error("PaymentGateway address is undefined after deployment");
  }

  // Deploy Marketplace with CoreSystem address, PaymentGateway address, and a moduleId (ethers v6)
  const Marketplace = await ethers.getContractFactory("Marketplace");
  const moduleId = ethers.encodeBytes32String("MARKETPLACE");

  console.log("CoreSystem address:", coreSystemAddress);
  console.log("PaymentGateway address:", paymentGatewayAddress);

  const marketplace = await Marketplace.deploy(coreSystemAddress, paymentGatewayAddress, moduleId);
  await marketplace.deploymentTransaction();
  const marketplaceAddress = marketplace.target;
  console.log("Marketplace deployed at:", marketplaceAddress);

  return marketplace;
}

async function createProduct(marketplace, seller, productDetails) {
  // productDetails: { id, price, tokenAddress, discount }
  const tx = await marketplace.connect(seller).createProduct(
    productDetails.id,
    productDetails.price,
    productDetails.tokenAddress,
    productDetails.discount || 0
  );
  await tx.wait();
}

async function purchaseProduct(marketplace, buyer, productId, paymentToken, amount) {
  // Approve token if needed
  if (paymentToken !== ethers.ZeroAddress) {
    const token = await ethers.getContractAt("IERC20", paymentToken);
    await token.connect(buyer).approve(marketplace.address, amount);
  }
  const tx = await marketplace.connect(buyer).purchase(productId, amount, { value: paymentToken === ethers.ZeroAddress ? amount : 0 });
  await tx.wait();
}

async function getBalance(address, tokenAddress) {
  if (tokenAddress === ethers.ZeroAddress) {
    return await ethers.provider.getBalance(address);
  } else {
    const token = await ethers.getContractAt("IERC20", tokenAddress);
    return await token.balanceOf(address);
  }
}

module.exports = {
  getMarketplaceContract,
  createProduct,
  purchaseProduct,
  getBalance,
};
