const { ethers } = require("hardhat");
const {
  getMarketplaceContract,
  createProduct,
  purchaseProduct,
  getBalance,
} = require("./utils/marketplaceHelpers");

async function main() {
  const [deployer, seller, buyer, buyer2] = await ethers.getSigners();

  console.log("Deploying Marketplace contract...");
  const marketplace = await getMarketplaceContract();
  console.log("Marketplace deployed at:", marketplace.address);

  // Define product details
  const productId = 1;
  const price = ethers.utils.parseEther("1"); // 1 token or 1 native currency
  const discount = ethers.utils.parseEther("0.1"); // 0.1 token discount

  // For demo, use native currency address as zero address
  const nativeTokenAddress = ethers.constants.AddressZero;

  // Create product with price in native currency and discount
  console.log("Creating product...");
  await createProduct(marketplace, seller, {
    id: productId,
    price: price,
    tokenAddress: nativeTokenAddress,
    discount: discount,
  });
  console.log("Product created with ID:", productId);

  // Purchase product normally (native currency)
  console.log("Purchasing product with native currency...");
  const sellerBalanceBefore = await getBalance(seller.address, nativeTokenAddress);
  const buyerBalanceBefore = await getBalance(buyer.address, nativeTokenAddress);

  await purchaseProduct(marketplace, buyer, productId, nativeTokenAddress, price);

  const sellerBalanceAfter = await getBalance(seller.address, nativeTokenAddress);
  const buyerBalanceAfter = await getBalance(buyer.address, nativeTokenAddress);

  console.log("Seller balance before:", ethers.utils.formatEther(sellerBalanceBefore));
  console.log("Seller balance after:", ethers.utils.formatEther(sellerBalanceAfter));
  console.log("Buyer balance before:", ethers.utils.formatEther(buyerBalanceBefore));
  console.log("Buyer balance after:", ethers.utils.formatEther(buyerBalanceAfter));

  // Purchase product with another token
  console.log("Deploying test ERC20 token for alternate payment...");
  const Token = await ethers.getContractFactory("TestToken");
  const testToken = await Token.deploy("Test Token", "TTK", 18, ethers.utils.parseEther("1000"));
  await testToken.deployed();
  console.log("TestToken deployed at:", testToken.address);

  // Transfer some tokens to buyer2
  await testToken.transfer(buyer2.address, ethers.utils.parseEther("100"));
  console.log("Transferred 100 TTK to buyer2");

  // Create product priced in testToken
  const productId2 = 2;
  const price2 = ethers.utils.parseEther("10"); // 10 TTK
  await createProduct(marketplace, seller, {
    id: productId2,
    price: price2,
    tokenAddress: testToken.address,
    discount: 0,
  });
  console.log("Product 2 created with ID:", productId2);

  // Purchase product 2 with testToken
  console.log("Purchasing product 2 with testToken...");
  const sellerBalanceBeforeToken = await getBalance(seller.address, testToken.address);
  const buyer2BalanceBefore = await getBalance(buyer2.address, testToken.address);

  await purchaseProduct(marketplace, buyer2, productId2, testToken.address, price2);

  const sellerBalanceAfterToken = await getBalance(seller.address, testToken.address);
  const buyer2BalanceAfter = await getBalance(buyer2.address, testToken.address);

  console.log("Seller TTK balance before:", ethers.utils.formatEther(sellerBalanceBeforeToken));
  console.log("Seller TTK balance after:", ethers.utils.formatEther(sellerBalanceAfterToken));
  console.log("Buyer2 TTK balance before:", ethers.utils.formatEther(buyer2BalanceBefore));
  console.log("Buyer2 TTK balance after:", ethers.utils.formatEther(buyer2BalanceAfter));

  // Purchase product with discount
  console.log("Purchasing product with discount...");
  const discountedPrice = price.sub(discount);
  const buyerBalanceBeforeDiscount = await getBalance(buyer.address, nativeTokenAddress);
  const sellerBalanceBeforeDiscount = await getBalance(seller.address, nativeTokenAddress);

  // For demo, assume purchaseProduct handles discount internally or price is set with discount
  await purchaseProduct(marketplace, buyer, productId, nativeTokenAddress, discountedPrice);

  const buyerBalanceAfterDiscount = await getBalance(buyer.address, nativeTokenAddress);
  const sellerBalanceAfterDiscount = await getBalance(seller.address, nativeTokenAddress);

  console.log("Buyer balance before discount purchase:", ethers.utils.formatEther(buyerBalanceBeforeDiscount));
  console.log("Buyer balance after discount purchase:", ethers.utils.formatEther(buyerBalanceAfterDiscount));
  console.log("Seller balance before discount purchase:", ethers.utils.formatEther(sellerBalanceBeforeDiscount));
  console.log("Seller balance after discount purchase:", ethers.utils.formatEther(sellerBalanceAfterDiscount));

  // Commission collection check
  console.log("Checking commission collection...");
  // For demo, assume marketplace contract has a function to get collected fees
  if (typeof marketplace.getCollectedFees === "function") {
    const fees = await marketplace.getCollectedFees(nativeTokenAddress);
    console.log("Collected fees in native currency:", ethers.utils.formatEther(fees));
  } else {
    console.log("Marketplace contract does not expose getCollectedFees function for demo.");
  }

  console.log("Demo completed.");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
