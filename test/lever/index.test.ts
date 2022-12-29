import { expect } from 'chai';
import hre from 'hardhat';
import { BigNumber, Contract } from 'ethers';
import { deploy } from '../../scripts/test';

const ethers = hre.ethers;
const web3 = require('web3');
const toWei = (x: { toString: () => any }) => web3.utils.toWei(x.toString());

describe('lever:main', function () {
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

	it('mint 10 btc to user1, 1000000 usdt to user2', async () => {
		const btcAmount = ethers.utils.parseEther('10');
		await btc.mint(user1.address, btcAmount);
		await btc.connect(user1).approve(exchange.address, btcAmount);

		const usdtAmount = ethers.utils.parseEther('1000000');
		await usdc.mint(user2.address, usdtAmount);
		await usdc.connect(user2).approve(exchange.address, usdtAmount);
	});

	it('user1 deposits 1 BTC', async () => {
        let liq = await lever.getAccountLiquidity(user1.address);
		let btcBalance = await btc.balanceOf(user1.address);
		let cbtcBalance = await cbtc.balanceOf(user1.address);
		expect(liq[1]).to.be.equal(BigNumber.from(0));
		expect(btcBalance).to.be.equal(ethers.utils.parseEther('10'));
		expect(cbtcBalance).to.be.equal(BigNumber.from(0))
        
        let btcAmount = ethers.utils.parseEther('1');
        await exchange.connect(user1).mint(btc.address, btcAmount);
		await lever.connect(user1).enterMarkets([cbtc.address]);

		liq = await lever.getAccountLiquidity(user1.address);
		btcBalance = await btc.balanceOf(user1.address);
		cbtcBalance = await cbtc.balanceOf(user1.address);
		expect(liq[1]).to.be.greaterThan(BigNumber.from(0));
		expect(btcBalance).to.be.equal(ethers.utils.parseEther('9'));
		expect(cbtcBalance).to.be.equal(ethers.utils.parseEther('1').div(2))
	});

	it('user2 deposits 100000 USDC in lever', async () => {
        let liq = await lever.getAccountLiquidity(user2.address);
		let usdcBalance = await usdc.balanceOf(user2.address);
		let cusdcBalance = await cusdc.balanceOf(user2.address);
		expect(liq[1]).to.be.equal(BigNumber.from(0));
		expect(usdcBalance).to.be.equal(ethers.utils.parseEther('1000000'));
		expect(cusdcBalance).to.be.equal(BigNumber.from(0))
        
        let usdcAmount = ethers.utils.parseEther('100000');
        await exchange.connect(user2).mint(usdc.address, usdcAmount);
		await lever.connect(user2).enterMarkets([cusdc.address]);

		liq = await lever.getAccountLiquidity(user2.address);
		usdcBalance = await usdc.balanceOf(user2.address);
		cusdcBalance = await cusdc.balanceOf(user2.address);
		expect(liq[1]).to.be.greaterThan(BigNumber.from(0));
		expect(usdcBalance).to.be.equal(ethers.utils.parseEther('900000'));
		expect(cusdcBalance).to.be.equal(ethers.utils.parseEther('100000').div(10));
	});

	it('user1 borrows 1000 USDC from lever', async () => {
        let usdcAmount = ethers.utils.parseEther('1000');
        await exchange.connect(user1).borrow(usdc.address, usdcAmount);

		let liq = await lever.getAccountLiquidity(user1.address);
		let usdcBalance = await usdc.balanceOf(user1.address);
		let cusdcBalance = await cusdc.balanceOf(user1.address);
		expect(liq[1]).to.be.greaterThan(BigNumber.from(0));
		expect(usdcBalance).to.be.equal(ethers.utils.parseEther('1000'));
		expect(cusdcBalance).to.be.equal(BigNumber.from(0));
	});
});