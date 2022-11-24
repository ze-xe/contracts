import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "hardhat-gas-reporter"

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
    gasPrice: 1.5,
    coinmarketcap: '54e57674-6e99-404b-8528-cbf6a9f1e471'
  }
};

export default config;
