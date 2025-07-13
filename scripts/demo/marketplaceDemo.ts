import { ethers } from "hardhat";
import {
  getMarketplaceContract,
  createListing,
  purchaseListing,
  getBalance,
  Product,
} from "./utils/marketplaceHelpers";

async function main() {
  const [deployer, seller, buyer, buyer2] = await ethers.getSigners();
  const marketplace = await getMarketplaceContract();

  const productId = 1;
  const price = ethers.parseEther("1");
  const discount = 1000; // 10% discount
  const nativeToken = ethers.ZeroAddress;

  const { listing, signature } = await createListing(marketplace, seller, {
    id: productId,
    price,
    tokenAddress: nativeToken,
    discount: Number(discount),
  } as Product);

  const sellerBefore = await getBalance(seller.address, nativeToken);
  const buyerBefore = await getBalance(buyer.address, nativeToken);
  await purchaseListing(marketplace, buyer, listing, signature, nativeToken);
  const sellerAfter = await getBalance(seller.address, nativeToken);
  const buyerAfter = await getBalance(buyer.address, nativeToken);

  console.log("Seller balance before:", ethers.formatEther(sellerBefore));
  console.log("Seller balance after:", ethers.formatEther(sellerAfter));
  console.log("Buyer balance before:", ethers.formatEther(buyerBefore));
  console.log("Buyer balance after:", ethers.formatEther(buyerAfter));

  const Token = await ethers.getContractFactory("TestToken");
  const testToken = await Token.deploy("Test Token", "TTK", 18, ethers.parseEther("1000"));
  await testToken.waitForDeployment();
  await testToken.transfer(buyer2.address, ethers.parseEther("100"));

  const productId2 = 2;
  const price2 = ethers.parseEther("10");
  const { listing: listing2, signature: signature2 } = await createListing(
    marketplace,
    seller,
    {
      id: productId2,
      price: price2,
      tokenAddress: await testToken.getAddress(),
    } as Product
  );

  const sellerTokenBefore = await getBalance(seller.address, await testToken.getAddress());
  const buyer2Before = await getBalance(buyer2.address, await testToken.getAddress());
  await purchaseListing(
    marketplace,
    buyer2,
    listing2,
    signature2,
    await testToken.getAddress()
  );
  const sellerTokenAfter = await getBalance(seller.address, await testToken.getAddress());
  const buyer2After = await getBalance(buyer2.address, await testToken.getAddress());

  console.log("Seller TTK balance before:", ethers.formatEther(sellerTokenBefore));
  console.log("Seller TTK balance after:", ethers.formatEther(sellerTokenAfter));
  console.log("Buyer2 TTK balance before:", ethers.formatEther(buyer2Before));
  console.log("Buyer2 TTK balance after:", ethers.formatEther(buyer2After));

  console.log("Demo completed.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
