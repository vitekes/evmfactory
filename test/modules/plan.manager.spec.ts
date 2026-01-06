import { expect } from 'chai';
import { ethers } from '../../hardhat-connection';
import type {
  CoreSystem,
  PlanManager,
  SubscriptionManager,
  PaymentGateway,
  TestToken,
} from '../../typechain-types';
import { deployGatewayStack, deployTestToken } from '../shared/paymentStack';

describe('PlanManager', function () {
  const MODULE_ID = ethers.keccak256(ethers.toUtf8Bytes('SubscriptionManager'));
  const AUTHOR_ROLE = ethers.keccak256(ethers.toUtf8Bytes('AUTHOR_ROLE'));
  const OPERATOR_ROLE = ethers.keccak256(ethers.toUtf8Bytes('OPERATOR_ROLE'));
  const PLAN_PRICE = ethers.parseEther('10');
  const PLAN_PERIOD = BigInt(30 * 24 * 60 * 60);

  let core: CoreSystem;
  let planManager: PlanManager;
  let subscriptionManager: SubscriptionManager;
  let gateway: PaymentGateway;
  let token: TestToken;

  let deployer: Awaited<ReturnType<typeof ethers.getSigners>>[number];
  let merchant: Awaited<ReturnType<typeof ethers.getSigners>>[number];
  let operator: Awaited<ReturnType<typeof ethers.getSigners>>[number];

  beforeEach(async function () {
    [deployer, merchant, operator] = await ethers.getSigners();

    const Core = await ethers.getContractFactory('CoreSystem', deployer);
    core = (await Core.deploy(deployer.address)) as CoreSystem;

    const { gateway: deployedGateway } = await deployGatewayStack(deployer);
    gateway = deployedGateway;

    const SubscriptionManagerFactory = await ethers.getContractFactory('SubscriptionManager', deployer);
    subscriptionManager = (await SubscriptionManagerFactory.deploy(
      await core.getAddress(),
      await gateway.getAddress(),
      MODULE_ID,
    )) as SubscriptionManager;

    const PlanManagerFactory = await ethers.getContractFactory('PlanManager', deployer);
    planManager = (await PlanManagerFactory.deploy(
      await core.getAddress(),
      await subscriptionManager.getAddress(),
      MODULE_ID,
      1,
    )) as PlanManager;

    await core.grantRole(AUTHOR_ROLE, merchant.address);
    await core.grantRole(OPERATOR_ROLE, operator.address);

    token = await deployTestToken(deployer, 'PlanToken', 'PLAN', 18, 0);
  });

  async function buildPlan(salt: bigint) {
    const { chainId } = await ethers.provider.getNetwork();
    const block = await ethers.provider.getBlock('latest');
    if (!block) throw new Error('missing block');

    const plan = {
      chainIds: [chainId],
      price: PLAN_PRICE,
      period: PLAN_PERIOD,
      token: await token.getAddress(),
      merchant: merchant.address,
      salt,
      expiry: BigInt(block.timestamp) + 3600n,
    };

    const domain = {
      chainId,
      verifyingContract: await subscriptionManager.getAddress(),
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
    return { plan, signature, planHash: await subscriptionManager.hashPlan(plan) };
  }

  it('creates plan and stores metadata', async function () {
    const { plan, signature, planHash } = await buildPlan(1n);

    await expect(planManager.connect(merchant).createPlan(plan, signature, 'ipfs://plan'))
      .to.emit(planManager, 'PlanCreated')
      .withArgs(merchant.address, planHash, PLAN_PRICE, await token.getAddress(), Number(PLAN_PERIOD), 'ipfs://plan');

    const stored = await planManager.getPlan(planHash);
    expect(stored.merchant).to.equal(merchant.address);
    expect(stored.status).to.equal(1); // Active
  });

  it('enforces unique plan hash', async function () {
    const { plan, signature } = await buildPlan(1n);
    await planManager.connect(merchant).createPlan(plan, signature, 'ipfs://plan');
    await expect(planManager.connect(merchant).createPlan(plan, signature, 'ipfs://plan2')).to.be.revertedWithCustomError(
      planManager,
      'PlanAlreadyExists',
    );
  });

  it('respects active plan limit', async function () {
    const first = await buildPlan(1n);
    const second = await buildPlan(2n);
    await planManager.connect(merchant).createPlan(first.plan, first.signature, 'ipfs://one');
    await expect(planManager.connect(merchant).createPlan(second.plan, second.signature, 'ipfs://two')).to.be.revertedWithCustomError(
      planManager,
      'ActivePlanLimitReached',
    );
  });

  it('deactivates and reactivates plan', async function () {
    const { plan, signature, planHash } = await buildPlan(1n);
    await planManager.connect(merchant).createPlan(plan, signature, 'uri://one');

    await expect(planManager.connect(merchant).deactivatePlan(planHash))
      .to.emit(planManager, 'PlanStatusChanged')
      .withArgs(merchant.address, planHash, 0);

    await expect(planManager.connect(merchant).activatePlan(planHash))
      .to.emit(planManager, 'PlanStatusChanged')
      .withArgs(merchant.address, planHash, 1);
  });

  it('allows operator to freeze and prevents reactivation', async function () {
    const { plan, signature, planHash } = await buildPlan(1n);
    await planManager.connect(merchant).createPlan(plan, signature, 'uri://freeze');

    await expect(planManager.connect(operator).freezePlan(planHash, true))
      .to.emit(planManager, 'PlanFrozenToggled')
      .withArgs(operator.address, planHash, true);

    await expect(planManager.connect(merchant).activatePlan(planHash)).to.be.revertedWithCustomError(
      planManager,
      'PlanFrozen',
    );
  });

  it('updates URI and transfers ownership', async function () {
    const { plan, signature, planHash } = await buildPlan(1n);
    await planManager.connect(merchant).createPlan(plan, signature, 'uri://base');

    await expect(planManager.connect(merchant).updatePlanUri(planHash, 'uri://updated'))
      .to.emit(planManager, 'PlanUriUpdated')
      .withArgs(merchant.address, planHash, 'uri://updated');

    const newMerchant = operator;
    await core.grantRole(AUTHOR_ROLE, newMerchant.address);

    await expect(planManager.connect(operator).transferPlanOwnership(planHash, newMerchant.address))
      .to.emit(planManager, 'PlanOwnershipTransferred')
      .withArgs(operator.address, planHash, merchant.address, newMerchant.address);

    const stored = await planManager.getPlan(planHash);
    expect(stored.merchant).to.equal(newMerchant.address);
  });
});
