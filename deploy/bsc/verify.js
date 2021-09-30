const {run, ethers} = require("hardhat")

module.exports = async() => {

    const factory = await ethers.getContract("BscVaultFactory")
    const impl = await ethers.getContract("BscVault")

    await run("verify:verify", {
        address : factory.address,
        contract: "contracts/BSCL1/Factory.sol:BscVaultFactory",
        constructorArguments: [impl.address]
    })

    await run("verify:verify", {
        address : impl.address,
        contract: "contracts/BSCL1/vault.sol:BscVault"
    })
}

module.exports.tags = ["bsc_verify"]