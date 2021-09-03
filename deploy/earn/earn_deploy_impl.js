const { ethers, network, artifacts, upgrades } = require("hardhat");


module.exports = async ({ deployments }) => {
  const { deploy } = deployments;
  const [deployer] = await ethers.getSigners();

  
  let impl = await deploy("EarnVault", {
    from: deployer.address,
  })
  
  let implAddress = await ethers.getContract("EarnVault")
  console.log('Implementation address', implAddress.address)
};

module.exports.tags = ["earn_mainnet_deploy_impl"];