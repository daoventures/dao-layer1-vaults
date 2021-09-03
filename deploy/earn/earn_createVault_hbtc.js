const { ethers, network, artifacts, upgrades } = require("hardhat");
const { mainnet: network_ } = require("../../addresses");

const pid = 8
const type = 0
const curvePoolAddr = "0x4CA9b3063Ec5866A4B82E437059D2C43d1be596F"

module.exports = async ({ deployments }) => {
    const { deploy, catchUnknownSigner } = deployments;
    const [deployer] = await ethers.getSigners();

    let Factory = await ethers.getContract("EarnStrategyFactory")

    const zap = await ethers.getContract("CurveHBTCZap", deployer)
    
    let implArtifacts = await artifacts.readArtifact("EarnVault")
    
    let implABI = implArtifacts.abi


    let implInterfacec = new ethers.utils.Interface(implABI)

    let data = implInterfacec.encodeFunctionData("initialize", [ zap.address,
        network_.treasury, network_.community,
        network_.admin, network_.strategist, pid, type])
    
    
    await Factory.connect(deployer).createVault(data)
    
    const vaultProxy = await Factory.getVault((await Factory.totalVaults()).toNumber() - 1)

    await zap.addPool(vaultProxy, curvePoolAddr)


};

module.exports.tags = ["earn_mainnet_deploy_vault_hbtc"];
module.exports.dependencies = ["earn_mainnet_deploy_factory"]