import path from "path";
import fs from "fs";
import { emptyDir, ensureDir, writeJson } from "fs-extra";
import { globSync } from "glob";
import solc from "solc";

const projectRoot = path.resolve(__dirname, "..");
const artifactsDir = path.join(projectRoot, "artifacts");
const cacheDir = path.join(projectRoot, "cache");
const tronContractsRoot = path.join(projectRoot, "contracts");
const evmContractsRoot = path.resolve(projectRoot, "..", "evm", "contracts");

const contractRoots = [tronContractsRoot, evmContractsRoot].filter((root) => fs.existsSync(root));
const nodeModuleRoots = [
  path.join(projectRoot, "node_modules"),
  path.resolve(projectRoot, "..", "evm", "node_modules"),
];

function normalizePath(p: string): string {
  return p.replace(/\\/g, "/");
}

type SourceMap = Record<string, { content: string }>;

type ImportCallbackResult = { contents: string } | { error: string };

function createImportResolver(): (importPath: string) => ImportCallbackResult {
  const cache = new Map<string, ImportCallbackResult>();

  return (importPath: string) => {
    if (cache.has(importPath)) {
      return cache.get(importPath)!;
    }

    const normalized = normalizePath(importPath);

    for (const root of [...contractRoots, ...nodeModuleRoots]) {
      const candidate = path.join(root, normalized);
      if (fs.existsSync(candidate) && fs.statSync(candidate).isFile()) {
        const result: ImportCallbackResult = { contents: fs.readFileSync(candidate, "utf8") };
        cache.set(importPath, result);
        return result;
      }
    }

    const errorResult: ImportCallbackResult = { error: `File not found: ${importPath}` };
    cache.set(importPath, errorResult);
    return errorResult;
  };
}

async function buildSources(): Promise<{ sources: SourceMap; originLookup: Map<string, string> }> {
  const sources: SourceMap = {};
  const originLookup = new Map<string, string>();

  for (const root of contractRoots) {
    const matches = globSync("**/*.sol", { cwd: root, nodir: true });
    matches.sort();

    for (const relativePath of matches) {
      const normalizedRelativePath = normalizePath(relativePath);
      const sourceKey = normalizePath(path.posix.join("contracts", normalizedRelativePath));

      if (sources[sourceKey]) {
        continue; // allow Tron-specific overrides to take precedence
      }

      const absolutePath = path.join(root, relativePath);
      const content = fs.readFileSync(absolutePath, "utf8");
      sources[sourceKey] = { content };
      originLookup.set(sourceKey, absolutePath);
    }
  }

  if (Object.keys(sources).length === 0) {
    throw new Error("No Solidity sources found for compilation");
  }

  return { sources, originLookup };
}

async function main(): Promise<void> {
  await ensureDir(artifactsDir);
  await ensureDir(cacheDir);
  await emptyDir(artifactsDir);
  await emptyDir(cacheDir);

  const { sources } = await buildSources();

  const input = {
    language: "Solidity",
    sources,
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      viaIR: true,
      outputSelection: {
        "*": {
          "*": ["abi", "evm.bytecode", "evm.deployedBytecode", "metadata"],
        },
      },
    },
  };

  const importResolver = createImportResolver();
  const rawOutput = solc.compile(JSON.stringify(input), { import: importResolver });
  const output = JSON.parse(rawOutput);

  if (output.errors?.length) {
    const errors = output.errors.filter((entry: any) => entry.severity === "error");
    const warnings = output.errors.filter((entry: any) => entry.severity !== "error");

    for (const warning of warnings) {
      const message = warning.formattedMessage ?? warning.message;
      console.warn(message.trim());
    }

    if (errors.length) {
      for (const error of errors) {
        const message = error.formattedMessage ?? error.message;
        console.error(message.trim());
      }
      throw new Error("Solc reported compilation errors");
    }
  }

  const artifactsWritten: string[] = [];

  for (const [sourceName, contracts] of Object.entries<any>(output.contracts ?? {})) {
    for (const [contractName, contractOutput] of Object.entries<any>(contracts)) {
      const bytecode = contractOutput.evm?.bytecode?.object ?? "";
      if (!bytecode || bytecode === "0x" || bytecode === "0") {
        continue; // skip abstract contracts and interfaces
      }

      const artifactDir = path.join(artifactsDir, normalizePath(sourceName));
      await ensureDir(artifactDir);
      const artifactPath = path.join(artifactDir, `${contractName}.json`);

      const artifact = {
        contractName,
        sourceName: normalizePath(sourceName),
        abi: contractOutput.abi,
        bytecode: bytecode.startsWith("0x") ? bytecode : `0x${bytecode}`,
        deployedBytecode: contractOutput.evm?.deployedBytecode?.object
          ? contractOutput.evm.deployedBytecode.object.startsWith("0x")
            ? contractOutput.evm.deployedBytecode.object
            : `0x${contractOutput.evm.deployedBytecode.object}`
          : "0x",
        linkReferences: contractOutput.evm?.bytecode?.linkReferences ?? {},
        deployedLinkReferences: contractOutput.evm?.deployedBytecode?.linkReferences ?? {},
        metadata: contractOutput.metadata,
      };

      await writeJson(artifactPath, artifact, { spaces: 2 });
      artifactsWritten.push(path.relative(projectRoot, artifactPath));
    }
  }

  await writeJson(path.join(cacheDir, "solc-input.json"), input, { spaces: 2 });
  await writeJson(path.join(cacheDir, "solc-output.json"), output, { spaces: 2 });

  console.log(`Compiled ${artifactsWritten.length} deployable contracts.`);
  if (artifactsWritten.length) {
    console.log("Artifacts written:");
    for (const artifactPath of artifactsWritten) {
      console.log(` - ${artifactPath}`);
    }
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
