import { expect } from 'chai';
import hre from 'hardhat';
import { Contract } from 'ethers';
import { deploy } from '../../scripts/deploy';

const ethers = hre.ethers;
const web3 = require('web3');
const toWei = (x: { toString: () => any }) => web3.utils.toWei(x.toString());

describe('rates', function () {
	let usdc: Contract, cusdc: Contract, btc: Contract, cbtc: Contract, eth: Contract, ceth: Contract, exchange: Contract, vault: Contract, lever: Contract;
	let owner: any, user1: any, user2: any, user3, user4, user5, user6;
	let orderIds: string[] = [];

	before(async () => {
		[owner, user1, user2, user3, user4, user5, user6] = await ethers.getSigners();
		const deployments = await deploy();
		usdc = deployments.usdc;
		cusdc = deployments.cusdc;
		btc = deployments.btc;
		cbtc = deployments.cbtc;
		eth = deployments.eth;
		ceth = deployments.ceth;
		exchange = deployments.exchange;
        lever = deployments.lever;
	});

	it('check rates', async() => {
		let supplyRatePerSec = await cusdc.supplyRatePerBlock();
		let borrowRatePerSec = await cusdc.borrowRatePerBlock();
		let supplyApy = (((Math.pow(((supplyRatePerSec/1e18) * 24*60*60) + 1, 365))) - 1) * 100;
		let borrowApy = (((Math.pow(((borrowRatePerSec/1e18) * 24*60*60) + 1, 365))) - 1) * 100;
		let borrowRatePerHour = 100 * (Math.pow(1 + (borrowRatePerSec/1e18), 60*60) - 1);
		console.log(`Supply APY for USDC ${supplyApy} %`);
		console.log(`Borrow APY for USDC ${borrowApy} %`);
		console.log(`Borrow Rate per Hour for USDC ${borrowRatePerHour} %`);
	})

	it('utilization = 80%, supply 1000 USDC and borrow 800 USDC', async () => {
		await usdc.connect(user1).mint(user1.address, toWei(1000));
		await usdc.connect(user1).approve(cusdc.address, toWei(1000));

		await cusdc.connect(user1).mint(toWei(1000));
		await cusdc.connect(user1).borrow(toWei(800));
	})


	it('check rates', async() => {
		let supplyRatePerSec = await cusdc.supplyRatePerBlock();
		let borrowRatePerSec = await cusdc.borrowRatePerBlock();
		let supplyApy = (((Math.pow(((supplyRatePerSec/1e18) * 24*60*60) + 1, 365))) - 1) * 100;
		let borrowApy = (((Math.pow(((borrowRatePerSec/1e18) * 24*60*60) + 1, 365))) - 1) * 100;
		let borrowRatePerHour = 100 * (Math.pow(1 + (borrowRatePerSec/1e18), 60*60) - 1);
		console.log(`Supply APY for USDC ${supplyApy} %`);
		console.log(`Borrow APY for USDC ${borrowApy} %`);
		console.log(`Borrow Rate per Hour for USDC ${borrowRatePerHour} %`);
	})

	it('utilization = 7%, supply 10000 USDC', async () => {
		// mint
		await usdc.connect(user2).mint(user2.address, toWei(10000));
		await usdc.connect(user2).approve(cusdc.address, toWei(10000));

		await cusdc.connect(user2).mint(toWei(10000));
	})

	it('check rates', async() => {
		let supplyRatePerSec = await cusdc.supplyRatePerBlock();
		let borrowRatePerSec = await cusdc.borrowRatePerBlock();
		let supplyApy = (((Math.pow(((supplyRatePerSec/1e18) * 24*60*60) + 1, 365))) - 1) * 100;
		let borrowApy = (((Math.pow(((borrowRatePerSec/1e18) * 24*60*60) + 1, 365))) - 1) * 100;
		let borrowRatePerHour = 100 * (Math.pow(1 + (borrowRatePerSec/1e18), 60*60) - 1);
		console.log(`Supply APY for USDC ${supplyApy} %`);
		console.log(`Borrow APY for USDC ${borrowApy} %`);
		console.log(`Borrow Rate per Hour for USDC ${borrowRatePerHour} %`);
	})
});