const { ethers, network, artifacts, upgrades } = require("hardhat");
const { mainnet: network_ } = require("../../addresses/bsc");

const L1proxyAddress = "" //address of L1 proxy vault
const safuVaultProxyAddress = "" //address of proxy safu vault

module.exports = async ({ deployments }) => {
    const [deployer] = await ethers.getSigners();

    let implArtifacts = await artifacts.readArtifact("BscVault")
    const vault = await ethers.getContractAt(implArtifacts.abi, L1proxyAddress, deployer)

    await vault.setWhitelist(safuVaultProxyAddress, true)

    console.log("Whitelisted successfully")
}

module.exports.tags = ["bscL1_whitelist"]