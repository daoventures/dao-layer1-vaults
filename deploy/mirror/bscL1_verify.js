const { run, ethers } = require('hardhat')


module.exports = async () => {
    const Factory = await ethers.getContract("BscVaultFactory")
    const implementation = await ethers.getContract("BscVault")

    // await run("verify:verify", {
    //     address: "0x5f60c2791BFA37955D067D7576B90Fe96ef80bd0",
    //     constructorArguments: [
    //         "0xDED9Fa2257751F74892f71D98cCB4CcB79238D71",
    //         "0x8319833400000000000000000000000000000000000000000000000000000000000001200000000000000000000000000000000000000000000000000000000000000160000000000000000000000000735659c8576d88a2eb5c810415ea51cb06931696000000000000000000000000d36932143f6ebdedd872d5fb0651f4b72fd15a84000000000000000000000000b022e08adc8ba2de6ba4fecb59c6d502f66e953b00000000000000000000000059e83877bd248cbfe392dbb5a8a29959bcb48592000000000000000000000000dd6c35aff646b2fb7d8a8955ccbe0994409348d000000000000000000000000054d003d451c973ad7693f825d5b78adfc0efe9340000000000000000000000003f68a3c1023d736d8be867ca49cb18c543373b99000000000000000000000000000000000000000000000000000000000000000f44414f5661756c74455448555344430000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a64616f4554485553444300000000000000000000000000000000000000000000"
    //     ],
    //     contract: "contracts/mirror/Proxy.sol:BeaconProxy"
    // })
    await run("verify:verify", {
        address: Factory.address,
        constructorArguments: [implementation.address]
    })

    await run("verify:verify", {
        address: implementation.address
    })
}

module.exports.tags = ["bsc_verify"]