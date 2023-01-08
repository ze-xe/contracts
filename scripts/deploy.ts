import hre, { ethers } from "hardhat";
const { upgrades } = require("hardhat");
import fs from 'fs';

export async function deploy(logs = false) {
  const deployments = JSON.parse(fs.readFileSync(process.cwd() + `/deployments/${hre.network.name}/deployments.json`, 'utf8'));
  const config = JSON.parse(fs.readFileSync( process.cwd() + `/deployments/${hre.network.name}/config.json`, 'utf8'));
  
  deployments.contracts = {};
  deployments.sources = {};

  /* -------------------------------------------------------------------------- */
  /*                                  Exchange                                  */
  /* -------------------------------------------------------------------------- */
  const Exchange = await ethers.getContractFactory("Exchange");
  const exchange = await upgrades.deployProxy(Exchange, [config.name, config.version]); 
  await exchange.deployed();

  if(logs) console.log(`Exchange(${config.name} ${config.version}) deployed to `, exchange.address);
  deployments.contracts['Exchange'] = {
    address: exchange.address,
    abi: 'Exchange',
    constructorArguments: [config.name, config.version]
  }
  deployments.sources['Exchange'] = Exchange.interface.format('json');
  
  /* -------------------------------------------------------------------------- */
  /*                                 ZEXE Token                                 */
  /* -------------------------------------------------------------------------- */
  const ZEXE = await ethers.getContractFactory("ZEXE");
  const zexe = await ZEXE.deploy();
  await zexe.deployed();

  if(logs) console.log(`ZEXE deployed to `, zexe.address);
  deployments.contracts['ZEXE'] = {
    address: zexe.address,
    source: 'TestERC20',
    constructorArguments: []
  }
  deployments.sources['TestERC20'] = ZEXE.interface.format('json');

  /* -------------------------------------------------------------------------- */
  /*                                    Lever                                   */
  /* -------------------------------------------------------------------------- */
  const Lever = await ethers.getContractFactory("Lever");
  const lever = await Lever.deploy(exchange.address, zexe.address);
  await lever.deployed();

  if(logs) console.log(`Lever deployed to `, lever.address);
  deployments.contracts['Lever'] = {
    address: lever.address,
    abi: 'Lever',
    constructorArguments: [exchange.address, zexe.address]
  }
  deployments.sources['Lever'] = Lever.interface.format('json');

  /* -------------------------------------------------------------------------- */
  /*                                    Tokens                                  */
  /* -------------------------------------------------------------------------- */
  const ERC20 = await ethers.getContractFactory("TestERC20");
  const LendingMarket = await ethers.getContractFactory("LendingMarket");
  deployments.sources['LendingMarket'] = LendingMarket.interface.format('json');
  const PriceOracle = await ethers.getContractFactory("SimplePriceOracle");
  deployments.sources['PriceOracle'] = PriceOracle.interface.format('json');
  const InterestRateModel = await ethers.getContractFactory("JumpRateModelV2");
  deployments.sources['InterestRateModel'] = InterestRateModel.interface.format('json');

  const oracle = await PriceOracle.deploy();
  await oracle.deployed();
  if(logs) console.log(`PriceOracle deployed to `, oracle.address);
  deployments.contracts['PriceOracle'] = {
    address: oracle.address,
    abi: 'PriceOracle',
    constructorArguments: []
  }
  await lever._setPriceOracle(oracle.address);

  // for additional incentives
  await zexe.mint(lever.address, ethers.utils.parseEther('10000000000000'));

  for(let i in config.tokens){
    const tokenConfig = config.tokens[i];
    // Initialize Interest Rate Model
    const irm = await InterestRateModel.deploy(
      inEth(tokenConfig.interestRateModel.baseRate),
      inEth(tokenConfig.interestRateModel.multiplier),
      inEth(tokenConfig.interestRateModel.jumpMultiplierPerBlock),
      inEth(tokenConfig.interestRateModel.kink),
      tokenConfig.interestRateModel.owner
    );
    deployments.contracts['l'+tokenConfig.symbol+'_IRM'] = {
      address: irm.address,
      abi: 'InterestRateModel',
      constructorArguments: [
        inEth(tokenConfig.interestRateModel.baseRate),
        inEth(tokenConfig.interestRateModel.multiplier),
        inEth(tokenConfig.interestRateModel.jumpMultiplierPerBlock),
        inEth(tokenConfig.interestRateModel.kink),
        tokenConfig.interestRateModel.owner
      ]
    }
    // Initialize token
    let token;
    if(!tokenConfig.address){
      token = await ERC20.deploy(tokenConfig.name, tokenConfig.symbol);
      console.log(`${tokenConfig.symbol} deployed to ${token.address}`);
      deployments.contracts[tokenConfig.symbol] = {
        address: token.address,
        abi: 'TestERC20',
        constructorArguments: [tokenConfig.name, tokenConfig.symbol]
      }
    } else {
      token = await ethers.getContractAt("TestERC20", tokenConfig.address);
      if(!token){
        throw new Error(`Token ${tokenConfig.symbol} not found`);
      }
    } 
    // Initialize market
    const market = await upgrades.deployProxy(LendingMarket, [token.address, lever.address, irm.address, inEth('2'), `Lever ${tokenConfig.name}`, `l${tokenConfig.symbol}`, 18]);
    await market.deployed();
    await oracle.setUnderlyingPrice(market.address, inEth(tokenConfig.price));
    await lever._supportMarket(market.address)
    await lever._setCollateralFactor(market.address, inEth(tokenConfig.collateralFactor));
    await exchange.enableMarginTrading(token.address, market.address);
    await exchange.setMinTokenAmount(token.address, inEth(tokenConfig.minTokenAmount));

    await lever._setCompSpeeds(
      [market.address], 
      [inEth(tokenConfig.supplySpeed)], 
      [inEth(tokenConfig.borrowSpeed)]
    );
    console.log(`l${tokenConfig.symbol} market deployed to ${market.address}`);
    deployments.contracts['l'+tokenConfig.symbol] = {
      address: market.address,
      abi: 'LendingMarket',
      constructorArguments: [token.address, lever.address, irm.address, inEth('2'), `Lever ${tokenConfig.name}`, `l${tokenConfig.symbol}`, 18]
    }
  }

  await exchange.transferOwnership(config.owner);
  fs.writeFileSync(process.cwd() + `/deployments/${hre.network.name}/deployments.json`, JSON.stringify(deployments, null, 2));
}

const inEth = (amount: string|number) => {
  if(typeof amount === 'number') amount = amount.toString();
  return ethers.utils.parseEther(amount).toString();
};