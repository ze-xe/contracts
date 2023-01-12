import { deploy } from "./deploy";
import fs from 'fs';
import hre, { OpenzeppelinDefender } from 'hardhat';

async function main() {
  // read deployments and config
  const deployments = JSON.parse(fs.readFileSync( process.cwd() + `/deployments/${hre.network.name}/deployments.json`, 'utf8'));
  const config = JSON.parse(fs.readFileSync( process.cwd() + `/deployments/${hre.network.name}/config.json`, 'utf8'));
  // override existing deployments
  deployments.contracts = {};
  deployments.sources = {};
  const version = config.version.split(".")[0] +
		"." +
		(parseInt(config.version.split(".")[1]) + 1) +
		".0";

  config.version = version;
  config.latest = version;
  
  const {exchange, lever} = await deploy(deployments, config);

  if (hre.network.name !== "hardhat") {
		// Add contract to openzeppelin defender
		console.log("Adding contract to openzeppelin defender... 💬");
		// get the abi in json string using the contract interface
		const AbiJsonString = OpenzeppelinDefender.Utils.AbiJsonString(
			exchange.interface
		);

		//Obtaining the name of the network through the chainId of the network
		const networkName = OpenzeppelinDefender.Utils.fromChainId(
			Number(hre.network.config.chainId!)
		);

		//add the contract to the admin
		const option = {
			network: networkName!,
			address: exchange.address,
			name: `Exchange ${config.version.split(".")[0]}.${
				config.version.split(".")[1]
			}.x`,
			abi: AbiJsonString as string,
		};

		await OpenzeppelinDefender.AdminClient.addContract(option);
		console.log(
			`Exchange ${config.version} added to openzeppelin defender! 🎉`
		);
	}
  
  // save deployments
	fs.writeFileSync(process.cwd() + `/deployments/${hre.network.name}/config.json`, JSON.stringify(config, null, 2));
  fs.writeFileSync(process.cwd() + `/deployments/${hre.network.name}/deployments.json`, JSON.stringify(deployments, null, 2));
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
