const { ethers, network, artifacts, upgrades } = require("hardhat");
const { mainnet: network_ } = require("../../addresses");

const pid = 7
const type = 0
const curvePoolAddr = "0x7fC77b5c7614E1533320Ea6DDc2Eb61fa00A9714"

module.exports = async ({ deployments }) => {
    const { deploy, catchUnknownSigner } = deployments;
    const [deployer] = await ethers.getSigners();

    let Factory = await ethers.getContract("EarnStrategyFactory")

    const zap = await ethers.getContract("CurveSBTCZap", deployer)
    
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

module.exports.tags = ["earn_mainnet_deploy_vault_sbtc"];
module.exports.dependencies = ["earn_mainnet_deploy_factory"]