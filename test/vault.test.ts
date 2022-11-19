import { expect } from 'chai';
import hre from 'hardhat';
import { Contract } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { deploy } from '../scripts/deploy';

const ethers = hre.ethers;
const web3 = require('web3');
const toWei = (x: { toString: () => any }) => web3.utils.toWei(x.toString());
describe('vault', function () {
	let eth: Contract, btc: Contract, usdc: Contract, vault: Contract;
	let owner, user1: any, user2, user3, user4, user5, user6;

	before(async () => {
		[owner, user1, user2, user3, user4, user5, user6] =
			await ethers.getSigners();

		const deployments = await deploy();
        eth = deployments.eth;
        btc = deployments.btc;
        usdc = deployments.usdc;
		vault = deployments.vault;
	});

	it('create deposit1', async () => {
		await eth.mint(user1.address, 100);
		await eth.connect(user1).approve(vault.address, 100);
		await vault.connect(user1).deposit(eth.address, 100);
		expect(await vault.userTokenBalance(user1.address, eth.address)).to.be.equal(
			100
		);
	});

	it('create deposit2', async () => {
		await btc.mint(user1.address, 10);
		await btc.connect(user1).approve(vault.address, 10);
		await vault.connect(user1).deposit(btc.address, 10);
		expect(await vault.userTokenBalance(user1.address, btc.address)).to.be.equal(
			10
		);
	});

	it('create withdraw', async () => {
		await vault.connect(user1).withdraw(eth.address, 10);
		expect(await vault.userTokenBalance(user1.address, eth.address)).to.be.equal(
			90
		);
		expect(await eth.balanceOf(user1.address)).to.be.equal(10);
	});
});
