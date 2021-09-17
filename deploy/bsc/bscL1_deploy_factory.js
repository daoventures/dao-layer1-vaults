const { ethers, network, artifacts, upgrades } = require("hardhat");



module.exports = async ({ deployments }) => {
  const { deploy, catchUnknownSigner } = deployments;
  const [deployer] = await ethers.getSigners();

  let impl = await ethers.getContract("BscVault")

  let factory = await deploy("BscVaultFactory", {
    from: deployer.address,
    args: [impl.address]
  })

  console.log('Factory deployed to ', factory.address)

};

module.exports.tags = ["bsc_mainnet_deploy_factory"];
module.exports.dependencies = ["bsc_mainnet_deploy_impl"]