const { ethers, network, artifacts, upgrades } = require("hardhat");
const { mainnet: network_ } = require("../../addresses/bsc");


module.exports = async ({ deployments }) => {
    const { deploy, catchUnknownSigner } = deployments;
    const [deployer] = await ethers.getSigners();

    let Factory = await ethers.getContract("BscVaultFactory")


    let implArtifacts = await artifacts.readArtifact("BscVault")

    let implABI = implArtifacts.abi


    let implInterfacec = new ethers.utils.Interface(implABI)
    let data = implInterfacec.encodeFunctionData("initialize", ["DAO L1 pnck btcb-busd", "daopnckBTCB_BUSD",
        network_.PID.BTCB_BUSD, 
        network_.ADDRESSES.treasuryWallet, network_.ADDRESSES.communityWallet, network_.ADDRESSES.strategist, network_.ADDRESSES.adminAddress])

    await Factory.connect(deployer).createVault(data)
    const vaultProxyAddress = await Factory.getVault((await Factory.totalVaults()).toNumber() - 1)

    console.log("BTCB-BUSD Proxy :", vaultProxyAddress);


};

module.exports.tags = ["bsc_mainnet_deploy_pool_btcb_busd"];
module.exports.dependencies = ["bsc_mainnet_deploy_factory"]