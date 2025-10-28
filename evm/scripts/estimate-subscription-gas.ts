import { ethers } from 'hardhat';

type DeploymentInfo = {
  label: string;
  address: string;
  gasUsed: bigint;
  bytecodeSize: number;
};

async function recordDeployment(label: string, deployTxPromise: Promise<any>): Promise<DeploymentInfo> {
  const contract = await deployTxPromise;
  await contract.waitForDeployment();
  const deploymentTx = contract.deploymentTransaction();
  if (!deploymentTx) {
    throw new Error(`Missing deployment transaction for ${label}`);
  }
  const receipt = await deploymentTx.wait();
  if (!receipt) {
    throw new Error(`Missing receipt for ${label}`);
  }
  const address = await contract.getAddress();
  const bytecode = await ethers.provider.getCode(address);
  return {
    label,
    address,
    gasUsed: receipt.gasUsed,
    bytecodeSize: (bytecode.length - 2) / 2, // hex string -> bytes
  };
}

async function main(): Promise<void> {
  const [deployer] = await ethers.getSigners();
  console.log(`Estimation signer: ${deployer.address}`);

  const moduleId = ethers.id('SubscriptionManager');

  const deployments: DeploymentInfo[] = [];

  const coreDeployment = recordDeployment(
    'CoreSystem',
    ethers.getContractFactory('CoreSystem').then((factory) => factory.deploy(deployer.address)),
  );
  const subscriptionManagerDeployment = coreDeployment.then(async ({ address: coreAddress }) =>
    recordDeployment(
      'SubscriptionManager',
      ethers
        .getContractFactory('SubscriptionManager')
        .then((factory) => factory.deploy(coreAddress, deployer.address, moduleId)),
    ),
  );

  const planManagerDeployment = Promise.all([coreDeployment, subscriptionManagerDeployment]).then(
    async ([coreInfo, subscriptionInfo]) =>
      recordDeployment(
        'PlanManager',
        ethers
          .getContractFactory('PlanManager')
          .then((factory) => factory.deploy(coreInfo.address, subscriptionInfo.address, moduleId, 5)),
      ),
  );

  const factoryDeployment = coreDeployment.then(async ({ address: coreAddress }) =>
    recordDeployment(
      'SubscriptionManagerFactory',
      ethers
        .getContractFactory('SubscriptionManagerFactory')
        .then((factory) => factory.deploy(coreAddress, deployer.address)),
    ),
  );

  deployments.push(await coreDeployment);
  deployments.push(await subscriptionManagerDeployment);
  deployments.push(await planManagerDeployment);
  deployments.push(await factoryDeployment);

  console.log('\nDeployment gas usage (Hardhat network, optimizer enabled):');
  for (const deployment of deployments) {
    console.log(
      `${deployment.label.padEnd(28)} | gasUsed: ${deployment.gasUsed.toString().padStart(10)} | bytecodeSize: ${
        deployment.bytecodeSize
      } bytes`,
    );
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

