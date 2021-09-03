const { ethers, network, artifacts, upgrades } = require("hardhat");
const { mainnet: network_ } = require("../../addresses");


module.exports = async ({ deployments }) => {
  const { deploy, catchUnknownSigner } = deployments;
  const [deployer] = await ethers.getSigners();

  let impl = await ethers.getContract("EarnVault")

  let factory = await deploy("EarnStrategyFactory", {
    from: deployer.address,
    args: [impl.address]
  })

  console.log('Factory deployed to ', factory.address)

};

module.exports.tags = ["earn_mainnet_deploy_factory"];
module.exports.dependencies = ["earn_mainnet_deploy_impl", "earn_mainnet_deploy_zaps"]