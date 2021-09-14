const { ethers, network, artifacts, upgrades } = require("hardhat");
const { mainnet: network_ } = require("../../addresses");

const pid = 2
const type = 0
const curvePoolAddr = "0x45F783CCE6B7FF23B2ab2D70e416cdb7D6055f51"
const curvePoolZap = "0xbBC81d23Ea2c3ec7e56D39296F0cbB648873a5d3" 

module.exports = async ({ deployments }) => {
    const { deploy, catchUnknownSigner } = deployments;
    const [deployer] = await ethers.getSigners();

    let Factory = await ethers.getContract("EarnStrategyFactory")

    const zap = await ethers.getContract("CurveYZap", deployer)
    
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

module.exports.tags = ["earn_mainnet_deploy_vault_y"];
module.exports.dependencies = ["earn_mainnet_deploy_factory"]