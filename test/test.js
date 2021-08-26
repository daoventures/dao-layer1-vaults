const { ethers, artifacts, network } = require("hardhat")
const IERC20_ABI = require("../abis/IERC20_ABI.json")

const ILVETHAddr = "0x6a091a3406E0073C3CD6340122143009aDac0EDa"
const unlockedAccAddr = "0xafda0872177cae4336a16597f5d2f65d254a74c2"

describe("Sushi-ILVETH", () => {
    it("should work", async () => {
        let tx, receipt
        const [deployer, client1, client2, client3] = await ethers.getSigners()

        await network.provider.request({method: "hardhat_impersonateAccount", params: [unlockedAccAddr]})
        const unlockedAcc = await ethers.getSigner(unlockedAccAddr)

        // await deployer.sendTransaction({to: unlockedAccAddr, value: ethers.utils.parseEther("1")})

        const ILVETHVaultFac = await ethers.getContractFactory("ILVETHVault", deployer)
        const ILVETHVault = await ILVETHVaultFac.deploy()
        await ILVETHVault.initialize("DAO L1 Sushi ILV-ETH", "daoSushiILV")
        await ILVETHVault.setWhitelistAddress(client1.address, true)
        await ILVETHVault.setWhitelistAddress(client2.address, true)

        const ILVETHContract = new ethers.Contract(ILVETHAddr, IERC20_ABI, unlockedAcc)
        await ILVETHContract.transfer(client1.address, ethers.utils.parseEther("1"))
        await ILVETHContract.transfer(client2.address, ethers.utils.parseEther("1"))
        // await ILVETHContract.transfer(client3.address, ethers.utils.parseEther("1"))

        await ILVETHContract.connect(client1).approve(ILVETHVault.address, ethers.constants.MaxUint256)
        await ILVETHVault.connect(client1).deposit(ethers.utils.parseEther("1"))
        await ILVETHVault.invest()
        await ILVETHVault.harvest()
        await network.provider.send("evm_increaseTime", [365*86400/2+1])

        await ILVETHContract.connect(client2).approve(ILVETHVault.address, ethers.constants.MaxUint256)
        await ILVETHVault.connect(client2).deposit(ethers.utils.parseEther("1"))
        await ILVETHVault.invest()

        // await ILVETHContract.connect(client3).approve(ILVETHVault.address, ethers.constants.MaxUint256)
        // await ILVETHVault.connect(client3).deposit(ethers.utils.parseEther("1"))
        // console.log(ethers.utils.formatEther(await ILVETHVault.fees()))

        
        console.log(ethers.utils.formatEther(await ILVETHVault.getAllPool())) // 2.000185693989767422
        console.log(ethers.utils.formatEther(await ILVETHVault.getAllPoolInETH())) // 1.564927246207681752
        console.log(ethers.utils.formatEther(await ILVETHVault.getAllPoolInUSD())) // 4854.986335008275079844
        console.log(ethers.utils.formatEther(await ILVETHVault.getAllPoolInETHExcludeVestedILV())) // 1.564781960904963486
        console.log(ethers.utils.formatEther(await ILVETHVault.getPricePerFullShare(true))) // 2427.546198215187271096
        console.log(ethers.utils.formatEther(await ILVETHVault.getPricePerFullShare(false))) // 1.000114694897692193

        // for (let i=0; i<10000; i++) {
        //     await network.provider.send("evm_mine")
        // }
        await ILVETHVault.harvest()
        await network.provider.send("evm_increaseTime", [365*86400/2+1])
        await ILVETHVault.unlock(0)
        await ILVETHVault.compound()
        await ILVETHVault.connect(client1).withdraw(ILVETHVault.balanceOf(client1.address))
        console.log(ethers.utils.formatEther(await ILVETHContract.balanceOf(client1.address))); // 1.000022577181585061

        await network.provider.send("evm_increaseTime", [365*86400/2+1])
        await ILVETHVault.unlock(1)
        await ILVETHVault.compound()
        await ILVETHVault.connect(client2).withdraw(ILVETHVault.balanceOf(client2.address))
        console.log(ethers.utils.formatEther(await ILVETHContract.balanceOf(client2.address))); // 0.999983640986847989
    })
})