import { expect } from 'chai';
import { ethers } from '../../hardhat-connection';
import { anyValue } from '@nomicfoundation/hardhat-ethers-chai-matchers/withArgs';
import type { CoreSystem, Marketplace, PaymentGateway, TestToken } from '../../typechain-types';
import { deployGatewayStack, deployTestToken } from '../shared/paymentStack';

const MODULE_ID = ethers.id('Marketplace');
const FEATURE_OWNER_ROLE = ethers.id('FEATURE_OWNER_ROLE');

interface ListingInput {
  chainIds: bigint[];
  token: string;
  price: bigint;
  sku: string;
  seller: string;
  salt: bigint;
  expiry: bigint;
  discountPercent?: number;
}

describe('Marketplace', function () {
  let admin: Awaited<ReturnType<typeof ethers.getSigners>>[number];
  let seller: Awaited<ReturnType<typeof ethers.getSigners>>[number];
  let buyer: Awaited<ReturnType<typeof ethers.getSigners>>[number];
  let other: Awaited<ReturnType<typeof ethers.getSigners>>[number];
  let core: CoreSystem;
  let gateway: PaymentGateway;
  let marketplace: Marketplace;
  let paymentToken: TestToken;

  beforeEach(async function () {
    [admin, seller, buyer, other] = await ethers.getSigners();

    const Core = await ethers.getContractFactory('CoreSystem', admin);
    core = (await Core.deploy(admin.address)) as CoreSystem;

    const stack = await deployGatewayStack(admin);
    gateway = stack.gateway;

    const MarketplaceFactory = await ethers.getContractFactory('Marketplace', admin);
    marketplace = (await MarketplaceFactory.deploy(
      await core.getAddress(),
      await gateway.getAddress(),
      MODULE_ID,
    )) as Marketplace;
    await marketplace.waitForDeployment();

    await core.connect(admin).grantRole(FEATURE_OWNER_ROLE, await admin.getAddress());
    await core.connect(admin).grantRole(FEATURE_OWNER_ROLE, await marketplace.getAddress());

    await core.connect(admin).registerFeature(MODULE_ID, await marketplace.getAddress(), 0);
    await core.connect(admin).setService(MODULE_ID, 'PaymentGateway', await gateway.getAddress());
    await gateway.connect(admin).setModuleAuthorization(MODULE_ID, await marketplace.getAddress(), true);

    await core.connect(admin).revokeRole(FEATURE_OWNER_ROLE, await admin.getAddress());

    paymentToken = await deployTestToken(admin, 'PayToken', 'PAY', 18, 0);
    await paymentToken.mint(await buyer.getAddress(), ethers.parseEther('1000'));
    await paymentToken.connect(buyer).approve(await gateway.getAddress(), ethers.MaxUint256);
  });

  async function signListing(input: ListingInput) {
    const listing = {
      chainIds: input.chainIds,
      token: input.token,
      price: input.price,
      sku: ethers.keccak256(ethers.toUtf8Bytes(input.sku)),
      seller: input.seller,
      salt: input.salt,
      expiry: input.expiry,
      discountPercent: input.discountPercent ?? 0,
    };

    const domain = {
      chainId: (await ethers.provider.getNetwork()).chainId,
      verifyingContract: await marketplace.getAddress(),
    } as const;

    const types = {
      Listing: [
        { name: 'chainIds', type: 'uint256[]' },
        { name: 'token', type: 'address' },
        { name: 'price', type: 'uint256' },
        { name: 'sku', type: 'bytes32' },
        { name: 'seller', type: 'address' },
        { name: 'salt', type: 'uint256' },
        { name: 'expiry', type: 'uint64' },
        { name: 'discountPercent', type: 'uint16' },
      ],
    } as const;

    const signature = await seller.signTypedData(domain, types, listing);
    return { listing, signature };
  }

  function futureTimestamp(secondsFromNow = 3600): bigint {
    return BigInt(Math.floor(Date.now() / 1000) + secondsFromNow);
  }

  it('processes ERC-20 purchase and prevents re-use of listing', async function () {
    const { listing, signature } = await signListing({
      chainIds: [BigInt((await ethers.provider.getNetwork()).chainId)],
      token: await paymentToken.getAddress(),
      price: ethers.parseEther('100'),
      sku: 'SKU-ERC',
      seller: await seller.getAddress(),
      salt: 1n,
      expiry: futureTimestamp(),
    });

    await expect(marketplace.connect(buyer).buy(listing, signature, listing.token, 0))
      .to.emit(marketplace, 'MarketplaceSale')
      .withArgs(
        listing.sku,
        listing.seller,
        await buyer.getAddress(),
        listing.price,
        listing.token,
        listing.price,
        anyValue,
        anyValue,
        MODULE_ID,
      );

    expect(await paymentToken.balanceOf(listing.seller)).to.equal(listing.price);

    await expect(marketplace.connect(other).buy(listing, signature, listing.token, 0)).to.be.revertedWithCustomError(
      marketplace,
      'Expired',
    );
  });

  it('processes native payment, refunding excess value', async function () {
    const price = ethers.parseEther('1');
    const extra = ethers.parseEther('0.2');
    const { listing, signature } = await signListing({
      chainIds: [BigInt((await ethers.provider.getNetwork()).chainId)],
      token: ethers.ZeroAddress,
      price,
      sku: 'SKU-NATIVE',
      seller: await seller.getAddress(),
      salt: 2n,
      expiry: futureTimestamp(),
    });

    const sellerBalanceBefore = await ethers.provider.getBalance(listing.seller);
    const buyerBalanceBefore = await ethers.provider.getBalance(await buyer.getAddress());

    const tx = await marketplace
      .connect(buyer)
      .buy(listing, signature, ethers.ZeroAddress, 0, { value: price + extra });
    const receipt = await tx.wait();
    const gasSpent = receipt?.gasUsed ? receipt.gasUsed * tx.gasPrice! : 0n;

    const sellerAfter = await ethers.provider.getBalance(listing.seller);
    const buyerAfter = await ethers.provider.getBalance(await buyer.getAddress());

    expect(sellerAfter - sellerBalanceBefore).to.equal(price);
    expect(buyerBalanceBefore - buyerAfter).to.equal(price + gasSpent);
  });

  it('enforces maxPaymentAmount for same-token payments', async function () {
    const { listing, signature } = await signListing({
      chainIds: [BigInt((await ethers.provider.getNetwork()).chainId)],
      token: await paymentToken.getAddress(),
      price: ethers.parseEther('5'),
      sku: 'SKU-LIMIT',
      seller: await seller.getAddress(),
      salt: 3n,
      expiry: futureTimestamp(),
    });

    await expect(
      marketplace.connect(buyer).buy(listing, signature, listing.token, ethers.parseEther('4')),
    ).to.be.revertedWithCustomError(marketplace, 'PriceExceedsMaximum');
  });

  it('processes purchase with alternative payment token conversion', async function () {
    const listingToken = await deployTestToken(admin, 'ListingToken', 'LST', 18, 0);
    const listingPrice = ethers.parseEther('7');
    await listingToken.mint(await seller.getAddress(), listingPrice);

    const { listing, signature } = await signListing({
      chainIds: [BigInt((await ethers.provider.getNetwork()).chainId)],
      token: await listingToken.getAddress(),
      price: listingPrice,
      sku: 'SKU-CONVERT',
      seller: await seller.getAddress(),
      salt: 11n,
      expiry: futureTimestamp(),
    });

    const buyerPaymentBefore = await paymentToken.balanceOf(await buyer.getAddress());

    await expect(marketplace.connect(buyer).buy(listing, signature, await paymentToken.getAddress(), listingPrice))
      .to.emit(marketplace, 'MarketplaceSale')
      .withArgs(
        listing.sku,
        listing.seller,
        await buyer.getAddress(),
        listing.price,
        await paymentToken.getAddress(),
        listingPrice,
        anyValue,
        anyValue,
        MODULE_ID,
      );

    const buyerPaymentAfter = await paymentToken.balanceOf(await buyer.getAddress());
    expect(buyerPaymentBefore - buyerPaymentAfter).to.equal(listingPrice);
    expect(await paymentToken.balanceOf(listing.seller)).to.equal(listingPrice);
  });

  it('reverts when converted amount exceeds maxPaymentAmount', async function () {
    const listingToken = await deployTestToken(admin, 'ListingToken2', 'LST2', 18, 0);
    const listingPrice = ethers.parseEther('4');
    await listingToken.mint(await seller.getAddress(), listingPrice);

    const { listing, signature } = await signListing({
      chainIds: [BigInt((await ethers.provider.getNetwork()).chainId)],
      token: await listingToken.getAddress(),
      price: listingPrice,
      sku: 'SKU-CONVERT-LIMIT',
      seller: await seller.getAddress(),
      salt: 12n,
      expiry: futureTimestamp(),
    });

    await expect(
      marketplace
        .connect(buyer)
        .buy(listing, signature, await paymentToken.getAddress(), listingPrice - ethers.parseEther('1')),
    ).to.be.revertedWithCustomError(marketplace, 'PriceExceedsMaximum');
  });

  it('allows seller to revoke listings and ignores foreign revokeBySku calls', async function () {
    const { listing, signature } = await signListing({
      chainIds: [BigInt((await ethers.provider.getNetwork()).chainId)],
      token: await paymentToken.getAddress(),
      price: ethers.parseEther('2'),
      sku: 'SKU-REVOKE',
      seller: await seller.getAddress(),
      salt: 10n,
      expiry: futureTimestamp(),
    });

    await marketplace.connect(other).revokeBySku(listing.sku, 100n);

    await expect(marketplace.connect(buyer).buy(listing, signature, listing.token, 0)).to.emit(
      marketplace,
      'MarketplaceSale',
    );

    const listing2 = await signListing({
      chainIds: [BigInt((await ethers.provider.getNetwork()).chainId)],
      token: await paymentToken.getAddress(),
      price: ethers.parseEther('2'),
      sku: 'SKU-REVOKE2',
      seller: await seller.getAddress(),
      salt: 1n,
      expiry: futureTimestamp(),
    });

    await marketplace.connect(seller).revokeBySku(listing2.listing.sku, 5n);

    await expect(
      marketplace.connect(buyer).buy(listing2.listing, listing2.signature, listing2.listing.token, 0),
    ).to.be.revertedWithCustomError(marketplace, 'Expired');
  });

  it('only allows seller to revoke specific listing', async function () {
    const { listing, signature } = await signListing({
      chainIds: [BigInt((await ethers.provider.getNetwork()).chainId)],
      token: await paymentToken.getAddress(),
      price: ethers.parseEther('3'),
      sku: 'SKU-SELLER',
      seller: await seller.getAddress(),
      salt: 42n,
      expiry: futureTimestamp(),
    });

    await expect(marketplace.connect(other).revokeListing(listing, signature)).to.be.revertedWithCustomError(
      marketplace,
      'NotSeller',
    );

    await expect(marketplace.connect(seller).revokeListing(listing, signature)).to.emit(marketplace, 'ListingRevoked');
  });
});
