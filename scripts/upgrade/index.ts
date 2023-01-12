import hre, { defender, ethers, upgrades } from "hardhat";
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
	const proposal = await defender.proposeUpgrade(deployments.contracts['Exchange'].address, Exchange, {title: `Upgrade to ${config.latest}`, multisig: config.admin});
	console.log("Upgrade proposal created at:", proposal.url);
    
    deployments.contracts['Exchange'].implementations[config.latest] = {
        address: proposal.metadata!.newImplementationAddress,
        source: 'Exchange_'+config.latest,
        constructorArguments: [],
        version: config.latest,
		block: (await ethers.provider.getBlockNumber()).toString()
    };
    deployments.contracts['Exchange'].latest = config.latest;
    deployments.sources['Exchange_'+config.latest] = Exchange.interface.format('json');

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