const { ethers, network, artifacts, upgrades } = require("hardhat");



module.exports = async ({ deployments }) => {
  const { deploy } = deployments;
  const [deployer] = await ethers.getSigners();

  
  let impl = await deploy("MirrorVault", {
    from: deployer.address,
  })
  
  let implAddress = await ethers.getContract("MirrorVault")
  console.log('Implementation address', implAddress.address)

};

module.exports.tags = ["mirror_mainnet_deploy_impl"];