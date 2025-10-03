import { expect } from 'chai';
import { ethers } from 'hardhat';
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs';
import type {
  CoreSystem,
  PaymentGateway,
  SubscriptionManager,
  TestToken,
} from '../../typechain-types';
import { deployGatewayStack, deployTestToken } from '../shared/paymentStack';

describe('SubscriptionManager', function () {
  const MODULE_ID = ethers.id('SUBSCRIPTION');
  const PLAN_PRICE = ethers.parseEther('25');
  const PLAN_PERIOD_SECONDS = 7 * 24 * 60 * 60;
  const FEATURE_OWNER_ROLE = ethers.id('FEATURE_OWNER_ROLE');
  const AUTOMATION_ROLE = ethers.id('AUTOMATION_ROLE');

  let core: CoreSystem;
  let gateway: PaymentGateway;
  let manager: SubscriptionManager;
  let token: TestToken;

  let deployer: Awaited<ReturnType<typeof ethers.getSigners>>[number];
  let merchant: Awaited<ReturnType<typeof ethers.getSigners>>[number];
  let subscriber: Awaited<ReturnType<typeof ethers.getSigners>>[number];
  let automation: Awaited<ReturnType<typeof ethers.getSigners>>[number];
  let outsider: Awaited<ReturnType<typeof ethers.getSigners>>[number];

  beforeEach(async function () {
    [deployer, merchant, subscriber, automation, outsider] = await ethers.getSigners();

    const Core = await ethers.getContractFactory('CoreSystem', deployer);
    core = (await Core.deploy(deployer.address)) as CoreSystem;

    const { gateway: deployedGateway } = await deployGatewayStack(deployer);
    gateway = deployedGateway;

    const Manager = await ethers.getContractFactory('SubscriptionManager', deployer);
    manager = (await Manager.deploy(await core.getAddress(), await gateway.getAddress(), MODULE_ID)) as SubscriptionManager;

    await core.connect(deployer).grantRole(FEATURE_OWNER_ROLE, deployer.address);

    await core.connect(deployer).registerFeature(MODULE_ID, await manager.getAddress(), 0);
    await core.connect(deployer).setService(MODULE_ID, 'PaymentGateway', await gateway.getAddress());

    await gateway.connect(deployer).setModuleAuthorization(MODULE_ID, await manager.getAddress(), true);

    token = await deployTestToken(deployer, 'SubToken', 'SUB', 18, 0);
    await token.mint(subscriber.address, PLAN_PRICE * 5n);
  });

  async function buildPlan(period: bigint = BigInt(PLAN_PERIOD_SECONDS)) {
    const { chainId } = await ethers.provider.getNetwork();
    const latestBlock = await ethers.provider.getBlock('latest');
    if (!latestBlock) {
      throw new Error('block not found');
    }
    const plan = {
      chainIds: [chainId],
      price: PLAN_PRICE,
      period,
      token: await token.getAddress(),
      merchant: merchant.address,
      salt: 1n,
      expiry: BigInt(latestBlock.timestamp) + 3600n,
    };

    const domain = {
      chainId,
      verifyingContract: await manager.getAddress(),
    } as const;

    const types = {
      Plan: [
        { name: 'chainIds', type: 'uint256[]' },
        { name: 'price', type: 'uint256' },
        { name: 'period', type: 'uint256' },
        { name: 'token', type: 'address' },
        { name: 'merchant', type: 'address' },
        { name: 'salt', type: 'uint256' },
        { name: 'expiry', type: 'uint64' },
      ],
    } as const;

    const signature = await merchant.signTypedData(domain, types, plan);
    const planHash = await manager.hashPlan(plan);
    return { plan, signature, planHash };
  }

    it('reverts when plan has zero period', async function () {
    const { plan, signature } = await buildPlan(0n);

    await expect(
      manager.connect(subscriber).subscribe(plan, signature, '0x'),
    ).to.be.revertedWithCustomError(manager, 'InvalidParameters');
  });

    it('subscribes successfully and stores plan data', async function () {
    const { plan, signature, planHash } = await buildPlan();

    await token.connect(subscriber).approve(await gateway.getAddress(), PLAN_PRICE * 3n);

    await expect(manager.connect(subscriber).subscribe(plan, signature, '0x'))
      .to.emit(manager, 'SubscriptionCreated')
      .withArgs(anyValue, subscriber.address, anyValue, anyValue, anyValue, await manager.MODULE_ID());

    const storedPlan = await manager.plans(planHash);
    expect(storedPlan.merchant).to.equal(merchant.address);

    const subscriberState = await manager.subscribers(subscriber.address);
    expect(subscriberState.planHash).to.equal(planHash);

    expect(await token.balanceOf(merchant.address)).to.equal(PLAN_PRICE);
  });

  it('support legacy subscribeWithToken overload', async function () {
    const { plan, signature } = await buildPlan();

    await token.connect(subscriber).approve(await gateway.getAddress(), PLAN_PRICE);

    await expect(
      manager
        .connect(subscriber)
        .subscribeWithToken(plan, signature, '0x', await token.getAddress()),
    )
      .to.emit(manager, 'SubscriptionCreated')
      .withArgs(anyValue, subscriber.address, anyValue, anyValue, anyValue, MODULE_ID);
  });

    it('automation charge processes due subscription', async function () {
    const { plan, signature } = await buildPlan();

    await token.connect(subscriber).approve(await gateway.getAddress(), PLAN_PRICE * 3n);
    await manager.connect(subscriber).subscribe(plan, signature, '0x');

    await core.connect(deployer).grantRole(AUTOMATION_ROLE, automation.address);

    await ethers.provider.send('evm_increaseTime', [PLAN_PERIOD_SECONDS]);
    await ethers.provider.send('evm_mine', []);

    await expect(manager.connect(automation).charge(subscriber.address))
      .to.emit(manager, 'SubscriptionRenewed')
      .withArgs(anyValue, anyValue, MODULE_ID);

    expect(await token.balanceOf(merchant.address)).to.equal(PLAN_PRICE * 2n);
  });

  it('chargeBatch skips non-due and missing subscriptions', async function () {
    const { plan, signature, planHash } = await buildPlan();

    await token.connect(subscriber).approve(await gateway.getAddress(), PLAN_PRICE);
    await manager.connect(subscriber).subscribe(plan, signature, '0x');

    await core.connect(deployer).grantRole(AUTOMATION_ROLE, automation.address);

    const tx = manager
      .connect(automation)
      .chargeBatch([subscriber.address, outsider.address]);

    await expect(tx)
      .to.emit(manager, 'ChargeSkipped')
      .withArgs(subscriber.address, planHash, 2)
      .and.to.emit(manager, 'ChargeSkipped')
      .withArgs(outsider.address, ethers.ZeroHash, 1);

    expect(await token.balanceOf(merchant.address)).to.equal(PLAN_PRICE);
  });
});
