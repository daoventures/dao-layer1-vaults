const { ethers, network, artifacts, upgrades } = require("hardhat");
const { mainnet: network_ } = require("../../addresses");

const pid = 26
const type = 2
const curvePoolAddr = "0xEB16Ae0052ed37f479f7fe63849198Df1765a733"

module.exports = async ({ deployments }) => {
    const { deploy, catchUnknownSigner } = deployments;
    const [deployer] = await ethers.getSigners();

    let Factory = await ethers.getContract("EarnStrategyFactory")

    const zap = await ethers.getContract("CurveLendingPool2Zap", deployer)
    
    let implArtifacts = await artifacts.readArtifact("EarnVault")
    
    let implABI = implArtifacts.abi


    let implInterfacec = new ethers.utils.Interface(implABI)

    let data = implInterfacec.encodeFunctionData("initialize", ["DAO Earn", "daoERN",zap.address,
        network_.treasury, network_.community,
        network_.admin, network_.strategist, pid, type, true])
    
    
    await Factory.connect(deployer).createVault(data)
    
    const vaultProxy = await Factory.getVault((await Factory.totalVaults()).toNumber() - 1)

    await zap.addPool(vaultProxy, curvePoolAddr)


};

module.exports.tags = ["earn_mainnet_deploy_vault_saave"];
module.exports.dependencies = ["earn_mainnet_deploy_factory"]