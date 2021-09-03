const { ethers, network, artifacts, upgrades } = require("hardhat");
const { mainnet: network_ } = require("../../addresses");

const pid = 18
const type = 0
const curvePoolAddr = "0x7F55DDe206dbAD629C080068923b36fe9D6bDBeF"
const curvePoolZap = "0x11F419AdAbbFF8d595E7d5b223eee3863Bb3902C"
module.exports = async ({ deployments }) => {
    const { deploy, catchUnknownSigner } = deployments;
    const [deployer] = await ethers.getSigners();

    let Factory = await ethers.getContract("EarnStrategyFactory")

    const zap = await ethers.getContract("CurveMetaPoolBTCZap", deployer)
    
    let implArtifacts = await artifacts.readArtifact("EarnVault")
    
    let implABI = implArtifacts.abi


    let implInterfacec = new ethers.utils.Interface(implABI)

    let data = implInterfacec.encodeFunctionData("initialize", [ zap.address,
        network_.treasury, network_.community,
        network_.admin, network_.strategist, pid, type])
    
    
    await Factory.connect(deployer).createVault(data)
    
    const vaultProxy = await Factory.getVault((await Factory.totalVaults()).toNumber() - 1)
 
    await zap.addPool(vaultProxy, curvePoolAddr, curvePoolZap)


};

module.exports.tags = ["earn_mainnet_deploy_vault_pbtc"];
module.exports.dependencies = ["earn_mainnet_deploy_factory"]