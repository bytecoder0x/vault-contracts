import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "dotenv/config";

const { ARBITRUM_SEPOLIA_URL, ARBITRUM_SCANER_KEY, PRIVATE_KEY } = process.env;

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.27",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      },
      viaIR: true
    }
  },
  networks: {
    arbitrumSepolia: {
      url: ARBITRUM_SEPOLIA_URL || "",
      chainId: 421614,
      accounts: [PRIVATE_KEY || ""]
    },
  },
  etherscan: {
    apiKey: {
      arbitrumSepolia: ARBITRUM_SCANER_KEY || ""
    }
  }
};

export default config;
