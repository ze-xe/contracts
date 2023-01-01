import { Contract } from "ethers";
import hre, { ethers } from "hardhat";
const { upgrades } = require("hardhat");
import fs from 'fs';

export async function verify(logs = false) {
  const deployments = JSON.parse(fs.readFileSync(process.cwd() + `/deployments/${hre.network.name}/deployments.json`, 'utf8'));
  
  for(let i in deployments.contracts){
    await hre.run("verify:verify", {
      address: deployments.contracts[i].address,
      constructorArguments: deployments.contracts[i].constructorArguments,
    });
  }
}

verify().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});