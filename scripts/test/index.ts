import { Contract } from "ethers";
import hre, { ethers, upgrades } from "hardhat";


export async function deploy() {

  /* -------------------------------------------------------------------------- */
  /*                                  Exchange                                  */
  /* -------------------------------------------------------------------------- */
  const Exchange = await ethers.getContractFactory("Exchange");
  const exchange = await upgrades.deployProxy(Exchange, ['zexe', '1']); 
  await exchange.deployed();
  
  /* -------------------------------------------------------------------------- */
  /*                                 ZEXE Token                                 */
  /* -------------------------------------------------------------------------- */
  const ZEXE = await ethers.getContractFactory("ZEXE");
  const zexe = await ZEXE.deploy();
  await zexe.deployed();

  /* -------------------------------------------------------------------------- */
  /*                                    Lever                                   */
  /* -------------------------------------------------------------------------- */
  const Lever = await ethers.getContractFactory("Lever");
  const lever = await Lever.deploy(exchange.address, zexe.address);
  await lever.deployed();

  /* -------------------------------------------------------------------------- */
  /*                                    Tokens                                  */
  /* -------------------------------------------------------------------------- */
  const ERC20 = await ethers.getContractFactory("TestERC20");
  const LendingMarket = await ethers.getContractFactory("LendingMarket");
  const PriceOracle = await ethers.getContractFactory("SimplePriceOracle");
  const InterestRateModel = await ethers.getContractFactory("JumpRateModelV2");
  const irm = await InterestRateModel.deploy(inEth('0.05'), inEth('0.25'), inEth('0.05'), inEth('0.90'), '0x22F221b77Cd7770511421c8E0636940732016Dcd');
  await irm.deployed();

  const oracle = await PriceOracle.deploy();
  await lever._setPriceOracle(oracle.address);

  const eth = await ERC20.deploy("Ethereum", "ETH");
  await eth.deployed();
  const ceth = await upgrades.deployProxy(LendingMarket, [eth.address, lever.address, irm.address, inEth('2'), 'Ethereum', 'ETH', 18]);
  await ceth.deployed();
  
  await oracle.setUnderlyingPrice(ceth.address, inEth('1124'));
  await lever._supportMarket(ceth.address)
  await lever._setCollateralFactor(ceth.address, inEth('0.92'));
  await exchange.enableMarginTrading(eth.address, ceth.address);
  await exchange.setMinTokenAmount(eth.address, inEth('0.1'));

  const btc = await ERC20.deploy("Bitcoin", "BTC");
  await btc.deployed();
  const cbtc = await upgrades.deployProxy(LendingMarket, [btc.address, lever.address, irm.address, inEth('2'), 'Bitcoin', 'BTC', 18]);
  await cbtc.deployed();
  
  await oracle.setUnderlyingPrice(cbtc.address, inEth('16724'));
  await lever._supportMarket(cbtc.address)
  await lever._setCollateralFactor(cbtc.address, inEth('0.92'));
  await exchange.enableMarginTrading(btc.address, cbtc.address);
  await exchange.setMinTokenAmount(btc.address, inEth('0.001'));

  const usdc = await ERC20.deploy("USD Coin", "USDC");
  await usdc.deployed();
  const cusdc = await upgrades.deployProxy(LendingMarket, [usdc.address, lever.address, irm.address, inEth('10'), 'USD Coin', 'USDC', 18]);
  await cusdc.deployed();
  await oracle.setUnderlyingPrice(cusdc.address, inEth('1'));
  await lever._supportMarket(cusdc.address)
  await lever._setCollateralFactor(cusdc.address, inEth('0.92'));
  await exchange.enableMarginTrading(usdc.address, cusdc.address);
  await exchange.setMinTokenAmount(usdc.address, inEth('10'));

  await zexe.mint(lever.address, ethers.utils.parseEther('10000000000000'));
  await lever._setCompSpeeds(
    [cusdc.address, cbtc.address, ceth.address], 
    [ethers.utils.parseEther("0.0000001"), ethers.utils.parseEther("0.000001"), ethers.utils.parseEther("0.001")], 
    [ethers.utils.parseEther("0.00001"), ethers.utils.parseEther("0.0001"), ethers.utils.parseEther("0.00001")]
  )

  return { exchange, lever, usdc, cusdc, btc, cbtc, eth, ceth, oracle, irm };
}

const inEth = (amount: string) => ethers.utils.parseEther(amount);