import { expect } from 'chai';
import { ethers } from 'hardhat';
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs';
import type {
  CoreSystem,
  PaymentGateway,
  SubscriptionManager,
  PlanManager,
  TestToken,
} from '../../typechain-types';
import { deployGatewayStack, deployTestToken } from '../shared/paymentStack';

describe('SubscriptionManager (multi-tier)', function () {
  const MODULE_ID = ethers.keccak256(ethers.toUtf8Bytes('SubscriptionManager'));
  const PLAN_PRICE = ethers.parseEther('25');
  const PLAN_PERIOD_SECONDS = 30 * 24 * 60 * 60; // 30 days
  const FEATURE_OWNER_ROLE = ethers.keccak256(ethers.toUtf8Bytes('FEATURE_OWNER_ROLE'));
  const AUTOMATION_ROLE = ethers.keccak256(ethers.toUtf8Bytes('AUTOMATION_ROLE'));
  const AUTHOR_ROLE = ethers.keccak256(ethers.toUtf8Bytes('AUTHOR_ROLE'));
  const OPERATOR_ROLE = ethers.keccak256(ethers.toUtf8Bytes('OPERATOR_ROLE'));

  let core: CoreSystem;
  let gateway: PaymentGateway;
  let manager: SubscriptionManager;
  let planManager: PlanManager;
  let token: TestToken;

  let deployer: Awaited<ReturnType<typeof ethers.getSigners>>[number];
  let merchant: Awaited<ReturnType<typeof ethers.getSigners>>[number];
  let subscriber: Awaited<ReturnType<typeof ethers.getSigners>>[number];
  let automation: Awaited<ReturnType<typeof ethers.getSigners>>[number];
  let operator: Awaited<ReturnType<typeof ethers.getSigners>>[number];
  let secondSubscriber: Awaited<ReturnType<typeof ethers.getSigners>>[number];

  beforeEach(async function () {
    [deployer, merchant, subscriber, automation, operator, secondSubscriber] = await ethers.getSigners();

    const Core = await ethers.getContractFactory('CoreSystem', deployer);
    core = (await Core.deploy(deployer.address)) as CoreSystem;

    const { gateway: deployedGateway } = await deployGatewayStack(deployer);
    gateway = deployedGateway;

    const Manager = await ethers.getContractFactory('SubscriptionManager', deployer);
    manager = (await Manager.deploy(
      await core.getAddress(),
      await gateway.getAddress(),
      MODULE_ID,
    )) as SubscriptionManager;

    const PlanMgr = await ethers.getContractFactory('PlanManager', deployer);
    planManager = (await PlanMgr.deploy(
      await core.getAddress(),
      await manager.getAddress(),
      MODULE_ID,
      5,
    )) as PlanManager;

    // Core setup
    await core.connect(deployer).grantRole(FEATURE_OWNER_ROLE, deployer.address);
    await core.connect(deployer).registerFeature(MODULE_ID, await manager.getAddress(), 0);
    await core.connect(deployer).setService(MODULE_ID, 'PaymentGateway', await gateway.getAddress());
    await core.connect(deployer).setService(MODULE_ID, 'PlanManager', await planManager.getAddress());
    await core.connect(deployer).revokeRole(FEATURE_OWNER_ROLE, deployer.address);

    await gateway.connect(deployer).setModuleAuthorization(MODULE_ID, await manager.getAddress(), true);

    await core.connect(deployer).grantRole(AUTOMATION_ROLE, automation.address);
    await core.connect(deployer).grantRole(OPERATOR_ROLE, operator.address);
    await core.connect(deployer).grantRole(AUTHOR_ROLE, merchant.address);

    token = await deployTestToken(deployer, 'SubToken', 'SUB', 18, 0);
    await token.mint(subscriber.address, PLAN_PRICE * 5n);
    await token.connect(subscriber).approve(await gateway.getAddress(), PLAN_PRICE * 5n);
  });

  type PlanOptions = {
    period?: bigint;
    price?: bigint;
    tokenOverride?: string;
    salt?: bigint;
  };

  async function buildSignedPlan(options: PlanOptions = {}) {
    const period = options.period ?? BigInt(PLAN_PERIOD_SECONDS);
    const price = options.price ?? PLAN_PRICE;
    const tokenAddress = options.tokenOverride ?? (await token.getAddress());
    const salt = options.salt ?? 1n;

    const { chainId } = await ethers.provider.getNetwork();
    const latestBlock = await ethers.provider.getBlock('latest');
    if (!latestBlock) {
      throw new Error('block not found');
    }

    const plan = {
      chainIds: [chainId],
      price,
      period,
      token: tokenAddress,
      merchant: merchant.address,
      salt,
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

  async function createPlan(options: PlanOptions = {}) {
    const { plan, signature, planHash } = await buildSignedPlan(options);
    await planManager.connect(merchant).createPlan(plan, signature, 'ipfs://tier');
    return { plan, signature, planHash };
  }

  async function expectActiveSubscription(user: string, planHash: string) {
    const state = await manager.getSubscriptionByPlan(user, planHash);
    expect(state.status).to.equal(1); // Active
    expect(state.cancelReason).to.equal(0);
    expect(state.merchant).to.equal(merchant.address);
    expect(state.nextChargeAt).to.be.gt(0);
  }

  describe('subscription lifecycle', function () {
    it('reverts if plan not registered', async function () {
      const { plan, signature } = await buildSignedPlan();
      await expect(manager.connect(subscriber).subscribe(plan, signature, '0x')).to.be.revertedWithCustomError(
        manager,
        'PlanNotFound',
      );
    });

    it('subscribes via ERC-20 payment and records state', async function () {
      const { plan, signature, planHash } = await createPlan();

      await expect(manager.connect(subscriber).subscribe(plan, signature, '0x'))
        .to.emit(manager, 'SubscriptionActivated')
        .withArgs(subscriber.address, planHash, merchant.address, anyValue)
        .and.to.emit(manager, 'SubscriptionCharged')
        .withArgs(subscriber.address, planHash, PLAN_PRICE, anyValue);

      await expectActiveSubscription(subscriber.address, planHash);
      expect(await manager.getActivePlan(subscriber.address, merchant.address)).to.equal(planHash);
      expect(await token.balanceOf(merchant.address)).to.equal(PLAN_PRICE);
    });

    it('switches to a newer plan of the same merchant', async function () {
      const first = await createPlan({ salt: 1n });
      const second = await createPlan({ salt: 2n, price: PLAN_PRICE + ethers.parseEther('5') });

      await manager.connect(subscriber).subscribe(first.plan, first.signature, '0x');

      await expect(manager.connect(subscriber).subscribe(second.plan, second.signature, '0x'))
        .to.emit(manager, 'SubscriptionSwitched')
        .withArgs(subscriber.address, first.planHash, second.planHash, merchant.address)
        .and.to.emit(manager, 'SubscriptionActivated');

      const firstState = await manager.getSubscriptionByPlan(subscriber.address, first.planHash);
      expect(firstState.status).to.equal(2); // Inactive
      expect(firstState.cancelReason).to.equal(4); // Switch

      await expectActiveSubscription(subscriber.address, second.planHash);
    });

    it('supports subscribeWithToken flow with conversion and maxPaymentAmount', async function () {
      const altToken = await deployTestToken(deployer, 'ALT', 'ALT', 18, 0);
      await altToken.mint(subscriber.address, PLAN_PRICE * 2n);
      await altToken.connect(subscriber).approve(await gateway.getAddress(), PLAN_PRICE * 2n);

      const { plan, signature, planHash } = await createPlan();

      await expect(
        manager
          .connect(subscriber)
          [
            'subscribeWithToken((uint256[],uint256,uint256,address,address,uint256,uint64),bytes,bytes,address,uint256)'
          ](plan, signature, '0x', await altToken.getAddress(), PLAN_PRICE * 2n),
      )
        .to.emit(manager, 'SubscriptionActivated')
        .withArgs(subscriber.address, planHash, merchant.address, anyValue);

      await expect(
        manager
          .connect(subscriber)
          [
            'subscribeWithToken((uint256[],uint256,uint256,address,address,uint256,uint64),bytes,bytes,address,uint256)'
          ](plan, signature, '0x', await altToken.getAddress(), PLAN_PRICE - 1n),
      ).to.be.revertedWithCustomError(manager, 'PriceExceedsMaximum');
    });

    it('allows user to unsubscribe and withdraw native deposit', async function () {
      const { plan, signature, planHash } = await createPlan({ tokenOverride: ethers.ZeroAddress, price: PLAN_PRICE });
      await manager.connect(subscriber).subscribe(plan, signature, '0x', { value: PLAN_PRICE + ethers.parseEther('1') });

      await expect(manager.connect(subscriber).unsubscribe(merchant.address))
        .to.emit(manager, 'SubscriptionCancelled')
        .withArgs(subscriber.address, planHash, 1); // reason User

      const state = await manager.getSubscriptionByPlan(subscriber.address, planHash);
      expect(state.status).to.equal(2);
      expect(await manager.getActivePlan(subscriber.address, merchant.address)).to.equal(ethers.ZeroHash);
      expect(await manager.getNativeDeposit(subscriber.address)).to.equal(0n);
    });
  });

  describe('charges and retries', function () {
    it('processes scheduled charge after period', async function () {
      const { plan, signature, planHash } = await createPlan();
      await manager.connect(subscriber).subscribe(plan, signature, '0x');

      await ethers.provider.send('evm_increaseTime', [PLAN_PERIOD_SECONDS]);
      await ethers.provider.send('evm_mine', []);

      const previousState = await manager.getSubscriptionByPlan(subscriber.address, planHash);

      await expect(
        manager
          .connect(automation)
          ['charge(address,bytes32)'](subscriber.address, planHash),
      )
        .to.emit(manager, 'SubscriptionCharged')
        .withArgs(subscriber.address, planHash, PLAN_PRICE, anyValue);

      const nextState = await manager.getSubscriptionByPlan(subscriber.address, planHash);
      expect(nextState.lastChargedAt).to.be.gt(previousState.lastChargedAt);
      expect(nextState.retryCount).to.equal(0);
      expect(nextState.retryAt).to.equal(0);
    });

    it('processes chargeBatch for multiple users', async function () {
      const { plan, signature, planHash } = await createPlan();
      await manager.connect(subscriber).subscribe(plan, signature, '0x');

      await token.mint(secondSubscriber.address, PLAN_PRICE * 5n);
      await token.connect(secondSubscriber).approve(await gateway.getAddress(), PLAN_PRICE * 5n);
      await manager.connect(secondSubscriber).subscribe(plan, signature, '0x');

      await ethers.provider.send('evm_increaseTime', [PLAN_PERIOD_SECONDS]);
      await ethers.provider.send('evm_mine', []);

      await expect(
        manager
          .connect(automation)
          ['chargeBatch(address[],bytes32[])'](
            [subscriber.address, secondSubscriber.address],
            [planHash, planHash],
          ),
      )
        .to.emit(manager, 'SubscriptionCharged')
        .withArgs(subscriber.address, planHash, PLAN_PRICE, anyValue)
        .and.to.emit(manager, 'SubscriptionCharged')
        .withArgs(secondSubscriber.address, planHash, PLAN_PRICE, anyValue);

      const firstState = await manager.getSubscriptionByPlan(subscriber.address, planHash);
      const secondState = await manager.getSubscriptionByPlan(secondSubscriber.address, planHash);
      expect(firstState.lastChargedAt).to.be.gt(0);
      expect(secondState.lastChargedAt).to.be.gt(0);
    });

    it('marks retry on first failure and cancels on second', async function () {
      const { plan, signature, planHash } = await createPlan({ tokenOverride: ethers.ZeroAddress, price: PLAN_PRICE });

      await manager.connect(subscriber).subscribe(plan, signature, '0x', { value: PLAN_PRICE });

      // native deposit depleted, first charge will fail and mark retry
      await ethers.provider.send('evm_increaseTime', [PLAN_PERIOD_SECONDS]);
      await ethers.provider.send('evm_mine', []);

      await manager.connect(automation).markFailedCharge(subscriber.address, planHash);
      const retryState = await manager.getSubscriptionByPlan(subscriber.address, planHash);
      expect(retryState.retryCount).to.equal(1);
      expect(retryState.retryAt).to.be.gt(0);

      await manager.connect(automation).markFailedCharge(subscriber.address, planHash);
      const finalState = await manager.getSubscriptionByPlan(subscriber.address, planHash);
      expect(finalState.status).to.equal(2); // Inactive
      expect(finalState.cancelReason).to.equal(2); // RetryFailed
      expect(await manager.getActivePlan(subscriber.address, merchant.address)).to.equal(ethers.ZeroHash);
    });
  });

  describe('operator tools', function () {
    it('allows operator to force cancel', async function () {
      const { plan, signature, planHash } = await createPlan();
      await manager.connect(subscriber).subscribe(plan, signature, '0x');

      await expect(manager.connect(operator).forceCancel(subscriber.address, merchant.address, 0))
        .to.emit(manager, 'SubscriptionCancelled')
        .withArgs(subscriber.address, planHash, 3); // Operator

      const state = await manager.getSubscriptionByPlan(subscriber.address, planHash);
      expect(state.status).to.equal(2);
      expect(state.cancelReason).to.equal(3);
    });

    it('reactivates subscription manually', async function () {
      const { plan, signature, planHash } = await createPlan();
      await manager.connect(subscriber).subscribe(plan, signature, '0x');

      await manager.connect(operator).forceCancel(subscriber.address, merchant.address, 0);

      await expect(manager.connect(operator).activateManually(subscriber.address, planHash, 1))
        .to.emit(manager, 'ManualActivation')
        .withArgs(operator.address, subscriber.address, planHash, 1)
        .and.to.emit(manager, 'SubscriptionActivated');

      const state = await manager.getSubscriptionByPlan(subscriber.address, planHash);
      expect(state.status).to.equal(1);
    });
  });

  describe('PlanManager integration', function () {
    it('enforces author role on plan creation', async function () {
      const signedPlan = await buildSignedPlan();
      await expect(
        planManager.connect(operator).createPlan(signedPlan.plan, signedPlan.signature, 'ipfs://tier'),
      ).to.be.revertedWithCustomError(
        planManager,
        'UnauthorizedMerchant',
      );
    });

    it('disallows activating frozen plan', async function () {
      const { planHash } = await createPlan();
      await planManager.connect(operator).freezePlan(planHash, true);
      await expect(planManager.connect(merchant).activatePlan(planHash)).to.be.revertedWithCustomError(
        planManager,
        'PlanFrozen',
      );
    });
  });
});
