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
|    Factory                     | [address](https://bscscan.com)
|    Implemenation               | [address](https://bscscan.com)
|    BTCB_ETH                    | [address](https://bscscan.com)