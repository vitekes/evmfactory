import fs from 'fs/promises';
import path from 'path';
import { pathToFileURL } from 'url';
import { ignition, network } from 'hardhat';
import type { DeploymentParameters } from '@nomicfoundation/ignition-core';
import DeploymentModule from '../ignition/modules/deploy';

type DeployConfig = {
  parameterFile?: string;
  deploymentId?: string;
};

const SUPPORTED_PARAM_EXTENSIONS = new Set(['.json', '.js', '.cjs', '.mjs', '.ts']);

function readEnvConfig(): DeployConfig {
  return {
    parameterFile: process.env.DEPLOY_PARAMS ?? process.env.DEPLOY_PARAMETERS ?? undefined,
    deploymentId: process.env.DEPLOY_ID ?? process.env.DEPLOYMENT_ID ?? undefined,
  };
}

function mergeCliArgs(config: DeployConfig): DeployConfig {
  const args = process.argv.slice(2);
  const result: DeployConfig = { ...config };

  for (let i = 0; i < args.length; i += 1) {
    const current = args[i];
    if (!current.startsWith('--')) {
      continue;
    }

    const [flag, valueFromEquals] = current.split('=', 2);
    const value = valueFromEquals ?? args[i + 1];

    switch (flag) {
      case '--params':
      case '--parameters':
        if (value) {
          result.parameterFile = value;
          if (valueFromEquals === undefined) {
            i += 1;
          }
        }
        break;
      case '--name':
      case '--deployment-id':
      case '--deployment-name':
        if (value) {
          result.deploymentId = value;
          if (valueFromEquals === undefined) {
            i += 1;
          }
        }
        break;
      default:
        break;
    }
  }

  return result;
}

async function fileExists(filePath: string): Promise<boolean> {
  try {
    await fs.access(filePath);
    return true;
  } catch {
    return false;
  }
}

async function resolveParameterPath(config: DeployConfig, networkName: string): Promise<string | undefined> {
  if (config.parameterFile) {
    return config.parameterFile;
  }

  const baseDir = path.join(process.cwd(), 'ignition/parameters');
  const candidates = ['json', 'ts', 'cjs', 'mjs'].map((ext) => path.join(baseDir, `${networkName}.${ext}`));

  for (const candidate of candidates) {
    if (await fileExists(candidate)) {
      return candidate;
    }
  }

  return undefined;
}

async function loadParameters(parameterFile?: string): Promise<DeploymentParameters | undefined> {
  if (!parameterFile) {
    return undefined;
  }

  const resolvedPath = path.isAbsolute(parameterFile) ? parameterFile : path.join(process.cwd(), parameterFile);
  const extension = path.extname(resolvedPath);

  if (!SUPPORTED_PARAM_EXTENSIONS.has(extension)) {
    throw new Error(`Unsupported parameter file extension: ${extension}`);
  }

  if (extension === '.json') {
    const raw = await fs.readFile(resolvedPath, 'utf8');
    return JSON.parse(raw) as DeploymentParameters;
  }

  const loadedModule = await import(pathToFileURL(resolvedPath).toString());
  return (loadedModule.default ?? loadedModule) as DeploymentParameters;
}

async function logAddress(label: string, contract: { getAddress(): Promise<string> }): Promise<void> {
  const address = await contract.getAddress();
  console.log(`${label}: ${address}`);
}

async function main(): Promise<void> {
  const envConfig = readEnvConfig();
  const config = mergeCliArgs(envConfig);
  const networkName = network.name;

  const parameterPath = await resolveParameterPath(config, networkName);
  const parameters = await loadParameters(parameterPath);
  const deploymentId = config.deploymentId ?? `evmfactory-${networkName}`;

  if (parameterPath) {
    console.log(`Using parameters from ${parameterPath}`);
  } else {
    console.log('No parameter file provided; using module defaults.');
  }

  console.log(`Deploying ${deploymentId} to network ${networkName}...`);

  const options: Parameters<typeof ignition.deploy>[1] = parameters
    ? { deploymentId, parameters }
    : { deploymentId };

  const {
    core,
    paymentRegistry,
    paymentOrchestrator,
    paymentGateway,
    paymentTokenFilter,
    paymentFeeProcessor,
    contestFactory,
    subscriptionManager,
    planManager,
    marketplace,
    donate,
  } = await ignition.deploy(DeploymentModule, options);

  console.log('Deployment successful. Contract addresses:');
  await logAddress('CoreSystem', core);
  await logAddress('ProcessorRegistry', paymentRegistry);
  await logAddress('PaymentOrchestrator', paymentOrchestrator);
  await logAddress('PaymentGateway', paymentGateway);
  await logAddress('TokenFilterProcessor', paymentTokenFilter);
  await logAddress('FeeProcessor', paymentFeeProcessor);
  await logAddress('ContestFactory', contestFactory);
  await logAddress('SubscriptionManager', subscriptionManager);
  await logAddress('PlanManager', planManager);
  await logAddress('Marketplace', marketplace);
  await logAddress('Donate', donate);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error('Deployment failed:', error);
    process.exit(1);
  });
