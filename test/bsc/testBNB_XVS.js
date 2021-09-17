const { expect } = require("chai")
const { ethers, deployments, network } = require('hardhat')
const { mainnet: addresses } = require('../../addresses/bsc')
const IERC20_ABI = require("../../abis/IERC20_ABI.json")

const unlockedAddress = "0xb1b9b4bbe8a92d535f5df2368e7fd2ecfb3a1950"
const unlockedAddress2 = "0x7450da0e7f9f1dfe8060160e612dfc833a725b48"


describe("BSC - BNB-XVS", () => {
    const setup = async () => {
        const [deployer, user1, user2, topup] = await ethers.getSigners()

        const lpToken = new ethers.Contract(addresses.LPTOKENS.BNB_XVS, IERC20_ABI, deployer)

        await topup.sendTransaction({ to: addresses.ADDRESSES.adminAddress, value: ethers.utils.parseEther("2") })
        await topup.sendTransaction({ to: unlockedAddress, value: ethers.utils.parseEther("2") })
        await topup.sendTransaction({ to: unlockedAddress2, value: ethers.utils.parseEther("2") })

        await network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [unlockedAddress]
        })


        await network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [unlockedAddress2]
        })

        await network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [addresses.ADDRESSES.adminAddress]
        })

        const impl = await ethers.getContract("BscVault", deployer)
        let implArtifacts = await artifacts.readArtifact("BscVault")
        const Factory = await ethers.getContract("BscVaultFactory", deployer)
        const vaultProxyAddress = await Factory.getVault((await Factory.totalVaults()).toNumber() - 1)

        const vault = await ethers.getContractAt(implArtifacts.abi, vaultProxyAddress, deployer)

        const unlockedUser = await ethers.getSigner(unlockedAddress)
        const unlockedUser2 = await ethers.getSigner(unlockedAddress2)
        const adminSigner = await ethers.getSigner(addresses.ADDRESSES.adminAddress)

        await lpToken.connect(unlockedUser).transfer(user1.address, ethers.utils.parseUnits("3", "18"))
        await lpToken.connect(unlockedUser2).transfer(user2.address, ethers.utils.parseUnits("2", "18"))

        await lpToken.connect(user1).approve(vault.address, ethers.utils.parseUnits("1000000000", 18))

        await lpToken.connect(user2).approve(vault.address, ethers.utils.parseUnits("1000000000", 18))

        return { vault, lpToken, user1, user2, adminSigner, deployer, Factory }
    }

    beforeEach(async () => {
        await deployments.fixture(["bsc_mainnet_deploy_pool_bnb_xvs"])
    })


    it("Should deploy correctly", async () => {
        const { vault, ALCX, USDT, DAI, adminSigner, deployer } = await setup()
        expect(await vault.communityWallet()).to.be.equal(addresses.ADDRESSES.communityWallet)
        expect(await vault.treasuryWallet()).to.be.equal(addresses.ADDRESSES.treasuryWallet)
        expect(await vault.strategist()).to.be.equal(addresses.ADDRESSES.strategist)
        expect(await vault.admin()).to.be.equal(addresses.ADDRESSES.adminAddress)

    })

    it("Should work correctly - normal flow", async () => {
        const { vault, lpToken, user1, user2, adminSigner, deployer } = await setup()

        let user1Balance = await lpToken.balanceOf(user1.address)
        let user2Balance = await lpToken.balanceOf(user2.address)
        console.log("User1 Deposited: ", ethers.utils.formatEther(user1Balance))
        console.log("User2 Deposited: ", ethers.utils.formatEther(user2Balance))

        await vault.connect(user1).deposit(user1Balance)
        await vault.connect(adminSigner).invest()
        await vault.connect(user2).deposit(user2Balance)

        await vault.connect(adminSigner).invest()
        await vault.connect(adminSigner).yield()

        await vault.connect(user1).withdraw(await vault.balanceOf(user1.address))
        await vault.connect(user2).withdraw(await vault.balanceOf(user2.address))

        console.log("User1 Withdrawn: ", ethers.utils.formatEther(await lpToken.balanceOf(user1.address)))
        console.log("User2 Withdrawn: ", ethers.utils.formatEther(await lpToken.balanceOf(user2.address)))
    })

    it("should emergencyWithdraw correctly", async () => {
        const { vault, lpToken, user1, user2, adminSigner, deployer } = await setup()

        let user1Balance = await lpToken.balanceOf(user1.address)
        let user2Balance = await lpToken.balanceOf(user2.address)
        console.log("User1 Deposited: ", ethers.utils.formatEther(user1Balance))
        console.log("User2 Deposited: ", ethers.utils.formatEther(user2Balance))

        await vault.connect(user1).deposit(user1Balance)
        await vault.connect(adminSigner).invest()
        await vault.connect(user2).deposit(user2Balance)

        await vault.connect(adminSigner).invest()
        await vault.connect(adminSigner).yield()

        await vault.connect(adminSigner).emergencyWithdraw()

        await vault.connect(user1).withdraw(await vault.balanceOf(user1.address))
        await vault.connect(user2).withdraw(await vault.balanceOf(user2.address))

        console.log("User1 Withdrawn: ", ethers.utils.formatEther(await lpToken.balanceOf(user1.address)))
        console.log("User2 Withdrawn: ", ethers.utils.formatEther(await lpToken.balanceOf(user2.address)))
    })

    it("Should revert other functions on emergency", async () => {
        const { vault, lpToken, user1, user2, adminSigner, deployer } = await setup()

        let user1Balance = await lpToken.balanceOf(user1.address)
        let user2Balance = await lpToken.balanceOf(user2.address)
        console.log("User1 Deposited: ", ethers.utils.formatEther(user1Balance))

        await vault.connect(user1).deposit(user1Balance)

        await vault.connect(adminSigner).emergencyWithdraw()

        expect(vault.connect(user2).deposit(user2Balance)).to.be.revertedWith("Pausable: paused")
        expect(vault.connect(adminSigner).invest()).to.be.revertedWith("Pausable: paused")
        expect(vault.connect(adminSigner).yield()).to.be.revertedWith("Pausable: paused")

        await vault.connect(user1).withdraw(await vault.balanceOf(user1.address))

        console.log("User1 Withdrawn: ", ethers.utils.formatEther(await lpToken.balanceOf(user1.address)))
    })

    it("should Reinvest correctly", async () => {
        const { vault, lpToken, user1, user2, adminSigner, deployer } = await setup()

        let user1Balance = await lpToken.balanceOf(user1.address)
        let user2Balance = await lpToken.balanceOf(user2.address)
        console.log("User1 Deposited: ", ethers.utils.formatEther(user1Balance))
        console.log("User2 Deposited: ", ethers.utils.formatEther(user2Balance))

        await vault.connect(user1).deposit(user1Balance)
        await vault.connect(adminSigner).invest()
        await vault.connect(user2).deposit(user2Balance)

        await vault.connect(adminSigner).invest()
        await vault.connect(adminSigner).yield()

        await vault.connect(adminSigner).emergencyWithdraw()

        await vault.connect(adminSigner).reInvest()

        await vault.connect(user1).withdraw(await vault.balanceOf(user1.address))
        await vault.connect(user2).withdraw(await vault.balanceOf(user2.address))

        console.log("User1 Withdrawn: ", ethers.utils.formatEther(await lpToken.balanceOf(user1.address)))
        console.log("User2 Withdrawn: ", ethers.utils.formatEther(await lpToken.balanceOf(user2.address)))
    })

    it("Should unPause functions on reInvest", async () => {
        const { vault, lpToken, user1, user2, adminSigner, deployer } = await setup()

        let user1Balance = await lpToken.balanceOf(user1.address)
        let user2Balance = await lpToken.balanceOf(user2.address)
        console.log("User1 Deposited: ", ethers.utils.formatEther(user1Balance))
        console.log("User2 Deposited: ", ethers.utils.formatEther(user2Balance))

        await vault.connect(user1).deposit(user1Balance)
        await vault.connect(adminSigner).invest()
        await vault.connect(user2).deposit(user2Balance)

        await vault.connect(adminSigner).emergencyWithdraw()

        await vault.connect(adminSigner).reInvest()

        await vault.connect(adminSigner).invest()
        await vault.connect(adminSigner).yield()

        await vault.connect(user1).withdraw(await vault.balanceOf(user1.address))
        await vault.connect(user2).withdraw(await vault.balanceOf(user2.address))

        console.log("User1 Withdrawn: ", ethers.utils.formatEther(await lpToken.balanceOf(user1.address)))
        console.log("User2 Withdrawn: ", ethers.utils.formatEther(await lpToken.balanceOf(user2.address)))
    })

    it("Should transfer Fee correctly", async () => {
        const { vault, lpToken, user1, user2, adminSigner, deployer } = await setup()

        let user1Balance = await lpToken.balanceOf(user1.address)

        await vault.connect(user1).deposit(user1Balance)

        await vault.connect(adminSigner).invest()

        let depositFeePerc = await vault.depositFee()
        let totalFee = user1Balance.mul(depositFeePerc).div(10000)

        let fourtyPerc = totalFee.mul(40).div(100)
        let twentyPerc = totalFee.mul(20).div(100)

        expect(
            await lpToken.balanceOf(addresses.ADDRESSES.treasuryWallet)
        ).to.eq(fourtyPerc)

        expect(
            await lpToken.balanceOf(addresses.ADDRESSES.communityWallet)
        ).to.eq(fourtyPerc)

        expect(
            await lpToken.balanceOf(addresses.ADDRESSES.strategist)
        ).to.eq(twentyPerc)

    })

    it("Should upgrade correctly", async () => {
        const { vault, lpToken, user1, user2, adminSigner, deployer, Factory } = await setup()

        let user1Balance = await lpToken.balanceOf(user1.address)
        let user2Balance = await lpToken.balanceOf(user2.address)

        await vault.connect(user1).deposit(user1Balance)
        await vault.connect(adminSigner).invest()
        await vault.connect(user2).deposit(user2Balance)

        await vault.connect(adminSigner).invest()

        let valueInPool = await vault.getAllPool()

        let newImpl = await ethers.getContractFactory("BscVault", deployer)
        let impl = await newImpl.deploy()

        await impl.deployTransaction.wait()

        await Factory.connect(deployer).updateLogic(impl.address)

        expect(valueInPool).to.eq(await vault.getAllPool())

    })
})