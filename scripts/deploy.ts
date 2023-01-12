import hre, { ethers } from "hardhat";
const { upgrades } = require("hardhat");

export async function deploy(deployments: any, config: any) {
	deployments.contracts = {};
	deployments.sources = {};

	const [deployer] = await ethers.getSigners();

	// Exchange
	let exchange = await _deploy(
		"Exchange",
		[config.name, config.version, config.admin, config.pauser],
		deployments,
		{upgradable: true},
		config
	);

	console.log(`Deployed zexe ${config.version} to ${exchange.address} 🎉`);

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

	console.log(`Initiating tokens... 💬`)
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

		console.log(`\t✅ ${config.tokens[i].symbol}`)
	}

	/* -------------------------------------------------------------------------- */
	/*                                    Utils                                   */
	/* -------------------------------------------------------------------------- */
	await _deploy("Multicall2", [], deployments);


	/* -------------------------------------------------------------------------- */
	await exchange.renounceRole(await exchange.ADMIN_ROLE(), deployer.address);

	console.log(`Deployment complete 🎉`)

	return {exchange, lever};
}

const inEth = (amount: string | number) => {
	if (typeof amount === "number") amount = amount.toString();
	return ethers.utils.parseEther(amount).toString();
};

const _deploy = async (
	contractName: string,
	args: any[],
	deployments: any,
	{upgradable = false, name = contractName} = {},
	config: any = {},
) => {
	const Contract = await ethers.getContractFactory(contractName);
	let contract;
	if (upgradable) {
		contract = await upgrades.deployProxy(Contract, args, {type: 'uups'});
		args = [];
	} else {
		contract = await Contract.deploy(...args);
	}
	await contract.deployed();

	deployments.contracts[name] = {
		address: contract.address,
		abi: contractName,
		constructorArguments: args,
		block: (await ethers.provider.getBlockNumber()).toString(),
	};
	deployments.sources[contractName] = JSON.parse(
		Contract.interface.format("json") as string
	);

	if (upgradable) {
		const implementationAddress = await upgrades.erc1967.getImplementationAddress(contract.address);
		if(!deployments.contracts[name].implementations) deployments.contracts[name].implementations = {};
		deployments.contracts[name].implementations[config.latest] = {
			address: implementationAddress,
			source: name+'_'+config.latest,
			constructorArguments: [],
			version: config.latest,
			block: (await ethers.provider.getBlockNumber()).toString()
		};
		deployments.contracts[name].latest = implementationAddress;
		deployments.sources[name+'_'+config.latest] = contract.interface.format('json');
	}

	return contract;
};
