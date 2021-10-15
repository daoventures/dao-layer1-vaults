const { run, ethers } = require('hardhat')
const { mainnet: network_ } = require("../../addresses/bsc");

const l1VaultProxy = "" //address of l1 proxy vault //"0xcB2dbBE8bD45F7b2aCDe811971DA2f64f1Bfa6CB"
const beaconAddress = "0x3eFcc3443C5E54edA85250d5A14D57560B648671"

module.exports = async () => {
    // const Factory = await ethers.getContract("BscVaultFactory")
    const implementation = await ethers.getContract("BscVault")

    let implArtifacts = await artifacts.readArtifact("BscVault")

    let implABI = implArtifacts.abi

    // let provider = new ethers.providers.JsonRpcProvider(process.env.ALCHEMY_URL_MAINNET)

    // const beaconAddress = await provider.getStorageAt(l1VaultProxy, "0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50")
    // console.log("beaconAddress", beaconAddress)

    let implInterfacec = new ethers.utils.Interface(implABI)
    let data = implInterfacec.encodeFunctionData("initialize", ["DAO L1 pnck alpaca-busd", "daopnckALPACA_BUSD",
        network_.PID.ALPACA_BUSD, 
        network_.ADDRESSES.treasuryWallet, network_.ADDRESSES.communityWallet, network_.ADDRESSES.strategist, network_.ADDRESSES.adminAddress])


    await run("verify:verify", {
        address: l1VaultProxy,
        constructorArguments: [
            beaconAddress,
            data
        ],
        contract: "contracts/BSCL1/verify/Proxy.sol:BeaconProxy"
    })
}

module.exports.tags = ["bsc_verify_proxy"]