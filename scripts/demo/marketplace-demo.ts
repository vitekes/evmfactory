import { ethers } from "hardhat";
import { deployCore, registerModule } from "./utils/deployer";
import { CONSTANTS } from "./utils/constants";
import { createMarketplace } from "./utils/marketplace";
import { createListing, purchaseListing } from "./utils/listing";
import { safeExecute } from "./utils/helpers";
import { ensureRoles } from "./utils/roles";

async function main() {
  const [deployer, seller, buyer] = await ethers.getSigners();

  console.log("=== Marketplace Demo ===\n");
  console.log(`Deployer: ${deployer.address}`);
  console.log(`Seller:   ${seller.address}`);
  console.log(`Buyer:    ${buyer.address}\n`);

  const { token, registry, gateway, validator, feeManager, acl } = await deployCore();

  // Fund participants
  await safeExecute("transfer demo tokens", async () => {
    await Promise.all([
      token.transfer(seller.address, ethers.parseEther("50")),
      token.transfer(buyer.address, ethers.parseEther("200"))
    ]);
  });

  // Deploy factory
  const marketplaceFactory = await safeExecute(
    "deploy marketplace factory",
    async () => {
      const Factory = await ethers.getContractFactory("MarketplaceFactory");
      const factory = await Factory.deploy(
        await registry.getAddress(),
        await gateway.getAddress()
      );
      await factory.waitForDeployment();
      return factory;
    }
  );

  // Register marketplace module
  await registerModule(
    registry,
    CONSTANTS.MARKETPLACE_ID,
    await marketplaceFactory.getAddress(),
    await validator.getAddress(),
    await gateway.getAddress()
  );


  // Grant required roles
  await ensureRoles(acl, deployer.address);

  // Create marketplace via factory (fallback to direct creation)
  const marketplaceAddress = await createMarketplace(
    marketplaceFactory,
    registry,
    validator,
    gateway
  );
  // Grant roles to the newly deployed marketplace to allow payment processing
  await ensureRoles(acl, marketplaceAddress);
  const marketplace = await ethers.getContractAt(
    "Marketplace",
    marketplaceAddress
  );
  console.log(`Marketplace deployed: ${marketplaceAddress}\n`);

  // Configure commission for the deployed marketplace using its module id
  const moduleId = await marketplace.MODULE_ID();
  await safeExecute("configure commission", async () => {
    await feeManager.setPercentFee(
      moduleId,
      await token.getAddress(),
      500n
    );
  });

  // Create listing
  const price = ethers.parseEther("10");
  const listingId = await createListing(
    marketplace,
    token,
    seller,
    price,
    "https://example.com/item/1"
  );
  console.log(`Listing created with id ${listingId}`);

  // Buyer approves tokens and purchases the listing
  await (token.connect(buyer) as unknown as typeof token).approve(marketplaceAddress, price);
  await purchaseListing(marketplace, token, buyer, listingId, price);

  // Final balances
  const [sellerBal, buyerBal] = await Promise.all([
    token.balanceOf(seller.address),
    token.balanceOf(buyer.address)
  ]);
  console.log(`Seller balance: ${ethers.formatEther(sellerBal)} tokens`);
  console.log(`Buyer balance:  ${ethers.formatEther(buyerBal)} tokens`);

  const fees = await feeManager.collectedFees(
    moduleId,
    await token.getAddress()
  );
  console.log(`Collected fees: ${ethers.formatEther(fees)} tokens`);
  if (fees > 0n) {
    await feeManager.withdrawFees(
      moduleId,
      await token.getAddress(),
      deployer.address
    );
    console.log("Fees withdrawn to deployer");
  }

  console.log("\n✅ Demo finished");
}

main().catch((error) => {
  console.error("Demo failed", error);
  process.exitCode = 1;
});
