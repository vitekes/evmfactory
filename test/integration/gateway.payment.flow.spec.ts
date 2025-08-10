const { expect } = require('chai');
const { ethers } = require('hardhat');

describe('Payment flow (integration)', function () {
  it('processes native token payment when not paused; reverts when paused', async function () {
    const [deployer, user] = await ethers.getSigners();

    // Deploy minimal stack: Registry -> Orchestrator -> Gateway
    const Registry = await ethers.getContractFactory('ProcessorRegistry', deployer);
    const registry = await Registry.deploy();

    const Orchestrator = await ethers.getContractFactory('PaymentOrchestrator', deployer);
    const orchestrator = await Orchestrator.deploy(await registry.getAddress());

    const Gateway = await ethers.getContractFactory('PaymentGateway', deployer);
    const gateway = await Gateway.deploy(await orchestrator.getAddress());
import { expect } from 'chai';
import { ethers } from 'hardhat';

describe('Payment flow (integration)', function () {
  it('processes native token payment when not paused; reverts when paused', async function () {
    const [deployer, user] = await ethers.getSigners();

    const Registry = await ethers.getContractFactory('ProcessorRegistry', deployer);
    const registry = await Registry.deploy();

    const Orchestrator = await ethers.getContractFactory('PaymentOrchestrator', deployer);
    const orchestrator = await Orchestrator.deploy(await registry.getAddress());

    const Gateway = await ethers.getContractFactory('PaymentGateway', deployer);
    const gateway = await Gateway.deploy(await orchestrator.getAddress());

    const moduleId = ethers.id('DEMO_MODULE');
    const amount = ethers.parseEther('0.05');

    // Успешная оплата вне паузы
    await expect(
      gateway
        .connect(user)
        .processPayment(moduleId, ethers.ZeroAddress, user.address, amount, '0x', { value: amount }),
    ).to.emit(gateway, 'PaymentProcessed');

    // Пауза и проверка блокировки
    await gateway.connect(deployer).pauseGateway();
    await expect(
      gateway
        .connect(user)
        .processPayment(moduleId, ethers.ZeroAddress, user.address, amount, '0x', { value: amount }),
    ).to.be.revertedWithCustomError(gateway, 'EnforcedPause');

    // Снятие паузы и повторная успешная оплата
    await gateway.connect(deployer).unpauseGateway();
    await expect(
      gateway
        .connect(user)
        .processPayment(moduleId, ethers.ZeroAddress, user.address, amount, '0x', { value: amount }),
    ).to.emit(gateway, 'PaymentProcessed');
  });
});
    const moduleId = ethers.id('DEMO_MODULE');
    const amount = ethers.parseEther('0.05');

    // Happy path (not paused)
    const tx = await gateway
      .connect(user)
      .processPayment(moduleId, ethers.ZeroAddress, user.address, amount, '0x', { value: amount });
    await expect(tx).to.emit(gateway, 'PaymentProcessed');

    // Pause and verify it blocks
    await gateway.connect(deployer).pause();
    await expect(
      gateway
        .connect(user)
        .processPayment(moduleId, ethers.ZeroAddress, user.address, amount, '0x', { value: amount }),
    ).to.be.revertedWithCustomError(gateway, 'EnforcedPause');

    // Unpause and ensure it works again
    await gateway.connect(deployer).unpause();
    await expect(
      gateway
        .connect(user)
        .processPayment(moduleId, ethers.ZeroAddress, user.address, amount, '0x', { value: amount }),
    ).to.emit(gateway, 'PaymentProcessed');
  });
});
