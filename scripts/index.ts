import { deploy } from "./deploy";
import fs from 'fs';
import hre from 'hardhat';

async function main() {
  // upgrade version
  const config = JSON.parse(
		fs.readFileSync(
			process.cwd() + `/deployments/${hre.network.name}/config.json`,
			"utf8"
		)
	);
  config.version = config.version.split('.')[0]+'.'+ config.version.split('.')[1]+'.'+(parseInt(config.version.split('.')[2])+1);
  fs.writeFileSync(
    process.cwd() + `/deployments/${hre.network.name}/config.json`,
    JSON.stringify(config, null, 2)
  );

  await deploy(true);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
