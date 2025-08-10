import {expect} from 'chai';
import {ethers} from 'hardhat';


describe('PaymentOrchestrator - Pausable (unit)', function () {
    it('only PAUSER_ROLE can pause/unpause; paused orchestrator blocks processing', async function () {
        const [deployer, user, other] = await ethers.getSigners();

        const Registry = await ethers.getContractFactory('ProcessorRegistry', deployer);
        const registry = await Registry.deploy();

        const Orchestrator = await ethers.getContractFactory('PaymentOrchestrator', deployer);
        const orchestrator = await Orchestrator.deploy(await registry.getAddress());

        await expect(orchestrator.connect(other).pause())
            .to.be.revertedWithCustomError(orchestrator, 'AccessControlUnauthorizedAccount');

        await expect(orchestrator.connect(deployer).pause()).to.emit(orchestrator, 'Paused');

        const moduleId = ethers.id('DEMO_MODULE');
        const amount = ethers.parseEther('0.02');

        await expect(
            orchestrator.connect(user).processPayment(moduleId, ethers.ZeroAddress, user.address, amount, '0x'),
        ).to.be.revertedWithCustomError(orchestrator, 'EnforcedPause');

        await expect(orchestrator.connect(deployer).unpause()).to.emit(orchestrator, 'Unpaused');

        await expect(
            orchestrator.connect(user).processPayment(moduleId, ethers.ZeroAddress, user.address, amount, '0x'),
        ).to.not.be.reverted;
    });
});
