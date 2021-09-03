const { ethers, network, artifacts, upgrades } = require("hardhat");
const { mainnet: network_ } = require("../../addresses");

const pid = 20
const type = 0
const curvePoolAddr = "0xd81dA8D904b52208541Bade1bD6595D8a251F8dd"
const curvePoolZap = "0xd5BCf53e2C81e1991570f33Fa881c49EEa570C8D"
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

module.exports.tags = ["earn_mainnet_deploy_vault_obtc"];
module.exports.dependencies = ["earn_mainnet_deploy_factory"]