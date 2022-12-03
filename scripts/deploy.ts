import { Contract } from "ethers";
import hre, { ethers } from "hardhat";

interface Deployments {
  system: Contract;
  exchange: Contract;
  lever: Contract;
  eth: Contract;
  ceth: Contract;
  btc: Contract;
  cbtc: Contract;
  usdc: Contract;
  cusdc: Contract;
  irm: Contract;
  oracle: Contract;
}

export async function deploy(logs = false): Promise<Deployments> {
  /* -------------------------------------------------------------------------- */
  /*                                   System                                   */
  /* -------------------------------------------------------------------------- */
  const System = await ethers.getContractFactory("System");
  const system = await System.deploy();
  await system.deployed();

  if(logs) console.log("System deployed to:", system.address);
  
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
  const LendingMarket = await ethers.getContractFactory("LendingMarket");
  const PriceOracle = await ethers.getContractFactory("SimplePriceOracle");
  const InterestRateModel = await ethers.getContractFactory("JumpRateModelV2");
  const irm = await InterestRateModel.deploy(inEth('0.05'), inEth('0.25'), inEth('0.05'), inEth('0.80'), '0x22F221b77Cd7770511421c8E0636940732016Dcd');
  await irm.deployed();

  const oracle = await PriceOracle.deploy();
  await lever._setPriceOracle(oracle.address);

  const eth = await ERC20.deploy("ETH", "ETH");
  await eth.deployed();
  const ceth = await LendingMarket.deploy(eth.address, lever.address, irm.address, inEth('2'), 'ETH', 'ETH', 18);
  await ceth.deployed();
  
  await oracle.setUnderlyingPrice(ceth.address, inEth('1124'));
  await lever._supportMarket(ceth.address)
  await lever._setCollateralFactor(ceth.address, inEth('0.9'));
  await exchange.enableMarginTrading(eth.address, ceth.address);
  if(logs) console.log("ETH deployed to:", eth.address);
  if(logs) console.log("ETH market deployed to:", ceth.address);

  const btc = await ERC20.deploy("BTC", "BTC");
  await btc.deployed();
  const cbtc = await LendingMarket.deploy(btc.address, lever.address, irm.address, inEth('2'), 'BTC', 'BTC', 18);
  await cbtc.deployed();
  
  await oracle.setUnderlyingPrice(cbtc.address, inEth('16724'));
  await lever._supportMarket(cbtc.address)
  await lever._setCollateralFactor(cbtc.address, inEth('0.9'));
  await exchange.enableMarginTrading(btc.address, cbtc.address);
  if(logs) console.log("BTC deployed to:", btc.address);
  if(logs) console.log("BTC market deployed to:", cbtc.address);

  const usdc = await ERC20.deploy("USDC", "USDC");
  await usdc.deployed();
  const cusdc = await LendingMarket.deploy(usdc.address, lever.address, irm.address, inEth('10'), 'USDC', 'USDC', 18);
  await cusdc.deployed();
  await oracle.setUnderlyingPrice(cusdc.address, inEth('1'));
  await lever._supportMarket(cusdc.address)
  await lever._setCollateralFactor(cusdc.address, inEth('0.9'));
  await exchange.enableMarginTrading(usdc.address, cusdc.address);
  if(logs) console.log("USDC deployed to:", usdc.address);
  if(logs) console.log("USDC market deployed to:", cusdc.address);

  /* -------------------------------------------------------------------------- */
  /*                                   verify                                   */
  /* -------------------------------------------------------------------------- */
  try{
    await hre.run("verify:verify", {
      address: exchange.address,
      constructorArguments: [system.address],
    });
  } catch{
    console.log("Failed to verify exchange")
  }

  try{
    await hre.run("verify:verify", {
      address: lever.address,
      constructorArguments: [system.address],
    });
  } catch {
    console.log("Failed to verify lever")
  }

  try{
    await hre.run("verify:verify", {
      address: ceth.address,
      constructorArguments: [eth.address, lever.address, irm.address, inEth('2'), 'ETH', 'ETH', 18],
    });
  } catch {
    console.log("Failed to verify ceth")
  }

  try{
    await hre.run("verify:verify", {
      address: cbtc.address,
      constructorArguments: [btc.address, lever.address, irm.address, inEth('2'), 'BTC', 'BTC', 18],
    });
  } catch {
    console.log("Failed to verify cbtc")
  }
  
  try{
    await hre.run("verify:verify", {
      address: cusdc.address,
      constructorArguments: [usdc.address, lever.address, irm.address, inEth('10'), 'USDC', 'USDC', 18],
    });
  } catch {
    console.log("Failed to verify cusdc")
  }
  return { system, exchange, lever, usdc, cusdc, btc, cbtc, eth, ceth, oracle, irm };
}

const inEth = (amount: string) => ethers.utils.parseEther(amount);