import { expect } from 'chai';
import hre from 'hardhat';
import { Contract } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { deploy } from '../scripts/deploy';

const ethers = hre.ethers;
const web3 = require('web3');
const toWei = (x: { toString: () => any }) => web3.utils.toWei(x.toString());

describe('lever', function () {
	let usdt: Contract, btc: Contract, exchange: Contract, vault: Contract, lever: Contract;
	let owner: any, user1: any, user2: any, user3, user4, user5, user6;
	let orderIds: string[] = [];
	before(async () => {
		[owner, user1, user2, user3, user4, user5, user6] = await ethers.getSigners();
		const deployments = await deploy();
		usdt = deployments.usdc;
		btc = deployments.btc;
		exchange = deployments.exchange;
		vault = deployments.vault;
        lever = deployments.lever;
	});

	it('mint 10 btc to user1, 1000000 usdt to user2', async () => {
		const btcAmount = ethers.utils.parseEther('10');
		await btc.mint(user1.address, btcAmount);
		await btc.connect(user1).approve(vault.address, btcAmount);
		await vault.connect(user1).deposit(btc.address, btcAmount);

		const usdtAmount = ethers.utils.parseEther('1000000');
		await usdt.mint(user2.address, usdtAmount);
		await usdt.connect(user2).approve(vault.address, usdtAmount);
		await vault.connect(user2).deposit(usdt.address, usdtAmount);
	});

	it('user1 deposits 1 BTC in lever', async () => {
        expect(await lever.getHealthFactor(user1.address)).to.be.equal(0);
        
        const btcAmount = ethers.utils.parseEther('1');
        await lever.connect(user1).deposit(btc.address, btcAmount);

        const collateral = await lever.getCollateralFactors(user1.address);
        expect(await lever.getHealthFactor(user1.address)).to.be.equal(ethers.constants.MaxUint256);
	});
});