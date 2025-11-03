import { expect } from 'chai';
import { ethers } from 'hardhat';
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs';
import type {
  CoreSystem,
  Donate,
  FeeProcessor,
  PaymentGateway,
  PaymentOrchestrator,
  ProcessorRegistry,
  TestToken,
  TokenFilterProcessor,
} from '../../typechain-types';
import { deployGatewayStack, deployTestToken } from '../shared/paymentStack';

const MODULE_ID = ethers.id('Donate');
const FEATURE_OWNER_ROLE = ethers.id('FEATURE_OWNER_ROLE');
const FEE_BPS = 250; // 2.5%

describe('Donate module', function () {
  let admin: Awaited<ReturnType<typeof ethers.getSigners>>[number];
  let donor: Awaited<ReturnType<typeof ethers.getSigners>>[number];
  let recipient: Awaited<ReturnType<typeof ethers.getSigners>>[number];
  let treasury: Awaited<ReturnType<typeof ethers.getSigners>>[number];

  let core: CoreSystem;
  let registry: ProcessorRegistry;
  let orchestrator: PaymentOrchestrator;
  let gateway: PaymentGateway;
  let donate: Donate;
  let paymentToken: TestToken;
  let tokenFilter: TokenFilterProcessor;
  let feeProcessor: FeeProcessor;

  beforeEach(async function () {
    [admin, donor, recipient, treasury] = await ethers.getSigners();

    const Core = await ethers.getContractFactory('CoreSystem', admin);
    core = (await Core.deploy(admin.address)) as CoreSystem;

    const stack = await deployGatewayStack(admin);
    registry = stack.registry;
    orchestrator = stack.orchestrator;
    gateway = stack.gateway;

    const TokenFilterFactory = await ethers.getContractFactory('TokenFilterProcessor', admin);
    tokenFilter = (await TokenFilterFactory.deploy()) as TokenFilterProcessor;

    const FeeProcessorFactory = await ethers.getContractFactory('FeeProcessor', admin);
    feeProcessor = (await FeeProcessorFactory.deploy(0)) as FeeProcessor;

    await registry.connect(admin).registerProcessor(await tokenFilter.getAddress(), 0);
    await registry.connect(admin).registerProcessor(await feeProcessor.getAddress(), 1);

    const tokenFilterAdminRole = await tokenFilter.PROCESSOR_ADMIN_ROLE();
    await tokenFilter.connect(admin).grantRole(tokenFilterAdminRole, await orchestrator.getAddress());

    const feeProcessorAdminRole = await feeProcessor.PROCESSOR_ADMIN_ROLE();
    await feeProcessor.connect(admin).grantRole(feeProcessorAdminRole, await orchestrator.getAddress());

    paymentToken = await deployTestToken(admin, 'DonateToken', 'DNT', 18, 0);
    const paymentTokenAddress = await paymentToken.getAddress();

    const feeConfig = ethers.concat([
      ethers.zeroPadValue(ethers.toBeHex(FEE_BPS), 2),
      ethers.zeroPadValue(await treasury.getAddress(), 20),
    ]);
    await orchestrator.connect(admin).configureProcessor(MODULE_ID, 'FeeProcessor', true, feeConfig);

    const allowedTokenConfig = ethers.concat([ethers.getBytes(paymentTokenAddress)]);
    await orchestrator.connect(admin).configureProcessor(MODULE_ID, 'TokenFilter', true, allowedTokenConfig);

    const DonateFactory = await ethers.getContractFactory('Donate', admin);
    donate = (await DonateFactory.deploy(await core.getAddress(), await gateway.getAddress(), MODULE_ID)) as Donate;
    await donate.waitForDeployment();

    await core.connect(admin).grantRole(FEATURE_OWNER_ROLE, await admin.getAddress());
    await core.connect(admin).grantRole(FEATURE_OWNER_ROLE, await donate.getAddress());
    await core.connect(admin).registerFeature(MODULE_ID, await donate.getAddress(), 0);
    await core.connect(admin).setService(MODULE_ID, 'PaymentGateway', await gateway.getAddress());
    await gateway.connect(admin).setModuleAuthorization(MODULE_ID, await donate.getAddress(), true);
    await core.connect(admin).revokeRole(FEATURE_OWNER_ROLE, await admin.getAddress());

    await paymentToken.mint(await donor.getAddress(), ethers.parseUnits('1000', 18));
    await paymentToken.connect(donor).approve(await gateway.getAddress(), ethers.MaxUint256);
  });

  it('обрабатывает пожертвование в ERC-20 и распределяет комиссию', async function () {
    const amount = ethers.parseUnits('100', 18);
    const metadata = ethers.keccak256(ethers.toUtf8Bytes('charity-campaign-1'));
    const feeAmount = (amount * BigInt(FEE_BPS)) / 10000n;
    const expectedNet = amount - feeAmount;

    await expect(donate.connect(donor).donate(await recipient.getAddress(), await paymentToken.getAddress(), amount, metadata))
      .to.emit(donate, 'DonationProcessed')
      .withArgs(
        1n,
        await donor.getAddress(),
        await recipient.getAddress(),
        await paymentToken.getAddress(),
        amount,
        expectedNet,
        metadata,
        anyValue,
        MODULE_ID,
      );

    expect(await paymentToken.balanceOf(await recipient.getAddress())).to.equal(expectedNet);
    expect(await paymentToken.balanceOf(await treasury.getAddress())).to.equal(feeAmount);
    expect(await paymentToken.balanceOf(await donor.getAddress())).to.equal(ethers.parseUnits('900', 18));
  });

  it('отклоняет пожертвование токеном вне белого списка', async function () {
    const otherToken = await deployTestToken(admin, 'OtherToken', 'NOPE', 18, 0);
    const amount = ethers.parseUnits('10', 18);

    await otherToken.mint(await donor.getAddress(), amount);
    await otherToken.connect(donor).approve(await gateway.getAddress(), amount);

    await expect(
      donate.connect(donor).donate(await recipient.getAddress(), await otherToken.getAddress(), amount, ethers.ZeroHash),
    ).to.be.revertedWith('TokenFilter: token not allowed');
  });

  it('позволяет администратору ядра вернуть случайно отправленные активы', async function () {
    const rescueAmount = ethers.parseUnits('5', 18);
    await paymentToken.mint(await admin.getAddress(), rescueAmount);
    await paymentToken.connect(admin).transfer(await donate.getAddress(), rescueAmount);

    await expect(
      donate.connect(donor).rescueTokens(await paymentToken.getAddress(), await donor.getAddress(), rescueAmount),
    ).to.be.revertedWithCustomError(donate, 'NotAdmin');

    await donate
      .connect(admin)
      .rescueTokens(await paymentToken.getAddress(), await admin.getAddress(), rescueAmount);

    expect(await paymentToken.balanceOf(await admin.getAddress())).to.equal(rescueAmount);
  });
});
