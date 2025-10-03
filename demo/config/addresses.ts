import { config as loadEnv } from 'dotenv';
import path from 'path';
import fs from 'fs';
import hre from 'hardhat';
import DeploymentModule from '../../ignition/modules/deploy';

loadEnv({ path: path.resolve(process.cwd(), '.env.demo'), override: true });

export interface DemoAddresses {
  core: string;
  paymentGateway: string;
  processorRegistry: string;
  paymentTokenFilter?: string;
  paymentFeeProcessor?: string;
  contestFactory: string;
  subscriptionManager: string;
  testToken?: string;
}

const CACHE_PATH = path.resolve(process.cwd(), 'demo/.deployment.json');
let cached: DemoAddresses | null = null;

async function isDeployed(address: string | undefined): Promise<boolean> {
  if (!address) return true;
  const code = await hre.ethers.provider.getCode(address);
  return code !== '0x' && code !== '0x0';
}

async function verifyAddresses(addresses: DemoAddresses): Promise<boolean> {
  const checks = [
    addresses.core,
    addresses.paymentGateway,
    addresses.processorRegistry,
    addresses.contestFactory,
    addresses.subscriptionManager,
    addresses.paymentTokenFilter,
    addresses.paymentFeeProcessor,
  ];
  for (const addr of checks) {
    if (!(await isDeployed(addr))) {
      return false;
    }
  }
  return true;
}

function readEnvAddresses(): DemoAddresses | null {
  const requiredKeys = [
    'DEMO_CORE',
    'DEMO_PAYMENT_GATEWAY',
    'DEMO_PR_REGISTRY',
    'DEMO_CONTEST_FACTORY',
    'DEMO_SUBSCRIPTION_MANAGER',
  ] as const;

  const values: Partial<Record<string, string>> = {};
  for (const key of requiredKeys) {
    const value = process.env[key];
    if (!value) {
      return null;
    }
    values[key] = value;
  }

  const optionalToken = process.env.DEMO_TEST_TOKEN;
  const optionalFilter = process.env.DEMO_TOKEN_FILTER;
  const optionalFee = process.env.DEMO_FEE_PROCESSOR;

  return {
    core: values.DEMO_CORE!,
    paymentGateway: values.DEMO_PAYMENT_GATEWAY!,
    processorRegistry: values.DEMO_PR_REGISTRY!,
    paymentTokenFilter: optionalFilter || undefined,
    paymentFeeProcessor: optionalFee || undefined,
    contestFactory: values.DEMO_CONTEST_FACTORY!,
    subscriptionManager: values.DEMO_SUBSCRIPTION_MANAGER!,
    testToken: optionalToken || undefined,
  };
}

function readCache(): DemoAddresses | null {
  if (!fs.existsSync(CACHE_PATH)) {
    return null;
  }
  try {
    const raw = fs.readFileSync(CACHE_PATH, 'utf-8');
    return JSON.parse(raw) as DemoAddresses;
  } catch {
    return null;
  }
}

function writeCache(addresses: DemoAddresses) {
  try {
    fs.writeFileSync(CACHE_PATH, JSON.stringify(addresses, null, 2), 'utf-8');
  } catch {
    // ignore cache write errors
  }
}

async function deployWithIgnition(): Promise<DemoAddresses> {
  const deployment = await hre.ignition.deploy(DeploymentModule, {
    deploymentId: 'demo',
  });

  return {
    core: await deployment.core.getAddress(),
    paymentGateway: await deployment.paymentGateway.getAddress(),
    processorRegistry: await deployment.paymentRegistry.getAddress(),
    paymentTokenFilter: await deployment.paymentTokenFilter.getAddress(),
    paymentFeeProcessor: await deployment.paymentFeeProcessor.getAddress(),
    contestFactory: await deployment.contestFactory.getAddress(),
    subscriptionManager: await deployment.subscriptionManager.getAddress(),
  };
}

export async function getDemoAddresses(): Promise<DemoAddresses> {
  if (cached && (await verifyAddresses(cached))) {
    return cached;
  }

  const envAddresses = readEnvAddresses();
  if (envAddresses && (await verifyAddresses(envAddresses))) {
    cached = envAddresses;
    return envAddresses;
  }

  const cachedAddresses = readCache();
  if (cachedAddresses && (await verifyAddresses(cachedAddresses))) {
    cached = cachedAddresses;
    return cachedAddresses;
  }

  const deployed = await deployWithIgnition();
  writeCache(deployed);
  cached = deployed;
  return deployed;
}
