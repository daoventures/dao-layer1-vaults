const { ethers, network, artifacts, upgrades } = require("hardhat");
const { mainnet: network_ } = require("../../addresses/bsc");


module.exports = async ({ deployments }) => {
    const { deploy, catchUnknownSigner } = deployments;
    const [deployer] = await ethers.getSigners();

    let Factory = await ethers.getContract("BscVaultFactory")


    let implArtifacts = await artifacts.readArtifact("BscVault")

    let implABI = implArtifacts.abi


    let implInterfacec = new ethers.utils.Interface(implABI)
    let data = implInterfacec.encodeFunctionData("initialize", ["DAO L1 pnck bnb-xvs", "daopnckBNB_XVS",
        network_.PID.BNB_XVS, 
        network_.ADDRESSES.treasuryWallet, network_.ADDRESSES.communityWallet, network_.ADDRESSES.strategist, network_.ADDRESSES.adminAddress])

    await Factory.connect(deployer).createVault(data)
    const vaultProxyAddress = await Factory.getVault((await Factory.totalVaults()).toNumber() - 1)

    console.log("BNB_XVS Proxy :", vaultProxyAddress);


};

module.exports.tags = ["bsc_mainnet_deploy_pool_bnb_xvs"];
module.exports.dependencies = ["bsc_mainnet_deploy_factory"]