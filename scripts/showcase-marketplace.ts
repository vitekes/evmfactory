import { ethers, ignition } from "hardhat";
import PublicDeploy from "../ignition/modules/PublicDeploy";
import { deployMockToken } from "./demo/utils/helpers";

async function deploySystem() {
  const deployment = await ignition.deploy(PublicDeploy);

  const marketplaceFactory = await ethers.getContractAt(
    "MarketplaceFactory",
    await deployment.marketplaceFactory.getAddress()
  );
  const tokenValidator = await ethers.getContractAt(
    "TokenValidator",
    await deployment.tokenValidator.getAddress()
  );
  const priceOracle = await ethers.getContractAt(
    "MockPriceOracle",
    await deployment.priceOracle.getAddress()
  );
  const gateway = await ethers.getContractAt(
    "PaymentGateway",
    await deployment.gateway.getAddress()
  );

  // Create a marketplace instance
  const marketplaceAddress = await marketplaceFactory.callStatic.createMarketplace();
  await (await marketplaceFactory.createMarketplace()).wait();

  return { marketplaceAddress, tokenValidator, priceOracle, gateway };
}

async function main() {
  const [seller, buyer] = await ethers.getSigners();
  const chainId = (await ethers.provider.getNetwork()).chainId;

  const { marketplaceAddress, tokenValidator, priceOracle, gateway } = await deploySystem();
  console.log(`Marketplace deployed at ${marketplaceAddress}`);

  const marketplace = await ethers.getContractAt("Marketplace", marketplaceAddress);

  // Deploy demo tokens
  const usd = await deployMockToken("DemoUSD", "DUSD", 1_000_000n * 10n ** 18n);
  const alt = await deployMockToken("AltCoin", "ALT", 1_000_000n * 10n ** 18n);

  // Allow tokens for payments
  await (await tokenValidator.addToken(await usd.getAddress())).wait();
  await (await tokenValidator.addToken(await alt.getAddress())).wait();

  // Configure mock conversion rates (1 USD = 2 ALT)
  await (await priceOracle.setRate(await usd.getAddress(), await alt.getAddress(), ethers.parseEther("2"))).wait();
  await (await priceOracle.setRate(await alt.getAddress(), await usd.getAddress(), ethers.parseEther("0.5"))).wait();

  const listing = {
    sku: ethers.id("demo-item"),
    seller: seller.address,
    price: ethers.parseEther("100"),
    token: await usd.getAddress(),
    salt: 1,
    expiry: 0,
    chainIds: [chainId],
  } as const;

  const domain = { chainId, verifyingContract: marketplaceAddress };
  const types = {
    Listing: [
      { name: "sku", type: "bytes32" },
      { name: "seller", type: "address" },
      { name: "price", type: "uint256" },
      { name: "token", type: "address" },
      { name: "salt", type: "uint256" },
      { name: "expiry", type: "uint256" },
      { name: "chainIds", type: "uint256[]" },
    ],
  } as const;

  const sellerSig = await seller.signTypedData(domain, types, listing);

  // Purchase using listing currency
  await usd.connect(buyer).approve(await gateway.getAddress(), listing.price);
  await (await marketplace.connect(buyer).buy(listing, sellerSig, await usd.getAddress(), listing.price)).wait();
  console.log("Purchased with base token");

  // Purchase using alternative currency
  const altPrice = await marketplace.getPriceInPreferredCurrency(listing, await alt.getAddress());
  await alt.connect(buyer).approve(await gateway.getAddress(), altPrice);
  await (await marketplace.connect(buyer).buy(listing, sellerSig, await alt.getAddress(), altPrice)).wait();
  console.log("Purchased with alternative token");
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});

