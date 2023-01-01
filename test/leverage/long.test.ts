import { expect } from 'chai';
import hre from 'hardhat';
import { Contract } from 'ethers';
import { deploy } from '../../scripts/test';
import {BigNumber} from 'ethers';

const ethers = hre.ethers;

describe('leverage:long', function () {
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
		await btc.connect(user1).approve(exchange.address, ethers.constants.MaxUint256);

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
        const btcAmount = ethers.utils.parseEther('10000');
        await btc.mint(user3.address, btcAmount);
        await btc.connect(user3).approve(exchange.address, ethers.constants.MaxUint256);
        await exchange.connect(user3).mint(btc.address, btcAmount);

        const usdcAmount = ethers.utils.parseEther('100000000');
        await usdc.mint(user4.address, usdcAmount);
        await usdc.connect(user4).approve(exchange.address, ethers.constants.MaxUint256);
        await exchange.connect(user4).mint(usdc.address, usdcAmount);
    })

	it('user1 creates 1 btc long order @ 20000 with 3x leverage', async () => {
		const amount = 1;
		const minAmount = 0.001; // 0.001 * 20000 = 20 usdc
		const borrowLimit = Math.min((minAmount/amount - 1)/3 + 1, 0.9);
		const loops = Math.floor(Math.log(minAmount/amount) / Math.log(borrowLimit));
		const leverage = (1 - (minAmount/amount))/(1-borrowLimit)
		const exchangeRate = 20000;
		const liquidationExchangeRate = exchangeRate * borrowLimit;
		console.log('liquidationExchangeRate:', `$${liquidationExchangeRate}`, 'leverage:', leverage+'x');
		console.log('borrowLimit:', borrowLimit, 'loops:', loops);

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
			],
		};

		// The data to sign
		const value = {
			maker: user1.address,
			token0: btc.address, 
            token1: usdc.address,
			amount: ethers.utils.parseEther('1').toString(),
			orderType: 2, // long
            salt: '12345',
            exchangeRate: ethers.utils.parseEther('20000'),
            borrowLimit: 0.77 * 1e6, // borrowLimit * 1e6,
            loops: 5 // loops,
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
		expect(await exchange.verifyOrderHash(storedSignature, value)).to.equal(hash);
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
        
        // 0.75 BTC + 0.56 BTC + 0.42 BTC + 0.27 (0.312) = 2 BTC
		// 4 
		// 0.27
		// 0.312 - 0.27 = 0.042
		const btcAmount = ethers.utils.parseEther('2');
		let tx = await exchange.connect(user2).executeLimitOrders(
            [signatures[0]],
            [orders[0]],
			btcAmount
		);

		// tx = await tx.wait(1);

		expect(tx).to.emit(exchange, 'OrderExecuted').withArgs([orderIds[0]], [btcAmount], [ethers.utils.parseEther('40000')]);
		
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
		await exchange.connect(user2).executeLimitOrders(
            [signatures[0]],
            [orders[0]],
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
		await exchange.connect(user2).executeLimitOrders(
            [signatures[0]],
            [orders[0]],
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
        
		await exchange.connect(user2).executeLimitOrders(
            [signatures[0]],
            [orders[0]],
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
		expect(await btc.balanceOf(user1.address)).to.closeTo(user1FinalBalance, ethers.utils.parseEther("0.0001"));
		expect(await btc.balanceOf(user2.address)).to.closeTo(user2BtcBalance.sub(finalBtcAmountSold), ethers.utils.parseEther("0.1"));
		// user1 usdc balance
		user1UsdcBalance = await usdc.balanceOf(user1.address);
		expect(user1UsdcBalance).to.equal(ethers.utils.parseEther('0'));
		// user2 usdc balance
		user2UsdcBalance = await usdc.balanceOf(user2.address);
		expect(user2UsdcBalance).to.closeTo(finalBtcAmountSold.mul(orders[0].exchangeRate).div(ethers.constants.WeiPerEther), ethers.utils.parseEther("100"));
	})
});