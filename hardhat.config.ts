import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "hardhat-gas-reporter"
import "@nomiclabs/hardhat-etherscan";

require("dotenv").config();

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.17",
    settings: {
      optimizer: {
        enabled: true,
        runs: 1000,
      },
      viaIR: true
    },
  },
  gasReporter: {
    enabled: process.env.GAS_REPORTER ? true : false,
    currency: 'USD',
    gasPrice: 45,
    coinmarketcap: '54e57674-6e99-404b-8528-cbf6a9f1e471'
  },
  networks: {
    goerli: {
      url: `https://eth-goerli.alchemyapi.io/v2/${process.env.ALCHEMY_API_KEY}`,
      accounts: [`0x${process.env.PRIVATE_KEY}`],
    },
    harmonyTestnet: {
      url: `https://api.s0.b.hmny.io/`,
      accounts: [`0x${process.env.PRIVATE_KEY}`],
    }
  },
  etherscan: {
    apiKey: {
      harmonyTest: process.env.ETHERSCAN_API_KEY!
    }
  }
};

export default config;
