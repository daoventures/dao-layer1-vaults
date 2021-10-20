# BSC Layer1 Vaults

Vault uses beacon proxy pattern. 
Upgrading the implementation will upgrade all the vaults created from the factory.

Factory's owner is the deployer.

`vault's ownership` will be transferred to `factory's owner` at the time of vault creation.

## To deploy a Vault

```
npx hardhat deploy--network mainnet --tags bsc_mainnet_deploy_pool_alpaca_busd
```

- Tags needs to be updated to deploy other vaults
- `Please push deployments directory to git after every deployment`

### BSCscan Verification

```
npx hardhat deploy --network mainnet --tags bsc_verify
```



## Addresses - TODO after deployment

| Name                           | address            
|:-------------------------------|-------------------------------:|
|    Factory                     | [0x68b7b9D45D70496b9C0e449AD82c4Fda3ad8AfD5](https://bscscan.com/address/0x68b7b9D45D70496b9C0e449AD82c4Fda3ad8AfD5)
|    Implemenation               | [0xE0245d079295246e570894ec6014713ED276efF3](https://bscscan.com/address/0xE0245d079295246e570894ec6014713ED276efF3)
|    BTCB_ETH                    | [0xcB2dbBE8bD45F7b2aCDe811971DA2f64f1Bfa6CB](https://bscscan.com/address/0xcB2dbBE8bD45F7b2aCDe811971DA2f64f1Bfa6CB)
|    BTCB_BNB                    | [0xDB05ab97d695F6d881130aEed5B5C66186144bd8](https://bscscan.com/address/0xDB05ab97d695F6d881130aEed5B5C66186144bd8)
|    CAKE_BNB                    | [0x97511560b4f6239C717B3bB47A4227Ba7691E33c](https://bscscan.com/address/0x97511560b4f6239C717B3bB47A4227Ba7691E33c)
|    BTCD_BUSD                   | [0x204DD790bA0D7990246D32e59C30fcB01acc224C](https://bscscan.com/address/0x204DD790bA0D7990246D32e59C30fcB01acc224C)
|    USDC_CHESS                  | [0xae4566AA6271F066A085aF605691629BFB8182f9](https://bscscan.com/address/0xae4566AA6271F066A085aF605691629BFB8182f9)
|    BNB_XVS                     | [0x5633112d760953c4b418e25f46D4b2ABb3FB1B48](https://bscscan.com/address/0x5633112d760953c4b418e25f46D4b2ABb3FB1B48)
|    BNB_BELT                    | [0x03dADc2ca6aFea0522C21973b24D409ABA4F3AcE](https://bscscan.com/address/0x03dADc2ca6aFea0522C21973b24D409ABA4F3AcE)
|    ALPACA_BUSD                 | [0x8666bc8b5e4b5c2Eb6D2B438De392eDd3A1F8547](https://bscscan.com/address/0x8666bc8b5e4b5c2Eb6D2B438De392eDd3A1F8547)
