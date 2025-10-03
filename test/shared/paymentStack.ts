import { ethers } from 'hardhat';
import type { Signer } from 'ethers';
import type {
  PaymentGateway,
  PaymentOrchestrator,
  ProcessorRegistry,
  TestToken,
} from '../../typechain-types';

export interface GatewayStack {
  registry: ProcessorRegistry;
  orchestrator: PaymentOrchestrator;
  gateway: PaymentGateway;
}

export async function deployGatewayStack(deployer?: Signer): Promise<GatewayStack> {
  const signer = deployer ?? (await ethers.getSigners())[0];

  const Registry = await ethers.getContractFactory('ProcessorRegistry', signer);
  const registry = (await Registry.deploy()) as ProcessorRegistry;

  const Orchestrator = await ethers.getContractFactory('PaymentOrchestrator', signer);
  const orchestrator = (await Orchestrator.deploy(await registry.getAddress())) as PaymentOrchestrator;

  const Gateway = await ethers.getContractFactory('PaymentGateway', signer);
  const gateway = (await Gateway.deploy(await orchestrator.getAddress())) as PaymentGateway;

  return { registry, orchestrator, gateway };
}

export async function deployTestToken(
  signer: Signer,
  name = 'Test Token',
  symbol = 'TEST',
  decimals = 18,
  supply = 0n,
): Promise<TestToken> {
  const Token = await ethers.getContractFactory('TestToken', signer);
  const token = (await Token.deploy(name, symbol, decimals, supply)) as TestToken;
  return token;
}
