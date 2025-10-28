import path from "path";
import fs from "fs";
import TronWeb from "tronweb";
import dotenv from "dotenv";
import { ensureDir } from "fs-extra";

dotenv.config();

interface CliArgs {
  artifact?: string;
  args?: string;
  argsFile?: string;
  feeLimit?: string;
  callValue?: string;
  owner?: string;
  save?: string;
  _: string[];
}

function parseArgs(argv: string[]): CliArgs {
  const result: CliArgs = { _: [] };

  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith("--")) {
      result._.push(token);
      continue;
    }

    const key = token.slice(2);
    const next = argv[i + 1];
    if (!next || next.startsWith("--")) {
      (result as any)[key] = "true";
      continue;
    }

    (result as any)[key] = next;
    i += 1;
  }

  return result;
}

function parseParameters(value?: string, positional: string[] = []): unknown[] {
  if (value) {
    const trimmed = value.trim();
    if (trimmed) {
      try {
        const parsed = JSON.parse(trimmed);
        if (Array.isArray(parsed)) {
          return parsed;
        }
      } catch (error) {
        // fall back to comma-separated parsing below
      }
      return trimmed.split(",").map((entry) => entry.trim()).filter((entry) => entry.length > 0);
    }
  }

  return positional;
}

function ensureHexPrefix(hex: string): string {
  return hex.startsWith("0x") ? hex : `0x${hex}`;
}

async function main(): Promise<void> {
  const projectRoot = path.resolve(__dirname, "..");
  const args = parseArgs(process.argv.slice(2));

  const artifactRelativePath = args.artifact ?? args._[0];
  if (!artifactRelativePath) {
    throw new Error(
      "Artifact path is required. Pass --artifact path_relative_to_artifacts/ or provide it as the first positional argument.",
    );
  }

  const artifactPath = path.isAbsolute(artifactRelativePath)
    ? artifactRelativePath
    : path.join(projectRoot, "artifacts", artifactRelativePath);

  if (!fs.existsSync(artifactPath)) {
    throw new Error(`Artifact not found at ${artifactPath}`);
  }

  const artifact = JSON.parse(fs.readFileSync(artifactPath, "utf8"));
  const abi = artifact.abi ?? [];
  const bytecode: string = artifact.bytecode ?? "";

  if (!bytecode || bytecode === "0x") {
    throw new Error("Artifact does not contain deployable bytecode");
  }

  const privateKey = process.env.TRON_PRIVATE_KEY;
  if (!privateKey) {
    throw new Error("TRON_PRIVATE_KEY is not set in the environment");
  }

  const fullNode = process.env.TRON_FULL_NODE ?? "https://api.shasta.trongrid.io";
  const solidityNode = process.env.TRON_SOLIDITY_NODE ?? fullNode;
  const eventServer = process.env.TRON_EVENT_SERVER ?? fullNode;
  const apiKey = process.env.TRON_API_KEY;

  const tronConfig: Record<string, unknown> = {
    fullNode,
    solidityNode,
    eventServer,
    privateKey,
  };

  if (apiKey) {
    tronConfig.headers = { "TRON-PRO-API-KEY": apiKey };
  }

  const tronWeb = new TronWeb(tronConfig);

  const ownerAddress = args.owner
    ?? process.env.TRON_OWNER_ADDRESS
    ?? tronWeb.address.fromPrivateKey(privateKey);

  const feeLimit = args.feeLimit
    ? Number(args.feeLimit)
    : Number(process.env.TRON_FEE_LIMIT ?? 1_000_000_000);
  const callValue = args.callValue
    ? Number(args.callValue)
    : Number(process.env.TRON_CALL_VALUE ?? 0);

  let rawParameters: unknown[] = parseParameters(args.args, args._.slice(1));
  if (args.argsFile) {
    const argsFilePath = path.isAbsolute(args.argsFile)
      ? args.argsFile
      : path.join(projectRoot, args.argsFile);

    if (!fs.existsSync(argsFilePath)) {
      throw new Error(`Arguments file not found at ${argsFilePath}`);
    }

    const fileContent = JSON.parse(fs.readFileSync(argsFilePath, "utf8"));
    if (Array.isArray(fileContent)) {
      rawParameters = fileContent;
    } else if (Array.isArray(fileContent.args)) {
      rawParameters = fileContent.args;
    } else if (Array.isArray(fileContent.parameters)) {
      rawParameters = fileContent.parameters;
    } else {
      throw new Error("Arguments file must contain an array or an object with an 'args' or 'parameters' array");
    }
  }

  const parameters = rawParameters.map((param) => {
    if (typeof param === "string") {
      const trimmed = param.trim();
      if (/^T[1-9A-HJ-NP-Za-km-z]{33}$/u.test(trimmed)) {
        return tronWeb.address.toHex(trimmed);
      }
      if (/^[0-9a-fA-F]{40}$/u.test(trimmed)) {
        return ensureHexPrefix(trimmed);
      }
      if (/^0x[0-9a-fA-F]+$/u.test(trimmed)) {
        return trimmed;
      }
    }
    return param;
  });

  console.log("Preparing deployment with configuration:");
  console.log(` - artifact: ${path.relative(projectRoot, artifactPath)}`);
  console.log(` - owner:   ${ownerAddress}`);
  console.log(` - feeLimit: ${feeLimit}`);
  console.log(` - callValue: ${callValue}`);
  console.log(` - parameters: ${JSON.stringify(parameters)}`);

  const sanitizedBytecode = ensureHexPrefix(bytecode).slice(2);

  const contract = await tronWeb.contract().new({
    abi,
    bytecode: sanitizedBytecode,
    feeLimit,
    callValue,
    parameters,
    userFeePercentage: 0,
    originEnergyLimit: 0,
    from: ownerAddress,
  });

  const deploymentInfo = {
    contractName: artifact.contractName,
    sourceName: artifact.sourceName,
    address: contract.address,
    transactionId: (contract as any).transactionHash ?? (contract as any)._transaction?.txID,
    network: {
      fullNode,
      solidityNode,
      eventServer,
    },
    deployedAt: new Date().toISOString(),
    parameters,
    owner: ownerAddress,
  };

  console.log("Contract deployed successfully:");
  console.log(` - address: ${deploymentInfo.address}`);
  if (deploymentInfo.transactionId) {
    console.log(` - transaction: ${deploymentInfo.transactionId}`);
  }

  if (args.save) {
    const savePath = path.isAbsolute(args.save) ? args.save : path.join(projectRoot, args.save);
    await ensureDir(path.dirname(savePath));
    fs.writeFileSync(savePath, JSON.stringify(deploymentInfo, null, 2));
    console.log(`Deployment info saved to ${savePath}`);
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
