import fs from 'fs/promises';
import path from 'path';
import { pathToFileURL } from 'url';
import { ignition, network } from 'hardhat';
import DeploymentModule from '../ignition/modules/deploy';

type DeployArgs = {
  parameterFile?: string;
  deploymentId?: string;
};

const SUPPORTED_PARAM_EXTENSIONS = new Set(['.json', '.js', '.cjs', '.mjs', '.ts']);

function parseArgs(): DeployArgs {
  const args = process.argv.slice(2);
  const result: DeployArgs = {};

  for (let i = 0; i < args.length; i += 1) {
    const current = args[i];

    if (!current.startsWith('--')) {
      continue;
    }

    const [flag, valueFromEquals] = current.split('=', 2);

    switch (flag) {
      case '--params':
      case '--parameters': {
        const value = valueFromEquals ?? args[i + 1];
        if (!value) {
          throw new Error(`Missing value for ${flag}`);
        }
        result.parameterFile = value;
        if (valueFromEquals === undefined) {
          i += 1;
        }
        break;
      }
      case '--name':
      case '--deployment-id':
      case '--deployment-name': {
        const value = valueFromEquals ?? args[i + 1];
        if (!value) {
          throw new Error(`Missing value for ${flag}`);
        }
        result.deploymentId = value;
        if (valueFromEquals === undefined) {
          i += 1;
        }
        break;
      }
      default:
        // Ignore unknown flags to avoid conflicts with Hardhat internals.
        break;
    }
  }

  return result;
}

async function loadParameters(parameterFile?: string): Promise<Record<string, unknown>> {
  if (!parameterFile) {
    return {};
  }

  const resolvedPath = path.isAbsolute(parameterFile)
    ? parameterFile
    : path.join(process.cwd(), parameterFile);

  const extension = path.extname(resolvedPath);
  if (!SUPPORTED_PARAM_EXTENSIONS.has(extension)) {
    throw new Error(`Unsupported parameter file extension: ${extension}`);
  }

  if (extension === '.json') {
    const raw = await fs.readFile(resolvedPath, 'utf8');
    return JSON.parse(raw);
  }

  const module = await import(pathToFileURL(resolvedPath).toString());
  return module.default ?? module;
}

async function logAddress(label: string, contract: { getAddress(): Promise<string> }): Promise<void> {
  const address = await contract.getAddress();
  console.log(`${label}: ${address}`);
}

async function main(): Promise<void> {
  const args = parseArgs();
  const parameters = await loadParameters(args.parameterFile);
  const deploymentId = args.deploymentId ?? `evmfactory-${network.name}`;

  if (Object.keys(parameters).length > 0) {
    console.log(`Using parameters from ${args.parameterFile}`);
  }

  console.log(`Deploying ${deploymentId} to network ${network.name}...`);

  const options = {
    deploymentId,
    ...(Object.keys(parameters).length > 0 ? { parameters } : {}),
  } as const;

  const {
    core,
    paymentRegistry,
    paymentOrchestrator,
    paymentGateway,
    paymentTokenFilter,
    paymentFeeProcessor,
    contestFactory,
    subscriptionManager,
    marketplace,
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
  await logAddress('Marketplace', marketplace);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error('Deployment failed:', error);
    process.exit(1);
  });
