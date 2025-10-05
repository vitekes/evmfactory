import { expect } from 'chai';
import { ethers } from 'hardhat';
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs';
import type {
  ContestEscrow,
  ContestFactory,
  ContestValidatorMock,
  CoreSystem,
  NFTManager,
  TestToken,
} from '../../typechain-types';
import { deployGatewayStack } from '../shared/paymentStack';

const PrizeType = {
  MONETARY: 0,
  PROMO: 1,
} as const;

const FEATURE_OWNER_ROLE = ethers.id('FEATURE_OWNER_ROLE');

function toInstanceId(contestId: bigint): string {
  return ethers.zeroPadValue(ethers.toBeHex(contestId), 32);
}

describe('ContestFactory & ContestEscrow', function () {
  let admin: Awaited<ReturnType<typeof ethers.getSigners>>[number];
  let creator: Awaited<ReturnType<typeof ethers.getSigners>>[number];
  let other: Awaited<ReturnType<typeof ethers.getSigners>>[number];
  let core: CoreSystem;
  let factory: ContestFactory;
  let tokenA: TestToken;
  let validator: ContestValidatorMock;
  let nftManager: NFTManager;

  beforeEach(async function () {
    [admin, creator, other] = await ethers.getSigners();

    const Core = await ethers.getContractFactory('CoreSystem', admin);
    core = (await Core.deploy(admin.address)) as CoreSystem;

    const { gateway } = await deployGatewayStack(admin);

    const Factory = await ethers.getContractFactory('ContestFactory', admin);
    factory = (await Factory.deploy(await core.getAddress(), await gateway.getAddress())) as ContestFactory;
    await factory.waitForDeployment();

    const Token = await ethers.getContractFactory('TestToken', admin);
    tokenA = (await Token.deploy('ContestToken', 'CTK', 18, 0)) as TestToken;
    await tokenA.mint(creator.address, ethers.parseEther('1000'));

    const ValidatorMock = await ethers.getContractFactory('ContestValidatorMock', admin);
    validator = (await ValidatorMock.deploy(false)) as ContestValidatorMock;

    const NFT = await ethers.getContractFactory('NFTManager', admin);
    nftManager = (await NFT.deploy('ContestNFT', 'CNT')) as NFTManager;

    await core.connect(admin).grantRole(FEATURE_OWNER_ROLE, admin.address);
    await core.connect(admin).grantRole(FEATURE_OWNER_ROLE, creator.address);
    await core.connect(admin).grantRole(FEATURE_OWNER_ROLE, await factory.getAddress());

    await core.connect(admin).registerFeature(await factory.MODULE_ID(), await factory.getAddress(), 0);

    await core.connect(admin).setService(await factory.MODULE_ID(), 'Validator', await validator.getAddress());
    await core.connect(admin).setService(await factory.MODULE_ID(), 'NFTManager', await nftManager.getAddress());
  });

  async function createContest(
    prizes: ContestFactory.PrizeInfoStruct[],
  ): Promise<{ escrow: ContestEscrow; instanceId: string; contestId: bigint }> {
    const predictedEscrow = await factory.connect(creator).createContest.staticCall(prizes, '0x');
    const tx = await factory.connect(creator).createContest(prizes, '0x');
    const receipt = await tx.wait();

    const event = receipt?.logs
      .map((log) => {
        try {
          return factory.interface.parseLog(log);
        } catch (error) {
          return null;
        }
      })
      .find((parsed) => parsed?.name === 'ContestCreated');

    if (!event) {
      throw new Error('ContestCreated event not emitted');
    }

    const contestId = event.args.contestId as bigint;
    const instanceId = toInstanceId(contestId);
    const escrow = (await ethers.getContractAt('ContestEscrow', predictedEscrow)) as ContestEscrow;
    return { escrow, instanceId, contestId };
  }

  it('creates contest escrow and locks monetary prize', async function () {
    const prizes: ContestFactory.PrizeInfoStruct[] = [
      {
        prizeType: PrizeType.MONETARY,
        token: await tokenA.getAddress(),
        amount: ethers.parseEther('100'),
        distribution: 0,
        uri: '',
      },
      {
        prizeType: PrizeType.PROMO,
        token: ethers.ZeroAddress,
        amount: 0n,
        distribution: 0,
        uri: 'ipfs://promo',
      },
    ];

    await tokenA.connect(creator).approve(await factory.getAddress(), prizes[0].amount);

    const { escrow } = await createContest(prizes);

    expect(await tokenA.balanceOf(await escrow.getAddress())).to.equal(prizes[0].amount);
    expect(await escrow.finalized()).to.equal(false);
  });

  it('reverts when prize batch exceeds ERC-20 limit', async function () {
    const maxTokens = 21;
    const prizes: ContestFactory.PrizeInfoStruct[] = [];

    for (let i = 0; i < maxTokens; i++) {
      const Token = await ethers.getContractFactory('TestToken', admin);
      const token = (await Token.deploy(`Token${i}`, `TK${i}`, 18, 0)) as TestToken;
      await token.mint(creator.address, ethers.parseEther('10'));
      await token.connect(creator).approve(await factory.getAddress(), ethers.parseEther('1'));
      prizes.push({
        prizeType: PrizeType.MONETARY,
        token: await token.getAddress(),
        amount: ethers.parseEther('1'),
        distribution: 0,
        uri: '',
      });
    }

    await expect(factory.connect(creator).createContest(prizes, '0x')).to.be.revertedWithCustomError(
      factory,
      'BatchTooLarge',
    );
  });

  it('finalizes contest and distributes monetary prize', async function () {
    const amount = ethers.parseEther('90');
    const prizes: ContestFactory.PrizeInfoStruct[] = [
      {
        prizeType: PrizeType.MONETARY,
        token: await tokenA.getAddress(),
        amount,
        distribution: 0,
        uri: '',
      },
      {
        prizeType: PrizeType.PROMO,
        token: ethers.ZeroAddress,
        amount: 0n,
        distribution: 0,
        uri: 'ipfs://badge',
      },
    ];

    await tokenA.connect(creator).approve(await factory.getAddress(), amount);
    const { escrow } = await createContest(prizes);
    await nftManager.connect(admin).transferOwnership(await escrow.getAddress());

    const winners = [other.address, creator.address];

    await expect(escrow.connect(creator).finalize(winners, 0)).to.emit(escrow, 'ContestFinalized');

    expect(await escrow.finalized()).to.equal(true);
    expect(await tokenA.balanceOf(winners[0])).to.equal(ethers.parseEther('90'));
  });

  it('registers contest services in CoreSystem', async function () {
    const amount = ethers.parseEther('50');
    const prizes: ContestFactory.PrizeInfoStruct[] = [
      {
        prizeType: PrizeType.MONETARY,
        token: await tokenA.getAddress(),
        amount,
        distribution: 0,
        uri: '',
      },
    ];

    await tokenA.connect(creator).approve(await factory.getAddress(), amount);
    const { escrow, instanceId } = await createContest(prizes);

    const [implementation, context] = await core.getFeature(instanceId);
    expect(implementation).to.equal(await escrow.getAddress());
    expect(context).to.equal(0);

    expect(await core.getService(instanceId, 'Validator')).to.equal(await validator.getAddress());
    expect(await core.getService(instanceId, 'NFTManager')).to.equal(await nftManager.getAddress());
  });
});
