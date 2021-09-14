# DAO Earn

DAO Earn vault series utilize Curve and Convex protocols to get APY. In high-level, DAO Earn do compounding by sell $CRV, $CVX, and any extra reward from Curve pool to buy more LP token and stake into Convex again.

#### Reward Tokens: CRV, CVX, + other tokens for some vaults
## DAO Earn (USD based - 9 products):-

### Deposit and Withdraw token:-

Product Name | Token to deposit 
--------- | -------------------------- 
LUSD | [LP Token (LUSD3CRV-f)](https://etherscan.io/address/0xEd279fDD11cA84bEef15AF5D39BB4d4bEE23F0cA)
BUSDv2 | [LP Token (BUSD3CRV-f)](https://etherscan.io/address/0x4807862AA8b2bF68830e4C8dc86D0e9A998e085a)
alUSD | [LP Token (alUSD3CRV-f)](https://etherscan.io/address/0x43b4FdFD4Ff969587185cDB6f0BD875c5Fc83f8c)
UST | [LP Token (ust3CRV)](https://etherscan.io/address/0x94e131324b6054c0D789b190b2dAC504e4361b53)
USDN | [LP Token (usdn3CRV)](https://etherscan.io/address/0x4f3E8F405CF5aFC05D68142F3783bDfE13811522)
sUSD | [LP Token (crvPlain3andSUSD)](https://etherscan.io/address/0xC25a3A3b969415c80451098fa907EC722572917F)
Yearn | [LP Token (yDAI+yUSDC+yUSDT+yTUSD)](https://etherscan.io/address/0xdF5e0e81Dff6FAF3A7e52BA697820c5e32D806A8)
AAVE | [LP Token (a3CRV)](https://etherscan.io/address/0xFd2a8fA60Abd58Efe3EeE34dd494cD491dC14900)
sAAVE | [LP Token (saCRV)](https://etherscan.io/address/0x02d341CcB60fAaf662bC0554d13778015d1b285C)


## DAO Earn (BTC based - 6 products):-

Product Name | Token to deposit 
--------- | -------------------------- 
BBTC | [LP Token (bBTC/sbtcCRV)](https://etherscan.io/address/0x410e3E86ef427e30B9235497143881f717d93c2A)
PBTC | [LP Token (pBTC/sbtcCRV)](https://etherscan.io/address/0xDE5331AC4B3630f94853Ff322B66407e0D6331E8)
OBTC | [LP Token (oBTC/sbtcCRV)](https://etherscan.io/address/0x2fE94ea3d5d4a175184081439753DE15AeF9d614)
TBTC | [LP Token (tbtc/sbtcCrv)](https://etherscan.io/address/0x64eda51d3Ad40D56b9dFc5554E06F94e1Dd786Fd)
sBTC | [LP Token (crvRenWSBTC)](https://etherscan.io/address/0x075b1bb99792c9E1041bA13afEf80C91a1e70fB3)
HBTC | [LP Token (hCRV)](https://etherscan.io/address/0xb19059ebb43466C323583928285a49f558E572Fd)

## DAO Earn (ETH based - 6 products):-

Product Name | Token to deposit 
--------- | -------------------- 
stETH | [LP Token (steCRV)](https://etherscan.io/address/0x06325440D014e39736583c165C2963BA99fAf14E)
ankrETH | [LP Token (ankrCRV)](https://etherscan.io/address/0xaA17A236F2bAdc98DDc0Cf999AbB47D47Fc0A6Cf)
rETH | [LP Token (rCRV)](https://etherscan.io/address/0x53a901d48795C58f485cBB38df08FA96a24669D5)

## Params in Deploy script

#### _name
    - Name of lpToken

#### _symbol, 
    - Symbol of lpToken

#### _curveZap
    - address of curveZap contract

#### _treasuryWallet
    - address of treasury wallet
#### _communityWallet,
    - address of community wallet
#### _admin
    - address of admin wallet
#### _strategist,
    - address of strategist 
#### _pid_ 
    - pool id of the farm in convex

#### _type 
    - Yield Rewards are swapped to ETH. 
    type = 0 will collect extra rewards and swaps it in sushiswap 
    type = 1 is used in aave strategy, to swap _stkAAVE in uniswap V3 
    type = 2 will collect extra rewards and swaps it in uniswap v2 

#### _feeOn 
    - true to enable deposit fees
    - if set to false, deposit fee will not be collected from both whitelisted and non withelisted addreses

## Deployment
To deploy vault,
```
    npx hardhat --network mainnet deploy --tags earn_mainnet_deploy_vault_PRODUCT-NAME
```

This will deploy the factory and implementation, if they are not deployed already.

Please push the deployments directory to repo after every deployment.