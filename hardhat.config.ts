import { HardhatUserConfig, subtask } from "hardhat/config";
import { TASK_COMPILE_SOLIDITY_GET_SOLC_BUILD } from "hardhat/builtin-tasks/task-names";
import path from "path";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-ignition";
import "@typechain/hardhat";
import "@nomicfoundation/hardhat-network-helpers";
import "solidity-coverage";
import "hardhat-gas-reporter";

const config: HardhatUserConfig = {
    defaultNetwork: "hardhat",
    paths: {
        tests: "./test/hardhat",
    },
    solidity: {
        version: "0.8.28",
        settings: {
            optimizer: {
                enabled: true,
                runs: 200,
            },
            viaIR: true
        },
    },
    networks: {
        localhost: {
            url: "http://127.0.0.1:8545"
        },
        hardhat: {
            gas: 200000000,
            blockGasLimit: 200000000,
            allowUnlimitedContractSize: true,
            forking: process.env.FORK_URL ? { url: process.env.FORK_URL } : undefined
        },
        sepolia: {
            url: process.env.SEPOLIA_URL || "",
            accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
        },
        mainnet: {
            url: process.env.MAINNET_URL || "",
            accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
        }
    },
    // Явно указываем, что не используем oz-upgrades
    // Это предотвратит попытки компилятора искать upgradeable контракты
    paths: {
      sources: "./contracts",
      cache: "./cache",
      artifacts: "./artifacts"
    },
    etherscan: {
        apiKey: process.env.ETHERSCAN_API_KEY || "",
    },
    mocha: {
        timeout: 120000,
        reporter: 'spec'
    },
    gasReporter: {
        enabled: process.env.REPORT_GAS === 'true',
        currency: 'USD',
        coinmarketcap: process.env.COINMARKETCAP_API_KEY || '',
        outputFile: "gas-report.txt",
        noColors: true,
        showMethodSig: true,
        showTimeSpent: true,
        excludeContracts: ['Migrations'],
    },
    typechain: {
        outDir: "typechain-types",
        target: "ethers-v6",
        alwaysGenerateOverloads: false,
        discriminateTypes: false,
        tsNocheck: false,
        dontOverrideCompile: false
    }
};

export default config;

// Use local solcjs to avoid network download
subtask(TASK_COMPILE_SOLIDITY_GET_SOLC_BUILD).setAction(async ({ solcVersion }) => {
    const solcJsPath = path.join(__dirname, "node_modules", "solc", "soljson.js");
    return {
        compilerPath: solcJsPath,
        isSolcJs: true,
        version: solcVersion,
        longVersion: solcVersion,
    };
});
