import hre, { ethers, upgrades } from "hardhat";
import fs from "fs";

async function upgrade() {
	const deployments = JSON.parse(
		fs.readFileSync(
			process.cwd() + `/deployments/${hre.network.name}/deployments.json`,
			"utf8"
		)
	);

    // upgrade version
	const config = JSON.parse(
		fs.readFileSync(
			process.cwd() + `/deployments/${hre.network.name}/config.json`,
			"utf8"
		)
	);
	config.latest = config.latest.split(".")[0] +
		"." +
		config.latest.split(".")[1]+
		"." +
        (parseInt(config.latest.split(".")[2]) + 1);
	

	const Exchange = await ethers.getContractFactory("Exchange");
	const exchange = await Exchange.deploy();
    await exchange.deployed();

    console.log("Created new implementation\nReady to upgrade::", exchange.address);
    
    deployments.contracts['Exchange'].implementations[config.latest] = {
        address: exchange.address,
        source: 'Exchange_'+config.latest,
        constructorArguments: [],
        version: config.latest,
		block: (await ethers.provider.getBlockNumber()).toString()
    };
    deployments.sources['Exchange_'+config.latest] = exchange.interface.format('json');

	fs.writeFileSync(
		process.cwd() + `/deployments/${hre.network.name}/deployments.json`,
		JSON.stringify(deployments, null, 2)
	);
    fs.writeFileSync(
		process.cwd() + `/deployments/${hre.network.name}/config.json`,
		JSON.stringify(config, null, 2)
	);
}

upgrade().then(() => process.exit(0)).catch(error => {
    console.log(error);
})