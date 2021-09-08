const { ethers, network, artifacts, upgrades } = require("hardhat");
const { mainnet: network_ } = require("../../addresses/mirror");


module.exports = async ({ deployments }) => {
    const { deploy, catchUnknownSigner } = deployments;
    const [deployer] = await ethers.getSigners();

    let Factory = await ethers.getContract("MirrorFactory")


    let implArtifacts = await artifacts.readArtifact("MirrorVault")

    let implABI = implArtifacts.abi


    let implInterfacec = new ethers.utils.Interface(implABI)
    let data = implInterfacec.encodeFunctionData("initialize", ["DAOVaultETHUSDC", "daoETHUSDC",
        network_.MIRROR.mAMZN_UST_POOL, network_.TOKENS.mAMZN, network_.LPTOKENS.mAMZN_UST,
        network_.ADDRESSES.treasuryWallet, network_.ADDRESSES.communityWallet, network_.ADDRESSES.strategist, network_.ADDRESSES.adminAddress])

    await Factory.connect(deployer).createVault(data)
    const vaultProxyAddress = await Factory.getVault((await Factory.totalVaults()).toNumber() - 1)

    console.log("mAMZN_UST Proxy :", vaultProxyAddress);


};

module.exports.tags = ["mirror_mainnet_deploy_pool_mamzn_ust"];
module.exports.dependencies = ["mirror_mainnet_deploy_factory"]