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
|    BTCB_BNB                    | [0x643E7A44F5d3F3A0939eCfe464a277DCAcB5BaB3](https://bscscan.com/address/0x643E7A44F5d3F3A0939eCfe464a277DCAcB5BaB3)
