import { HardhatUserConfig, subtask } from "hardhat/config";
import { TASK_COMPILE_SOLIDITY_GET_SOLC_BUILD } from "hardhat/builtin-tasks/task-names";
import path from "path";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-ignition";
import "@typechain/hardhat";

const config: HardhatUserConfig = {
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
            // Встроенная тестовая сеть
            gas: 200000000,
            blockGasLimit: 200000000,
            allowUnlimitedContractSize: true
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
    etherscan: {
        apiKey: process.env.ETHERSCAN_API_KEY || "",
    },
    mocha: {
        timeout: 120000,
        reporter: 'spec'
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
