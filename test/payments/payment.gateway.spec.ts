import { expect } from 'chai';
import { ethers } from 'hardhat';
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs';
import type {
  DiscountProcessor,
  FeeProcessor,
  GatewayCaller,
  PaymentGateway,
  PaymentOrchestrator,
  ProcessorRegistry,
  TestToken,
} from '../../typechain-types';
import { deployGatewayStack, deployTestToken } from '../shared/paymentStack';

describe('PaymentGateway', function () {
  const MODULE_ID = ethers.id('PAYMENT');
  const PAYMENT_AMOUNT = ethers.parseEther('1');
  const ERC20_AMOUNT = ethers.parseUnits('500', 18);
  const DISCOUNT_BPS = 1000n;

  let gateway: PaymentGateway;
  let orchestrator: PaymentOrchestrator;
  let registry: ProcessorRegistry;
  let token: TestToken;
  let feeCollector: Awaited<ReturnType<typeof ethers.getSigners>>[number];
  let deployer: Awaited<ReturnType<typeof ethers.getSigners>>[number];
  let payer: Awaited<ReturnType<typeof ethers.getSigners>>[number];
  let moduleCaller: Awaited<ReturnType<typeof ethers.getSigners>>[number];
  let outsider: Awaited<ReturnType<typeof ethers.getSigners>>[number];

  beforeEach(async function () {
    [deployer, payer, moduleCaller, outsider, feeCollector] = await ethers.getSigners();

    const stack = await deployGatewayStack(deployer);
    gateway = stack.gateway;
    orchestrator = stack.orchestrator;
    registry = stack.registry;

    token = await deployTestToken(deployer);
    await token.mint(payer.address, ERC20_AMOUNT * 4n);

    await gateway.connect(deployer).setModuleAuthorization(MODULE_ID, moduleCaller.address, true);
  });

    it('reverts for unauthorized module callers', async function () {
    await expect(
      gateway
        .connect(outsider)
        .processPayment(MODULE_ID, token, payer.address, ERC20_AMOUNT, '0x'),
    ).to.be.revertedWithCustomError(gateway, 'Forbidden');
  });

    it('processes ERC-20 payments', async function () {
    await token.connect(payer).approve(await gateway.getAddress(), ERC20_AMOUNT);

    const tx = gateway
      .connect(moduleCaller)
      .processPayment(MODULE_ID, token, payer.address, ERC20_AMOUNT, '0x');

    await expect(tx)
      .to.emit(gateway, 'PaymentProcessed')
      .withArgs(MODULE_ID, anyValue, await token.getAddress(), payer.address, ERC20_AMOUNT, ERC20_AMOUNT, 1);

    await expect(tx).to.changeTokenBalances(token, [payer, moduleCaller], [-ERC20_AMOUNT, ERC20_AMOUNT]);
  });

    it('processes native payments', async function () {
    const tx = gateway
      .connect(moduleCaller)
      .processPayment(MODULE_ID, ethers.ZeroAddress, moduleCaller.address, PAYMENT_AMOUNT, '0x', {
        value: PAYMENT_AMOUNT,
      });

    await expect(tx)
      .to.emit(gateway, 'PaymentProcessed')
      .withArgs(
        MODULE_ID,
        anyValue,
        ethers.ZeroAddress,
        moduleCaller.address,
        PAYMENT_AMOUNT,
        PAYMENT_AMOUNT,
        1,
      );

    await expect(tx).to.changeEtherBalance(gateway, 0);
  });

  it('refunds payer when processors reduce ERC-20 payments', async function () {
    const Discount = await ethers.getContractFactory('DiscountProcessor', deployer);
    const discount = (await Discount.deploy(DISCOUNT_BPS)) as DiscountProcessor;

    await registry.connect(deployer).registerProcessor(await discount.getAddress(), 0);
    await orchestrator
      .connect(deployer)
      .configureProcessor(MODULE_ID, 'DiscountProcessor', true, '0x');

    await token.connect(payer).approve(await gateway.getAddress(), ERC20_AMOUNT);

    const expectedNet = (ERC20_AMOUNT * (10000n - DISCOUNT_BPS)) / 10000n;
    const gatewayAddress = await gateway.getAddress();

    const tx = gateway
      .connect(moduleCaller)
      .processPayment(MODULE_ID, token, payer.address, ERC20_AMOUNT, '0x');

    await expect(tx)
      .to.emit(gateway, 'PaymentProcessed')
      .withArgs(MODULE_ID, anyValue, await token.getAddress(), payer.address, ERC20_AMOUNT, expectedNet, 1);

    await expect(tx).to.changeTokenBalances(token, [payer, moduleCaller, gatewayAddress], [-expectedNet, expectedNet, 0n]);
  });

  it('distributes discount and fee correctly', async function () {
    const Discount = await ethers.getContractFactory('DiscountProcessor', deployer);
    const discount = (await Discount.deploy(DISCOUNT_BPS)) as DiscountProcessor;

    const Fee = await ethers.getContractFactory('FeeProcessor', deployer);
    const fee = (await Fee.deploy(0)) as FeeProcessor;

    await discount.grantRole(await discount.PROCESSOR_ADMIN_ROLE(), await orchestrator.getAddress());
    await fee.grantRole(await fee.PROCESSOR_ADMIN_ROLE(), await orchestrator.getAddress());

    await registry.connect(deployer).registerProcessor(await discount.getAddress(), 0);
    await registry.connect(deployer).registerProcessor(await fee.getAddress(), 1);

    const discountConfig = ethers.getBytes('0x07d0');
    await orchestrator
      .connect(deployer)
      .configureProcessor(MODULE_ID, 'DiscountProcessor', true, discountConfig);

    const feePercentBytes = ethers.getBytes('0x03e8');
    const feeRecipientBytes = ethers.getBytes(feeCollector.address);
    const feeConfig = ethers.concat([feePercentBytes, feeRecipientBytes]);
    await orchestrator
      .connect(deployer)
      .configureProcessor(MODULE_ID, 'FeeProcessor', true, feeConfig);

    await token.connect(payer).approve(await gateway.getAddress(), ERC20_AMOUNT);

    const tx = gateway
      .connect(moduleCaller)
      .processPayment(MODULE_ID, token, payer.address, ERC20_AMOUNT, '0x');

    const expectedNet = ethers.parseUnits('360', 18);
    const expectedPayerLoss = ethers.parseUnits('400', 18);
    const expectedFee = ethers.parseUnits('40', 18);

    await expect(tx)
      .to.emit(gateway, 'PaymentProcessed')
      .withArgs(MODULE_ID, anyValue, await token.getAddress(), payer.address, ERC20_AMOUNT, expectedNet, 1);

    await expect(tx).to.changeTokenBalances(
      token,
      [payer, moduleCaller, feeCollector],
      [-expectedPayerLoss, expectedNet, expectedFee],
    );
  });

  it('maintains unique payment ids inside a single call frame', async function () {
    const Caller = await ethers.getContractFactory('GatewayCaller', deployer);
    const caller = (await Caller.deploy()) as GatewayCaller;

    await gateway.connect(deployer).setModuleAuthorization(MODULE_ID, await caller.getAddress(), true);
    await token.connect(payer).approve(await gateway.getAddress(), ERC20_AMOUNT * 2n);

    const tx = await caller
      .connect(moduleCaller)
      .payTwice(
        await gateway.getAddress(),
        MODULE_ID,
        await token.getAddress(),
        payer.address,
        ERC20_AMOUNT,
      );

    const receipt = await tx.wait();
    const paymentEvents = receipt.logs
      .map((log) => {
        try {
          const parsed = gateway.interface.parseLog(log);
          return parsed.name === 'PaymentProcessed' ? parsed : null;
        } catch (error) {
          return null;
        }
      })
      .filter((entry): entry is ReturnType<typeof gateway.interface.parseLog> => entry !== null);

    expect(paymentEvents.length).to.equal(2);
    const [first, second] = paymentEvents;
    expect(first.args.paymentId).to.not.equal(second.args.paymentId);
    expect(await gateway.getPaymentStatus(first.args.paymentId)).to.equal(1);
    expect(await gateway.getPaymentStatus(second.args.paymentId)).to.equal(1);
  });

  it('reverts when native payment underfunded', async function () {
    await expect(
      gateway
        .connect(moduleCaller)
        .processPayment(MODULE_ID, ethers.ZeroAddress, moduleCaller.address, PAYMENT_AMOUNT, '0x', {
          value: PAYMENT_AMOUNT - 1n,
        }),
    ).to.be.revertedWithCustomError(gateway, 'InsufficientBalance');
  });

  it('reverts on zero amount requests', async function () {
    await expect(
      gateway
        .connect(moduleCaller)
        .processPayment(MODULE_ID, ethers.ZeroAddress, moduleCaller.address, 0, '0x'),
    ).to.be.revertedWithCustomError(gateway, 'InvalidAmount');
  });
});
