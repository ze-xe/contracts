import { expect } from 'chai';
import hre from 'hardhat';
import { Contract } from 'ethers';
import { deploy } from '../scripts/deploy';

const ethers = hre.ethers;
const web3 = require('web3');
const toWei = (x: { toString: () => any }) => web3.utils.toWei(x.toString());

describe('lever', function () {
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
		vault = deployments.vault;
        lever = deployments.lever;
	});

	it('check rates', async() => {
		let supplyRatePerBlock = await cusdc.supplyRatePerBlock();
		let borrowRatePerBlock = await cusdc.borrowRatePerBlock();
		let supplyApy = (((Math.pow(((supplyRatePerBlock/1e18) * 24*60*60) + 1, 365))) - 1) * 100;
		let borrowApy = (((Math.pow(((borrowRatePerBlock/1e18) * 24*60*60) + 1, 365))) - 1) * 100;
		console.log(`Supply APY for USDC ${supplyApy} %`);
		console.log(`Borrow APY for USDC ${borrowApy} %`);


		supplyRatePerBlock = await cbtc.supplyRatePerBlock();
		borrowRatePerBlock = await cbtc.borrowRatePerBlock();
		supplyApy = (((Math.pow(((supplyRatePerBlock/1e18) * 24*60*60) + 1, 365))) - 1) * 100;
		borrowApy = (((Math.pow(((borrowRatePerBlock/1e18) * 24*60*60) + 1, 365))) - 1) * 100;
		console.log(`Supply APY for BTC ${supplyApy} %`);
		console.log(`Borrow APY for BTC ${borrowApy} %`);

		supplyRatePerBlock = await ceth.supplyRatePerBlock();
		borrowRatePerBlock = await ceth.borrowRatePerBlock();
		supplyApy = (((Math.pow(((supplyRatePerBlock/1e18) * 24*60*60) + 1, 365))) - 1) * 100;
		borrowApy = (((Math.pow(((borrowRatePerBlock/1e18) * 24*60*60) + 1, 365))) - 1) * 100;
		console.log(`Supply APY for ETH ${supplyApy} %`);
		console.log(`Borrow APY for ETH ${borrowApy} %`);
	})

	it('mint 10 btc to user1, 1000000 usdt to user2', async () => {
		const btcAmount = ethers.utils.parseEther('10');
		await btc.mint(user1.address, btcAmount);
		await btc.connect(user1).approve(vault.address, btcAmount);
		await btc.connect(user1).approve(cbtc.address, btcAmount);
		// await vault.connect(user1).deposit(btc.address, btcAmount);

		const usdtAmount = ethers.utils.parseEther('1000000');
		await usdc.mint(user2.address, usdtAmount);
		await usdc.connect(user2).approve(vault.address, usdtAmount);
		await usdc.connect(user2).approve(cusdc.address, usdtAmount);
		// await vault.connect(user2).deposit(usdc.address, usdtAmount);
	});

	it('user1 deposits 1 BTC in lever', async () => {
        let liq = await lever.getAccountLiquidity(user1.address);
		let btcBalance = await btc.balanceOf(user1.address);
		let cbtcBalance = await cbtc.balanceOf(user1.address);
		// expect().to.be.equal(0);
		// console.log(liq, btcBalance.toString(), cbtcBalance.toString())
        
        let btcAmount = ethers.utils.parseEther('1');
        await cbtc.connect(user1).mint(btcAmount);
		await lever.connect(user1).enterMarkets([cbtc.address, cusdc.address]);

		liq = await lever.getAccountLiquidity(user1.address);
		btcBalance = await btc.balanceOf(user1.address);
		cbtcBalance = await cbtc.balanceOf(user1.address);
		// console.log(liq, btcBalance.toString(), cbtcBalance.toString())
	});

	it('user2 deposits 100000 USDC in lever', async () => {
        let liq = await lever.getAccountLiquidity(user2.address);
		let usdcBalance = await usdc.balanceOf(user2.address);
		let cusdcBalance = await cusdc.balanceOf(user2.address);
		// expect().to.be.equal(0);
		// console.log(liq, usdcBalance.toString(), cusdcBalance.toString())
        
        let usdcAmount = ethers.utils.parseEther('100000');
        await cusdc.connect(user2).mint(usdcAmount);
		await lever.connect(user2).enterMarkets([cusdc.address, cbtc.address]);

		liq = await lever.getAccountLiquidity(user2.address);
		usdcBalance = await usdc.balanceOf(user2.address);
		cusdcBalance = await cusdc.balanceOf(user2.address);
		// console.log(liq, usdcBalance.toString(), cusdcBalance.toString())
	});

	it('user1 borrows 1000 USDC from lever', async () => {
        let liq = await lever.getAccountLiquidity(user1.address);
		let usdcBalance = await usdc.balanceOf(user1.address);
		let cusdcBalance = await cusdc.balanceOf(user1.address);
		// expect().to.be.equal(0);
		// console.log(liq, usdcBalance.toString(), cusdcBalance.toString())
        
        let usdcAmount = ethers.utils.parseEther('1000');
        await cusdc.connect(user1).borrow(usdcAmount);

		liq = await lever.getAccountLiquidity(user1.address);
		usdcBalance = await usdc.balanceOf(user1.address);
		cusdcBalance = await cusdc.balanceOf(user1.address);
		// console.log(liq, usdcBalance.toString(), cusdcBalance.toString())
	});
});