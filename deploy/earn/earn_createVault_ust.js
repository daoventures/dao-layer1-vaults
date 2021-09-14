const { ethers, network, artifacts, upgrades } = require("hardhat");
const { mainnet: network_ } = require("../../addresses");

const pid = 21
const type = 0
const curvePoolAddr = "0x890f4e345B1dAED0367A877a1612f86A1f86985f"
const curvePoolZap = "0xB0a0716841F2Fc03fbA72A891B8Bb13584F52F2d"

module.exports = async ({ deployments }) => {
    const { deploy, catchUnknownSigner } = deployments;
    const [deployer] = await ethers.getSigners();

    let Factory = await ethers.getContract("EarnStrategyFactory")

    const zap = await ethers.getContract("CurveMetaPoolZap", deployer)
    
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

module.exports.tags = ["earn_mainnet_deploy_vault_ust"];
module.exports.dependencies = ["earn_mainnet_deploy_factory"]