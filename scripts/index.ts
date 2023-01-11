import { deploy } from "./deploy";
import fs from 'fs';
import hre from 'hardhat';

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
  
  await deploy(deployments, config);
  
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
