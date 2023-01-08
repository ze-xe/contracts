import hre, { ethers } from "hardhat";
import fs from "fs";

async function upgrade() {
	const deployments = JSON.parse(
		fs.readFileSync(
			process.cwd() + `/deployments/${hre.network.name}/deployments.json`,
			"utf8"
		)
	);

	const Exchange = await ethers.getContractFactory("Exchange");
	const exchange = await Exchange.deploy();
    await exchange.deployed();

    console.log("Exchange deployed to:", exchange.address);

    deployments.contracts['Exchange'].address = exchange.address;
    deployments.sources['Exchange'] = JSON.parse(exchange.interface.format('json') as string);

	fs.writeFileSync(
		process.cwd() + `/deployments/${hre.network.name}/deployments.json`,
		JSON.stringify(deployments, null, 2)
	);
}

upgrade().then(() => process.exit(0)).catch(error => {
    console.log(error);
})