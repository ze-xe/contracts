import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "hardhat-gas-reporter"
import "@nomiclabs/hardhat-etherscan";
import '@openzeppelin/hardhat-upgrades';
import "hardhat-openzeppelin-defender";
import "@openzeppelin/hardhat-defender"

require("dotenv").config();

const PRIVATE_KEY = process.env.PRIVATE_KEY ?? 'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.17",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      viaIR: true
    },
  },
  gasReporter: {
    enabled: process.env.GAS_REPORTER ? true : false,
    currency: 'USD',
    gasPrice: 0.1,
    coinmarketcap: '54e57674-6e99-404b-8528-cbf6a9f1e471'
  },
  networks: {
    arbitrumGoerli: {
      url: 'https://nd-389-970-162.p2pify.com/17b0fbe8312c9ff963057d537b9c7864', // 'https://goerli-rollup.arbitrum.io/rpc', // `https://arb-goerli.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
      accounts: [`0x${PRIVATE_KEY}`],
      chainId: 421613,
    }
  },
  etherscan: {
    apiKey: {
      harmonyTest: process.env.ETHERSCAN_API_KEY!,
      arbitrumGoerli: process.env.ARBISCAN_API_KEY!,
    }
  },
  defender: {
    apiKey: process.env.DEFENDER_TEAM_API_KEY!,
    apiSecret: process.env.DEFENDER_TEAM_API_SECRET_KEY!,
  },
  OpenzeppelinDefenderCredential: {
    apiKey: process.env.DEFENDER_TEAM_API_KEY!,
    apiSecret: process.env.DEFENDER_TEAM_API_SECRET_KEY!,
  },
};

export default config;
