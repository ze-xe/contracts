import { expect } from 'chai';
import hre from 'hardhat';
import { Contract } from 'ethers';
import { deploy } from '../scripts/test';

const ethers = hre.ethers;
const web3 = require('web3');
const toWei = (x: { toString: () => any }) => web3.utils.toWei(x.toString());

describe('exchange', function () {
	let usdt: Contract, btc: Contract, exchange: Contract, vault: Contract;
	let owner: any, user1: any, user2: any, user3, user4, user5, user6;
	let orderIds: string[] = [];
	let signatures: string[] = [];
	let orders: any[] = []
	before(async () => {
		[owner, user1, user2, user3, user4, user5, user6] =
			await ethers.getSigners();
		const deployments = await deploy();
		usdt = deployments.usdc;
		btc = deployments.btc;
		exchange = deployments.exchange;
	});

	it('mint 10 btc to user1, 1000000 usdt to user2', async () => {
		const btcAmount = ethers.utils.parseEther('10');
		await btc.mint(user1.address, btcAmount);
		// approve for exchange
		await btc.connect(user1).approve(exchange.address, btcAmount);

		const usdtAmount = ethers.utils.parseEther('1000000');
		await usdt.mint(user2.address, usdtAmount);
		// approve for exchange
		await usdt.connect(user2).approve(exchange.address, usdtAmount);
	});

	it('user1 creates limit order to sell 1 btc @ 19100', async () => {
		const domain = {
			name: 'zexe',
			version: '1',
			chainId: hre.network.config.chainId,
			verifyingContract: exchange.address,
		};

		// The named list of all type definitions
		const types = {
			Order: [
				{ name: 'maker', type: 'address' },
				{ name: 'token0', type: 'address' },
				{ name: 'token1', type: 'address' },
				{ name: 'amount', type: 'uint256' },
				{ name: 'orderType', type: 'uint8' },
                { name: 'salt', type: 'uint32' },
				{ name: 'exchangeRate', type: 'uint176' },
				{ name: 'borrowLimit', type: 'uint32' },
				{ name: 'loops', type: 'uint8' }
			]
		};

		// The data to sign
		const value = {
			maker: user1.address,
			token0: btc.address, 
            token1: usdt.address,
			amount: ethers.utils.parseEther('1').toString(),
			orderType: 1, // sell
            salt: '12345',
            exchangeRate: ethers.utils.parseUnits('19100', 18).toString(),
			borrowLimit: '0',
			loops: '0'
		};

		orders.push(value);

		// sign typed data
		const storedSignature = await user1._signTypedData(
			domain,
			types,
			value
		);
		signatures.push(storedSignature);

		// get typed hash
		const hash = ethers.utils._TypedDataEncoder.hash(domain, types, value);
		orderIds.push(hash);
		expect(await exchange.verifyOrderHash(storedSignature, value)).to.equal(hash);
	});

	it('buy user1s btc order @ 19100', async () => {
		let user1BtcBalance = await btc.balanceOf(user1.address);
		expect(user1BtcBalance).to.equal(ethers.utils.parseEther('10'));
		let user2BtcBalance = await btc.balanceOf(user2.address);
		expect(user2BtcBalance).to.equal(ethers.utils.parseEther('0'));

		const btcAmount = ethers.utils.parseEther('5');
		await exchange.connect(user2).executeLimitOrders(
            [signatures[0]],
            [orders[0]],
			btcAmount
		);

		user1BtcBalance = await btc.balanceOf(user1.address);
		expect(user1BtcBalance).to.equal(ethers.utils.parseEther('9'));
		user2BtcBalance = await btc.balanceOf(user2.address);
		expect(user2BtcBalance).to.equal(ethers.utils.parseEther('1'));
	});
});