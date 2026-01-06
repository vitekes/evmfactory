import { expect } from 'chai';
import { ethers } from '../../hardhat-connection';
import type { CoreSystem, MonetaryCash, TestToken } from '../../typechain-types';
import { deployTestToken } from '../shared/paymentStack';

describe('MonetaryCash', function () {
  const MODULE_ID = ethers.id('MonetaryCash');
  const FEATURE_OWNER_ROLE = ethers.id('FEATURE_OWNER_ROLE');
  const AMOUNT = ethers.parseEther('5');

  let core: CoreSystem;
  let monetaryCash: MonetaryCash;
  let token: TestToken;

  let deployer: Awaited<ReturnType<typeof ethers.getSigners>>[number];
  let backendSigner: Awaited<ReturnType<typeof ethers.getSigners>>[number];
  let recipient: Awaited<ReturnType<typeof ethers.getSigners>>[number];
  let caller: Awaited<ReturnType<typeof ethers.getSigners>>[number];

  beforeEach(async function () {
    [deployer, backendSigner, recipient, caller] = await ethers.getSigners();

    const Core = await ethers.getContractFactory('CoreSystem', deployer);
    core = (await Core.deploy(deployer.address)) as CoreSystem;
    await core.grantRole(FEATURE_OWNER_ROLE, deployer.address);

    const MonetaryCashFactory = await ethers.getContractFactory('MonetaryCash', deployer);
    monetaryCash = (await MonetaryCashFactory.deploy(
      await core.getAddress(),
      MODULE_ID,
      backendSigner.address,
    )) as MonetaryCash;

    token = await deployTestToken(deployer, 'CashToken', 'CASH', 18, 0);
    await token.mint(deployer.address, AMOUNT * 2n);
    await token.connect(deployer).approve(await monetaryCash.getAddress(), AMOUNT * 2n);
  });

  async function signActivation(cashId: bigint, deadline: bigint) {
    const { chainId } = await ethers.provider.getNetwork();
    const domain = {
      name: 'MonetaryCash',
      version: '1',
      chainId,
      verifyingContract: await monetaryCash.getAddress(),
    } as const;

    const types = {
      ActivateCash: [
        { name: 'cashId', type: 'uint256' },
        { name: 'recipient', type: 'address' },
        { name: 'deadline', type: 'uint256' },
      ],
    } as const;

    const message = {
      cashId,
      recipient: recipient.address,
      deadline,
    } as const;

    return backendSigner.signTypedData(domain, types, message);
  }

  it('creates and activates ERC-20 cash with backend signature', async function () {
    const latest = await ethers.provider.getBlock('latest');
    if (!latest) {
      throw new Error('block not found');
    }
    const expiresAt = BigInt(latest.timestamp + 3600);
    const tx = monetaryCash.connect(deployer).createCash(await token.getAddress(), AMOUNT, expiresAt);
    await expect(tx)
      .to.emit(monetaryCash, 'MonetaryCashCreated')
      .withArgs(deployer.address, 1, await token.getAddress(), AMOUNT, expiresAt);

    expect(await monetaryCash.getCashStatus(1)).to.equal(1);

    const deadline = BigInt(latest.timestamp + 3600);
    const signature = await signActivation(1n, deadline);

    await expect(monetaryCash.connect(caller).activateCashWithSig(1, recipient.address, deadline, signature))
      .to.emit(monetaryCash, 'MonetaryCashActivated')
      .withArgs(recipient.address, 1);

    expect(await token.balanceOf(recipient.address)).to.equal(AMOUNT);
  });

  it('rejects invalid signatures', async function () {
    await monetaryCash.connect(deployer).createCash(await token.getAddress(), AMOUNT, 0);
    const latest = await ethers.provider.getBlock('latest');
    if (!latest) {
      throw new Error('block not found');
    }
    const deadline = BigInt(latest.timestamp + 3600);

    const { chainId } = await ethers.provider.getNetwork();
    const domain = {
      name: 'MonetaryCash',
      version: '1',
      chainId,
      verifyingContract: await monetaryCash.getAddress(),
    } as const;

    const types = {
      ActivateCash: [
        { name: 'cashId', type: 'uint256' },
        { name: 'recipient', type: 'address' },
        { name: 'deadline', type: 'uint256' },
      ],
    } as const;

    const message = {
      cashId: 1n,
      recipient: recipient.address,
      deadline,
    } as const;

    const signature = await caller.signTypedData(domain, types, message);

    await expect(
      monetaryCash.connect(caller).activateCashWithSig(1, recipient.address, deadline, signature),
    ).to.be.revertedWithCustomError(monetaryCash, 'InvalidSignature');
  });

  it('prevents activation after expiry', async function () {
    const latest = await ethers.provider.getBlock('latest');
    if (!latest) {
      throw new Error('block not found');
    }
    const now = latest.timestamp;
    const expiresAt = BigInt(now + 60);
    await monetaryCash.connect(deployer).createCash(await token.getAddress(), AMOUNT, expiresAt);

    const signature = await signActivation(1n, BigInt(now + 300));

    await ethers.provider.send('evm_increaseTime', [120]);
    await ethers.provider.send('evm_mine', []);

    await expect(
      monetaryCash.connect(caller).activateCashWithSig(1, recipient.address, BigInt(now + 300), signature),
    ).to.be.revertedWithCustomError(monetaryCash, 'Expired');
  });

  it('allows admin to cancel and refund', async function () {
    await monetaryCash.connect(deployer).createCash(await token.getAddress(), AMOUNT, 0);

    await expect(monetaryCash.connect(deployer).cancelCash(1))
      .to.emit(monetaryCash, 'MonetaryCashCancelled')
      .withArgs(deployer.address, 1);

    expect(await token.balanceOf(deployer.address)).to.equal(AMOUNT * 2n);
  });

  it('supports native cash payouts', async function () {
    await monetaryCash.connect(deployer).createCash(ethers.ZeroAddress, AMOUNT, 0, { value: AMOUNT });
    const latest = await ethers.provider.getBlock('latest');
    if (!latest) {
      throw new Error('block not found');
    }
    const deadline = BigInt(latest.timestamp + 3600);
    const signature = await signActivation(1n, deadline);

    await expect(
      monetaryCash.connect(caller).activateCashWithSig(1, recipient.address, deadline, signature),
    ).to.emit(monetaryCash, 'MonetaryCashActivated');
  });
});
