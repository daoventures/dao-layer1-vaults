const { ethers, network, artifacts, upgrades } = require("hardhat");



module.exports = async ({ deployments }) => {
  const { deploy } = deployments;
  const [deployer] = await ethers.getSigners();

  
  let impl = await deploy("BscVault", {
    from: deployer.address,
  })
  
  let implAddress = await ethers.getContract("BscVault")
  console.log('Implementation address', implAddress.address)

};

module.exports.tags = ["bsc_mainnet_deploy_impl"];