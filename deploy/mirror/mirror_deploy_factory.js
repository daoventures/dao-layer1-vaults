const { ethers, network, artifacts, upgrades } = require("hardhat");



module.exports = async ({ deployments }) => {
  const { deploy, catchUnknownSigner } = deployments;
  const [deployer] = await ethers.getSigners();

  let impl = await ethers.getContract("MirrorVault")

  let factory = await deploy("MirrorFactory", {
    from: deployer.address,
    args: [impl.address]
  })

  console.log('Factory deployed to ', factory.address)

};

module.exports.tags = ["mirror_mainnet_deploy_factory"];
module.exports.dependencies = ["mirror_mainnet_deploy_impl"]