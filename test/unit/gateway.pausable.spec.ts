import { expect } from 'chai';
import { ethers, run } from 'hardhat';

describe('PaymentGateway - Pausable (unit)', function () {
  before(async () => {
    // Обеспечиваем актуальность артефактов (ABI с методами pause/unpause)
    await run('compile');
  });

  it('only PAUSER_ROLE can pause/unpause; paused gateway blocks payments', async function () {
    const [deployer, user, other] = await ethers.getSigners();

    const Registry = await ethers.getContractFactory('ProcessorRegistry', deployer);
    const registry = await Registry.deploy();

    const Orchestrator = await ethers.getContractFactory('PaymentOrchestrator', deployer);
    const orchestrator = await Orchestrator.deploy(await registry.getAddress());

    const Gateway = await ethers.getContractFactory('PaymentGateway', deployer);
    const gateway = await Gateway.deploy(await orchestrator.getAddress());

    // Не-пользователь с ролью паузы не может паузить
    await expect(gateway.connect(other).pause())
      .to.be.revertedWithCustomError(gateway, 'AccessControlUnauthorizedAccount');

    // Деплойер может паузить
    await expect(gateway.connect(deployer).pause()).to.emit(gateway, 'Paused');

    const moduleId = ethers.id('DEMO_MODULE');
    const amount = ethers.parseEther('0.01');

    // В паузе платёж отклоняется
    await expect(
      gateway
        .connect(user)
        .processPayment(moduleId, ethers.ZeroAddress, user.address, amount, '0x', { value: amount }),
    ).to.be.revertedWithCustomError(gateway, 'EnforcedPause');

    // Снимаем паузу
    await expect(gateway.connect(deployer).unpause()).to.emit(gateway, 'Unpaused');

    // Теперь платёж проходит и эмитится событие
    await expect(
      gateway
        .connect(user)
        .processPayment(moduleId, ethers.ZeroAddress, user.address, amount, '0x', { value: amount }),
    ).to.emit(gateway, 'PaymentProcessed');
  });
});
