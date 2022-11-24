import { expect } from 'chai';
import hre from 'hardhat';
import { Contract } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { deploy } from '../../scripts/deploy';
import {BigNumber} from 'ethers';

const ethers = hre.ethers;
const web3 = require('web3');
const toWei = (x: { toString: () => any }) => web3.utils.toWei(x.toString());

describe('zexe', function () {
	let usdc: Contract, btc: Contract, exchange: Contract, cbtc: Contract, cusdc: Contract, lever: Contract;
	let owner: any, user1: any, user2: any, user3: any, user4: any, user5: any, user6;
	let orderIds: string[] = [];
	let signatures: string[] = [];

    let orders: any[] = [];

	before(async () => {
		[owner, user1, user2, user3, user4, user5, user6] =
			await ethers.getSigners();
		const deployments = await deploy();
		usdc = deployments.usdc;
		cusdc = deployments.cusdc;
		btc = deployments.btc;
        cbtc = deployments.cbtc;
		exchange = deployments.exchange;
        lever = deployments.lever;
	});

	it('mint 10 btc to user1, 1000000 usdt to user2', async () => {
		let btcAmount = ethers.utils.parseEther('1');
		await btc.mint(user1.address, btcAmount);
        // approve for exchange to sell usdc
		await usdc.connect(user1).approve(exchange.address, ethers.constants.MaxUint256);
		// approve btc to cbtc market to mint
		await btc.connect(user1).approve(cbtc.address, ethers.constants.MaxUint256);

        btcAmount = ethers.utils.parseEther('10');
        await btc.mint(user2.address, btcAmount);
		// approve for exchange to sell usdc
        await btc.connect(user2).approve(exchange.address, ethers.constants.MaxUint256);

        // check approval
        // expect(await btc.allowance(user1.address, exchange.address)).to.equal(ethers.constants.MaxUint256);
        // expect(await btc.allowance(user1.address, cbtc.address)).to.equal(ethers.constants.MaxUint256);
        // expect(await btc.allowance(user1.address, cusdc.address)).to.equal(ethers.constants.MaxUint256);
        // expect(await usdc.allowance(user2.address, exchange.address)).to.equal(ethers.constants.MaxUint256);
        // expect(await usdc.allowance(user2.address, cbtc.address)).to.equal(ethers.constants.MaxUint256);
        // expect(await usdc.allowance(user2.address, cusdc.address)).to.equal(ethers.constants.MaxUint256);
	});

    it("make market liquid", async () => {
        // user 3, 4 and 5 are market makers
        // address 100 btc 100000 usdc to market
        const btcAmount = ethers.utils.parseEther('1000');
        await btc.mint(user3.address, btcAmount);
        await btc.connect(user3).approve(cbtc.address, ethers.constants.MaxUint256);
        await cbtc.connect(user3).mint(btcAmount);

        const usdcAmount = ethers.utils.parseEther('10000000');
        await usdc.mint(user4.address, usdcAmount);
        await usdc.connect(user4).approve(cusdc.address, ethers.constants.MaxUint256);
        await cusdc.connect(user4).mint(usdcAmount);
    })

	it('user1 creates long order of 1 btc @ 20000 @ 5_loops', async () => {
		const domain = {
			name: 'zexe',
			version: '1',
			chainId: hre.network.config.chainId,
			verifyingContract: exchange.address,
		};

		// The named list of all type definitions
		const types = {
			LeverageOrder: [
				{ name: 'maker', type: 'address' },
				{ name: 'token0', type: 'address' },
				{ name: 'token1', type: 'address' },
				{ name: 'amount', type: 'uint256' },
				{ name: 'long', type: 'bool' },
                { name: 'salt', type: 'uint32' },
				{ name: 'exchangeRate', type: 'uint176' },
				{ name: 'borrowLimit', type: 'uint32' },
				{ name: 'loops', type: 'uint8' }
			],
		};

		// The data to sign
		const value = {
			maker: user1.address,
			token0: btc.address, 
            token1: usdc.address,
			amount: ethers.utils.parseEther('1').toString(),
			long: true, // long
            salt: '12345',
            exchangeRate: (20000*1e8).toString(),
            borrowLimit: 0.75 * 1e6,
            loops: 9,
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
		expect(await exchange.verifyLeverageOrderHash(storedSignature, value)).to.equal(hash);
        orderIds.push(hash);
	});

	it('sell 2 btc to user1 order @ 20000', async () => {
		let user1BtcBalance: BigNumber = await btc.balanceOf(user1.address);
		expect(user1BtcBalance).to.equal(ethers.utils.parseEther('1'));
		let user2BtcBalance = await btc.balanceOf(user2.address);
		expect(user2BtcBalance).to.equal(ethers.utils.parseEther('10'));

		// user1 usdc balance
		let user1UsdcBalance = await usdc.balanceOf(user1.address);
		expect(user1UsdcBalance).to.equal(0);
		// user2 usdc balance
		let user2UsdcBalance = await usdc.balanceOf(user2.address);
		expect(user2UsdcBalance).to.equal(ethers.utils.parseEther('0'));

        await lever.connect(user1).enterMarkets([cbtc.address, cusdc.address]);
        
        // 1 BTC -> 0.75 BTC -> 0.56 BTC = 0.42 BTC
		const btcAmount = ethers.utils.parseEther('2');
		await exchange.connect(user2).executeLeverageOrder(
            signatures[0],
            orders[0],
			btcAmount
		);

		
		expect(await usdc.balanceOf(user2.address)).to.equal(ethers.utils.parseEther('40000'));
		expect(await btc.balanceOf(user2.address)).to.equal(ethers.utils.parseEther('8'));
		
		// const loops = await exchange.loops(orderIds[0]);
        // const loopFill = await exchange.loopFill(orderIds[0]);
        // console.log('loops', loops.toString());
        // console.log('loopFill', loopFill.toString());
        console.log("---------------------");
	});

    it('sell 0.5 btc to user1 order @ 20000', async () => {

     await lever.connect(user1).enterMarkets([cbtc.address, cusdc.address]);
		const btcAmount = ethers.utils.parseEther('0.5');
        
        // 1 BTC -> 0.5 BTC -> 0.25 BTC = 1.75 BTC
		await exchange.connect(user2).executeLeverageOrder(
            signatures[0],
            orders[0],
			btcAmount
		);

        // let user1UsdcBalance = await usdc.balanceOf(user1.address);
        // // 0.0625 btc * 20000 usdc = 1250 usdc
        // expect(user1UsdcBalance).to.equal(ethers.utils.parseEther('1250'));

        // const loops = await exchange.loops(orderIds[0]);
        // const loopFill = await exchange.loopFill(orderIds[0]);
        // console.log('loops', loops.toString());
        // console.log('loopFill', loopFill.toString());
        console.log("---------------------");
	});

    it('sell 1 btc to user1 order @ 20000', async () => {
		const btcAmount = ethers.utils.parseEther('1');
        
        // 1 BTC -> 0.5 BTC -> 0.25 BTC = 1.75 BTC
		await exchange.connect(user2).executeLeverageOrder(
            signatures[0],
            orders[0],
			btcAmount
		);

        // const loops = await exchange.loops(orderIds[0]);
        // const loopFill = await exchange.loopFill(orderIds[0]);
        // console.log('loops', loops.toString());
        // console.log('loopFill', loopFill.toString());
        console.log("---------------------");
	});

	it('executing empty limit order', async () => {
		const btcAmount = ethers.utils.parseEther('1');
        
		await exchange.connect(user2).executeLeverageOrder(
            signatures[0],
            orders[0],
			btcAmount
		);

        // const loops = await exchange.loops(orderIds[0]);
        // const loopFill = await exchange.loopFill(orderIds[0]);
        // console.log('loops', loops.toString());
        // console.log('loopFill', loopFill.toString());
        console.log("---------------------");
	});

	it('amount checks', async () => {
		let user1BtcBalance = ethers.utils.parseEther('1');
		let user2BtcBalance = ethers.utils.parseEther('10');
		let user1UsdcBalance = ethers.utils.parseEther('0');
		let user2UsdcBalance = ethers.utils.parseEther('0');

        let user1FinalBalance = user1BtcBalance.mul(BigNumber.from(orders[0].borrowLimit)).div(BigNumber.from(1e6));
        let finalBtcAmountSold = BigNumber.from(0);

		for(let i = 1; i < orders[0].loops; i++){
			finalBtcAmountSold = finalBtcAmountSold.add(user1FinalBalance);
			user1FinalBalance = user1FinalBalance.mul(BigNumber.from(orders[0].borrowLimit)).div(BigNumber.from(1e6));
		}
		expect(await btc.balanceOf(user1.address)).to.equal(user1FinalBalance);
		expect(await btc.balanceOf(user2.address)).to.closeTo(user2BtcBalance.sub(finalBtcAmountSold), ethers.utils.parseEther("0.1"));

		// user1 usdc balance
		user1UsdcBalance = await usdc.balanceOf(user1.address);
		expect(user1UsdcBalance).to.equal(ethers.utils.parseEther('0'));
		// user2 usdc balance
		user2UsdcBalance = await usdc.balanceOf(user2.address);
		expect(user2UsdcBalance).to.closeTo(finalBtcAmountSold.mul(BigNumber.from(orders[0].exchangeRate)).div(BigNumber.from(1e8)), ethers.utils.parseEther("2000"));
	})
});