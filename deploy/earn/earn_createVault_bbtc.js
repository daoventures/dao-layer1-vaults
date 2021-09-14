const { ethers, network, artifacts, upgrades } = require("hardhat");
const { mainnet: network_ } = require("../../addresses");

const pid = 19
const type = 0
const curvePoolAddr = "0x071c661B4DeefB59E2a3DdB20Db036821eeE8F4b"
const curvePoolZap = "0xC45b2EEe6e09cA176Ca3bB5f7eEe7C47bF93c756"
module.exports = async ({ deployments }) => {
    const { deploy, catchUnknownSigner } = deployments;
    const [deployer] = await ethers.getSigners();

    let Factory = await ethers.getContract("EarnStrategyFactory")

    const zap = await ethers.getContract("CurveMetaPoolBTCZap", deployer)
    
    let implArtifacts = await artifacts.readArtifact("EarnVault")
    
    let implABI = implArtifacts.abi


    let implInterfacec = new ethers.utils.Interface(implABI)

    let data = implInterfacec.encodeFunctionData("initialize", ["DAO Earn", "daoERN",zap.address,
        network_.treasury, network_.community,
        network_.admin, network_.strategist, pid, type, true])
    
    
    await Factory.connect(deployer).createVault(data)
    
    const vaultProxy = await Factory.getVault((await Factory.totalVaults()).toNumber() - 1)
 
    await zap.addPool(vaultProxy, curvePoolAddr, curvePoolZap)


};

module.exports.tags = ["earn_mainnet_deploy_vault_bbtc"];
module.exports.dependencies = ["earn_mainnet_deploy_factory"]