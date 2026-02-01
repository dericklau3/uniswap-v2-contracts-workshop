import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import 'solidity-docgen';
import "hardhat-contract-sizer"
import "hardhat-storage-layout-json";
import 'dotenv/config';
import "@nomicfoundation/hardhat-foundry";

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.6.6",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        },
      },
      {
        version: "0.5.16",
        settings: {
          evmVersion: "istanbul",
          optimizer: {
            enabled: true,
            runs: 200
          }
        },
      },
      {
        version: "0.4.19",
      },
    ]
  },
  networks: {
    bsctest: {
      url: `${process.env.BSCTEST_NETWORK}`,
      chainId: 97,
      accounts: [`${process.env.PRIVATEKEY}`]
    },
    sepolia: {
      url: `${process.env.SEPOLIA_NETWORK}`,
      chainId: 11155111,
      accounts: [`${process.env.PRIVATEKEY}`]
    },
    base_sepolia: {
      url: `${process.env.BASE_SEPOLIA_NETWORK}`,
      chainId: 84532,
      accounts: [`${process.env.PRIVATEKEY}`]
    }
  },
  contractSizer: {
    alphaSort: true,
    disambiguatePaths: false,
    runOnCompile: false,
    strict: true,
  }
};

export default config;