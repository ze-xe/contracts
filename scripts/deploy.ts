import hre, { ethers } from "hardhat";
const { upgrades } = require("hardhat");
import fs from "fs";

export async function deploy(logs = false) {
	const deployments = JSON.parse(
		fs.readFileSync(
			process.cwd() + `/deployments/${hre.network.name}/deployments.json`,
			"utf8"
		)
	);
	const config = JSON.parse(
		fs.readFileSync(
			process.cwd() + `/deployments/${hre.network.name}/config.json`,
			"utf8"
		)
	);

	deployments.contracts = {};
	deployments.sources = {};

	// Exchange
	let exchange;
	console.log( hre.network.name);
	if ( hre.network.name != 'hardhat'){
		exchange = await _deploy(
		"Exchange",
		[config.name, config.version, process.env.ADMIN_ADDRESS , process.env.PAUSER_ADDRESS, process.env.UPGRADEADMIN_ADDRESS],
		deployments,
		{upgradable: true}
	);
   }
   else{
	    exchange = await _deploy(
		"Exchange",
		[config.name, config.version,'0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266', '0x70997970C51812dc3A010C7d01b50e0d17dc79C8', '0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC'],
		deployments,
		{upgradable: true}
	);
   }
  await exchange.setFees(inEth(config.makerFee), inEth(config.takerFee));

	// ZEXE Token
	const zexe = await _deploy("ZEXE", [], deployments);

	// Lever
	const lever = await _deploy('Lever', [exchange.address, zexe.address], deployments);
	const oracle = await _deploy("SimplePriceOracle", [], deployments, {name: 'PriceOracle'});
	await lever._setPriceOracle(oracle.address);

	/* -------------------------------------------------------------------------- */
	/*                                    Tokens                                  */
	/* -------------------------------------------------------------------------- */
	// for additional incentives
	await zexe.mint(lever.address, ethers.utils.parseEther("10000000000000"));

	for (let i in config.tokens) {
		const tokenConfig = config.tokens[i];
		// Initialize Interest Rate Model
		const irm = await _deploy(
			"JumpRateModelV2",
			[
				inEth(tokenConfig.interestRateModel.baseRate),
				inEth(tokenConfig.interestRateModel.multiplier),
				inEth(tokenConfig.interestRateModel.jumpMultiplierPerBlock),
				inEth(tokenConfig.interestRateModel.kink),
				tokenConfig.interestRateModel.owner,
			],
			deployments, 
      {name: "l" + tokenConfig.symbol + "_IRM"}
		);
		// Initialize token
		let token;
		if (!tokenConfig.address) {
			token = await _deploy('TestERC20', [tokenConfig.name, tokenConfig.symbol], deployments, {name: tokenConfig.symbol});
		} else {
			token = await ethers.getContractAt("TestERC20", tokenConfig.address);
			if (!token) {
				throw new Error(`Token ${tokenConfig.symbol} not found`);
			}
		}
		// Initialize market
    const market = await _deploy(
      "LendingMarket",
      [
        token.address,
        lever.address,
        irm.address,
        inEth("2"),
        `Lever ${tokenConfig.name}`,
        `l${tokenConfig.symbol}`,
        18,
      ],
      deployments,
      {upgradable: true, name: "l" + tokenConfig.symbol + "_Market"}
    );
		await oracle.setUnderlyingPrice(
			market.address,
			inEth(tokenConfig.price)
		);
		await lever._supportMarket(market.address);
		await lever._setCollateralFactor(
			market.address,
			inEth(tokenConfig.collateralFactor)
		);
		await exchange.enableMarginTrading(token.address, market.address);
		await exchange.setMinTokenAmount(
			token.address,
			inEth(tokenConfig.minTokenAmount)
		);

		await lever._setCompSpeeds(
			[market.address],
			[inEth(tokenConfig.supplySpeed)],
			[inEth(tokenConfig.borrowSpeed)]
		);
	}

	/* -------------------------------------------------------------------------- */
	/*                                    Utils                                   */
	/* -------------------------------------------------------------------------- */
	await _deploy("Multicall2", [], deployments);

	// await exchange.transferOwnership(config.owner);
	// fs.writeFileSync(
	// 	process.cwd() + `/deployments/${hre.network.name}/deployments.json`,
	// 	JSON.stringify(deployments, null, 2)
	// );
}

const inEth = (amount: string | number) => {
	if (typeof amount === "number") amount = amount.toString();
	return ethers.utils.parseEther(amount).toString();
};

const _deploy = async (
	contractName: string,
	args: any[],
	deployments: any,
	{upgradable = false, name = contractName} = {}
) => {
	const Contract = await ethers.getContractFactory(contractName);
	let contract;
	if (upgradable) { 
		contract = await upgrades.deployProxy(Contract, args, {type: 'uups'});
	} else {
		contract = await Contract.deploy(...args);
	}
	await contract.deployed();

	deployments.contracts[name] = {
		address: contract.address,
		abi: contractName,
		constructorArguments: args,
	};
	deployments.sources[contractName] = JSON.parse(
		Contract.interface.format("json") as string
	);
 
	if ( hre.network.name != 'hardhat'){
	console.log(`verifying ${name} `);

	await hre.run("verify:verify", {
        address: contract.address,
      constructorArguments:[],
      });
	}
	
	console.log(`${name} deployed to ${contract.address}`);

	return contract;
};
