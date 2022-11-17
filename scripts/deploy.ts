import { Contract } from "ethers";
import { ethers } from "hardhat";

interface Deployments {
  system: Contract;
  vault: Contract;
  exchange: Contract;
  lever: Contract;
  eth: Contract;
  ethOracle: Contract;
  btc: Contract;
  btcOracle: Contract;
  usdc: Contract;
  usdcOracle: Contract;
  irm: Contract;
}

export async function deploy(logs = false): Promise<Deployments> {
  /* -------------------------------------------------------------------------- */
  /*                                   System                                   */
  /* -------------------------------------------------------------------------- */
  const System = await ethers.getContractFactory("System");
  const system = await System.deploy();
  await system.deployed();

  /* -------------------------------------------------------------------------- */
  /*                                    Vault                                   */
  /* -------------------------------------------------------------------------- */
  const Vault = await ethers.getContractFactory("Vault");
  const vault = await Vault.deploy(system.address);
  await vault.deployed();

  if(logs) console.log("Vault deployed to:", vault.address);
  await system.setVault(vault.address);
  
  
  /* -------------------------------------------------------------------------- */
  /*                                  Exchange                                  */
  /* -------------------------------------------------------------------------- */
  const Exchange = await ethers.getContractFactory("Exchange");
  const exchange = await Exchange.deploy(system.address);
  await exchange.deployed();
  
  if(logs) console.log("Exchanger deployed to:", exchange.address);
  await system.setExchange(exchange.address)

  /* -------------------------------------------------------------------------- */
  /*                                    Lever                                   */
  /* -------------------------------------------------------------------------- */
  const Lever = await ethers.getContractFactory("Lever");
  const lever = await Lever.deploy(system.address);
  await lever.deployed();

  if(logs) console.log("Lever deployed to:", lever.address);
  await system.setLever(lever.address);

  /* -------------------------------------------------------------------------- */
  /*                                    Tokens                                  */
  /* -------------------------------------------------------------------------- */
  const ERC20 = await ethers.getContractFactory("TestERC20");
  const PriceOracle = await ethers.getContractFactory("PriceOracle");
  const InterestRateModel = await ethers.getContractFactory("InterestRateModel");

  const eth = await ERC20.deploy("ETH", "ETH");
  await eth.deployed();
  const ethOracle = await PriceOracle.deploy(ethers.utils.parseEther('1000'));
  await ethOracle.deployed();
  if(logs) console.log("ETH deployed to:", eth.address);

  const btc = await ERC20.deploy("BTC", "BTC");
  await btc.deployed();
  const btcOracle = await PriceOracle.deploy(ethers.utils.parseEther('100000'));
  await btcOracle.deployed();
  if(logs) console.log("BTC deployed to:", btc.address);

  const usdc = await ERC20.deploy("USDC", "USDC");
  await usdc.deployed();
  const usdcOracle = await PriceOracle.deploy(ethers.utils.parseEther('1'));
  await usdcOracle.deployed();
  if(logs) console.log("USDC deployed to:", usdc.address);

  const irm = await InterestRateModel.deploy(ethers.utils.parseEther('0.05'), ethers.utils.parseEther('0.05'));
  
  await exchange.updateMinToken0Amount(eth.address, usdc.address, ethers.utils.parseEther('0.001'))
  await exchange.updateMinToken0Amount(btc.address, usdc.address, ethers.utils.parseEther('0.0001'))
  await exchange.updateExchangeRateDecimals(eth.address, usdc.address, '2')
  await exchange.updateExchangeRateDecimals(btc.address, usdc.address, '2')

  await lever.createMarket(eth.address, ethers.utils.parseEther('1.3'), ethers.utils.parseEther('2'), irm.address, ethOracle.address, ethers.utils.parseEther('10000'), ethers.utils.parseEther('1000'));
  await lever.listMarket(eth.address);
  await lever.createMarket(btc.address, ethers.utils.parseEther('1.5'), ethers.utils.parseEther('2'), irm.address, btcOracle.address, ethers.utils.parseEther('1000'), ethers.utils.parseEther('1000'));
  await lever.listMarket(btc.address);
  await lever.createMarket(usdc.address, ethers.utils.parseEther('1.5'), ethers.utils.parseEther('2'), irm.address, usdcOracle.address, ethers.utils.parseEther('100000000'), ethers.utils.parseEther('10000000'));
  await lever.listMarket(usdc.address);

  return { system, vault, exchange, lever, usdc, btc, eth, usdcOracle, btcOracle, ethOracle, irm };
}
