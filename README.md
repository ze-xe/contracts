# ZEXE Contracts
Version 0.0.1

### Compile
`npx hardhat compile`
### Test
`npx hardhat test`
### Deploy
`npx hardhat run scripts`


## Inspiration

It seems like every week there's some new story about how the people behind a centralized cryptocurrency exchange have absconded with funds, been hacked, or mismanaged the money in some other way. There's no reason to think that these cases will become any less frequent going forward, either.
It is becoming more obvious than ever that a decentralized trading platform is both possible and desirable where—rather than trusting a company to hold your funds and execute trades on your behalf, users can retain control of their own private keys. We can even do it so as to minimize fees and remove centralized points of potential failure. Furthermore, we want our platform to be owned by its users: the platform should operate in a manner that is aligned with its users' interests. The most important feature of this system is that we make it trustless: no one can act maliciously without being revealed or otherwise punished for it.
But despite the advantages of DEXes over centralization—namely that they're open source, transparent and trustless—there are still some pain points that prevent them from gaining mass adoption. They currently lack UI/UX niceties that make navigating centralized exchanges like Coinbase or Gemini feel effortless, and they have limited functionality; most decentralized exchanges only offer basic market orders instead of advanced options like limit orders, stop-loss, leverage trading and much more, that are essential for traders.

## What it does
zexe is a decentralized platform where traders can access spot trading, futures, perpetual contracts and options all under one roof. We've developed three key features that all work seamlessly together. They are:

1. Spot Trading

Spot trading is your typical trade where you buy and sell an instrument in real time as its value changes. zexe offers both limit and market orders—the former will let you set the exact price you want to pay or receive, while the latter will fill your order as quickly as possible at whatever price is available immediately. The stop loss feature lets you set a minimum/maximum price for your position, so if it goes below that minimum or above that maximum, you'll automatically sell your position and take a loss instead of letting it continue to go downhill.

2. Margin and perpetual trading

On zexe's margin and perpetual trading platform, you can trade equities and futures by pledging your collateral assets as margin or collateral to leverage your trades. With 10x leverage on margin and futures trades, you can make your trades more aggressive than ever before. Perpetuals trading gives users the ability to buy or sell an asset at a specified price for a specified amount of time. This means that traders can take advantage of upswings in the market without worrying about exiting their positions before they have time to recoup their profits. It also allows them to hedge against unexpected price changes if they're holding an asset they want to sell in a few months' time or if they want guaranteed access to cash in the short term while still making money if prices rise.

3. Option calls
Diversify your portfolio across several assets using option calls: zexe allows you to buy puts or calls on equities and futures to increase the potential returns or reduce the risk associated with your overall portfolio.

## How we built it
The zexe platform itself is made up of three layers: an off-chain order book, an on-chain settlement layer, and an on-chain management layer that manages the governance of its contract.

![System](https://raw.githubusercontent.com/ze-xe/contracts-0.1/main/uml/system.png)

#### Contracts:
https://github.com/ze-xe/contracts

1. Vault.sol: Users can Deposit/Withdraw tokens. Using a vault is more gas efficient than transferring tokens from their wallet

2. Exchange.sol: Users can create, update and execute orders from this contract

![ContractsUML](https://raw.githubusercontent.com/ze-xe/contracts-0.1/main/uml/outputFile.svg)

#### Backend:
https://github.com/ze-xe/backend

#### Frontend
https://github.com/ze-xe/frontend


## Challenges we ran into

## Accomplishments that we're proud of

## What we learned

## What's next for zexe
- Perpetual trading
- Launch on Testnet by EOY
- Mainnet launch by Q1 23