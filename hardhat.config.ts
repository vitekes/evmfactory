import { defineConfig } from "hardhat/config";
import path from "path";
import { fileURLToPath } from "url";
import hardhatEthers from "@nomicfoundation/hardhat-ethers";
import hardhatEthersChaiMatchers from "@nomicfoundation/hardhat-ethers-chai-matchers";
import hardhatIgnition from "@nomicfoundation/hardhat-ignition";
import hardhatIgnitionEthers from "@nomicfoundation/hardhat-ignition-ethers";
import hardhatMocha from "@nomicfoundation/hardhat-mocha";
import hardhatNetworkHelpers from "@nomicfoundation/hardhat-network-helpers";
import hardhatVerify from "@nomicfoundation/hardhat-verify";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const solcJsPath = path.join(__dirname, "node_modules", "solc", "soljson.js");
const sepoliaUrl = process.env.SEPOLIA_URL;
const mainnetUrl = process.env.MAINNET_URL;
const deployAccounts = process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [];

const config = defineConfig({
    plugins: [
        hardhatEthers,
        hardhatEthersChaiMatchers,
        hardhatIgnition,
        hardhatIgnitionEthers,
        hardhatMocha,
        hardhatNetworkHelpers,
        hardhatVerify
    ],
    defaultNetwork: "hardhat",
    paths: {
        tests: "./test",
        sources: "./contracts",
        cache: "./cache",
        artifacts: "./artifacts"
    },
    solidity: {
        version: "0.8.28",
        path: solcJsPath,
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
            type: "http",
            url: "http://127.0.0.1:8545"
        },
        hardhat: {
            type: "edr-simulated",
            gas: "auto",
            blockGasLimit: 16777216,
            allowUnlimitedContractSize: true,
            forking: process.env.FORK_URL ? { url: process.env.FORK_URL } : undefined
        },
        ...(sepoliaUrl
            ? {
                  sepolia: {
                      type: "http",
                      url: sepoliaUrl,
                      accounts: deployAccounts,
                  }
              }
            : {}),
        ...(mainnetUrl
            ? {
                  mainnet: {
                      type: "http",
                      url: mainnetUrl,
                      accounts: deployAccounts,
                  }
              }
            : {})
    },
    etherscan: {
        apiKey: process.env.ETHERSCAN_API_KEY || "",
    },
    test: {
        mocha: {
            timeout: 120000,
            reporter: "spec"
        }
    },
});

export default config;

