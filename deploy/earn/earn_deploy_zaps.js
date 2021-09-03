const { ethers, network, artifacts, upgrades } = require("hardhat");
const { mainnet: network_ } = require("../../addresses");


module.exports = async ({ deployments }) => {
  const { deploy, catchUnknownSigner } = deployments;
  const [deployer] = await ethers.getSigners();

  let CurveLendingPool3Zap = await deploy("CurveLendingPool3Zap", {
    from: deployer.address,
  })

  let CurveMetaPoolFacZap = await deploy("CurveMetaPoolFacZap", {
    from: deployer.address,
  })

  let CurvePlainPoolETHZap = await deploy("CurvePlainPoolETHZap", {
    from: deployer.address,
  })

  let CurveMetaPoolBTCZap = await deploy("CurveMetaPoolBTCZap", {
    from: deployer.address,
  })

  let CurveHBTCZap = await deploy("CurveHBTCZap", {
    from: deployer.address,
  })

  let CurveLendingPool2Zap = await deploy("CurveLendingPool2Zap", {
    from: deployer.address,
  })

  let CurveSBTCZap = await deploy("CurveSBTCZap", {
    from: deployer.address,
  })
  
  let CurvePlainPoolZap = await deploy("CurvePlainPoolZap", {
    from: deployer.address,
  })

  let CurveMetaPoolZap = await deploy("CurveMetaPoolZap", {
    from: deployer.address,
  })

  let CurveYZap = await deploy("CurveYZap", {
    from: deployer.address,
  })
  

  

  
  console.log('CurveLendingPool3Zap deployed to ', CurveLendingPool3Zap.address)
  console.log('CurveMetaPoolFacZap deployed to ', CurveMetaPoolFacZap.address)
  console.log('CurvePlainPoolETHZap deployed to ', CurvePlainPoolETHZap.address)
  console.log('CurveMetaPoolBTCZap deployed to ', CurveMetaPoolBTCZap.address)
  console.log('CurveHBTCZap deployed to ', CurveHBTCZap.address)
  console.log('CurveLendingPool2Zap deployed to ', CurveLendingPool2Zap.address)
  console.log('CurveSBTCZap deployed to ', CurveSBTCZap.address)
  console.log('CurvePlainPoolZap deployed to ', CurvePlainPoolZap.address)
  console.log('CurveMetaPoolZap deployed to ', CurveMetaPoolZap.address)
  console.log('CurveYZap deployed to ', CurveYZap.address)

};

module.exports.tags = ["earn_mainnet_deploy_zaps"];