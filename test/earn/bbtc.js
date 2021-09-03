const { expect } = require("chai")
const { ethers, deployments, network } = require('hardhat')
const { mainnet: addresses } = require('../../addresses')
const IERC20_ABI = require("../../abis/IERC20_ABI.json")

const USDTAddr = "0xdAC17F958D2ee523a2206206994597C13D831ec7"
const USDCAddr = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
const DAIAddr = "0x6B175474E89094C44Da98b954EedeAC495271d0F"
const aUSDTAddr = "0x3Ed3B47Dd13EC9a98b44e6204A523E766B225811"
const aUSDCAddr = "0xBcca60bB61934080951369a648Fb03DF4F96263C"
const aDAIAddr = "0x028171bCA77440897B824Ca71D1c56caC55b68A3"
const AXSAddr = "0xBB0E17EF65F82Ab018d8EDd776e8DD940327B28b"
const lpTokenAddr = "0x410e3E86ef427e30B9235497143881f717d93c2A" // *variable
const unlockedAddr = "0x28C6c06298d514Db089934071355E5743bf21d60"
const unlockedLpTokenAddr = "0x4Cf2c3ce9CA9A01e78B85FA12AC0352Be874AaCb" // *variable
const unlockedLpTokenAddr2 = "0xdFc7AdFa664b08767b735dE28f9E84cd30492aeE"
const unlockedCoinsAddr = "0x3DdfA8eC3052539b6C9549F12cEA2C295cfF5296"
const adminAddress = addresses.admin

const increaseTime = async (_seconds) => {
    let result = await network.provider.request({
        method: "evm_increaseTime",
        params: [_seconds]
    })
}

const mine = async () => {
    let result = await network.provider.request({
        method: "evm_mine",
        params: []
    })
}

describe("DAO Earn", () => {

    beforeEach(async () => {
        await deployments.fixture(["earn_mainnet_deploy_vault_bbtc"])
    })

    it("Should work", async () => {
        const [deployer, client, strategist, biconomy, treasury, community, topup] = await ethers.getSigners()
        const curveZap = await ethers.getContract("CurveMetaPoolBTCZap")
        // await network.provider.send("hardhat_setCode", [
        //     unlockedLpTokenAddr2,
        //     "0x",
        //   ]);
          
        // await topup.sendTransaction({to: unlockedLpTokenAddr2, value: ethers.utils.parseEther("5")})
        await network.provider.request({ method: "hardhat_impersonateAccount", params: [adminAddress], });

        const admin = await ethers.getSigner(adminAddress);

        let implArtifacts = await artifacts.readArtifact("EarnVault")

        let Factory = await ethers.getContract("EarnStrategyFactory")

        const earnVaultAddress = await Factory.getVault((await Factory.totalVaults()).toNumber() - 1)
        const earnVault = await ethers.getContractAt(implArtifacts.abi, earnVaultAddress, deployer)
        // Transfer LP token to client
        await network.provider.request({ method: "hardhat_impersonateAccount", params: [unlockedLpTokenAddr], });
        const unlockedLpTokenSigner = await ethers.getSigner(unlockedLpTokenAddr);

        // await network.provider.request({ method: "hardhat_impersonateAccount", params: [unlockedLpTokenAddr2], });
        // const unlockedLpTokenSigner2 = await ethers.getSigner(unlockedLpTokenAddr2);


        const lpTokenContract = new ethers.Contract(lpTokenAddr, IERC20_ABI, unlockedLpTokenSigner);
        await lpTokenContract.transfer(client.address, ethers.utils.parseUnits("2", 16))

        // await lpTokenContract.connect(unlockedLpTokenSigner2).transfer(client.address, ethers.utils.parseUnits("3", 18))

        await lpTokenContract.connect(client).approve(earnVault.address, ethers.constants.MaxUint256)

        // Transfer USDT/USDC/DAI coin to client
        await network.provider.request({method: "hardhat_impersonateAccount", params: [unlockedAddr],});
        const unlockedSigner = await ethers.getSigner(unlockedAddr);
        const USDTContract = new ethers.Contract(USDTAddr, IERC20_ABI, unlockedSigner)
        const USDCContract = new ethers.Contract(USDCAddr, IERC20_ABI, unlockedSigner)
        const DAIContract = new ethers.Contract(DAIAddr, IERC20_ABI, unlockedSigner)

        // Transfer aUSDT/aUSDC/aDAI coin to client
        await network.provider.request({method: "hardhat_impersonateAccount", params: [unlockedCoinsAddr],});
        const unlockedCoinsSigner = await ethers.getSigner(unlockedCoinsAddr);

        // Deposit
        console.log('lp token deposited', ethers.utils.formatEther(await lpTokenContract.balanceOf(client.address)))
        await earnVault.connect(client).deposit(ethers.utils.parseUnits("2", 16), false)

        // receipt = await tx.wait()
        // console.log(receipt.gasUsed.toString())

        // Invest
        tx = await earnVault.connect(admin).invest()

        // await earnVault.connect(admin).invest()

        // Change Curve Zap contract - CHECK
        // const curveZap2 = await CurveZap.deploy()
        // await curveZap2.addPool(earnVault.address, curvePoolAddr)
        // await earnVault.setCurveZap(curveZap2.address)

        // Yield
        await increaseTime(604800)
        await mine()
        tx = await earnVault.connect(admin).yield()
        // receipt = await tx.wait()
        // console.log(receipt.gasUsed.toString())
        // console.log(ethers.utils.formatEther(await earnVault.getPricePerFullShare(false)))
        // console.log(ethers.utils.formatEther(await community.getBalance()))
        // console.log(ethers.utils.formatEther(await strategist.getBalance()))

        // Emergency withdraw
        // const cvStake = new ethers.Contract("0x02E2151D4F351881017ABdF2DD2b51150841d5B3", ["function balanceOf(address) external view returns (uint)"], deployer)
        // console.log(ethers.utils.formatEther(await cvStake.balanceOf(earnStrategy.address)))
        // console.log(ethers.utils.formatEther(await lpTokenContract.balanceOf(earnVault.address)))
        await increaseTime(604800)
        await mine()
        await earnVault.connect(admin).emergencyWithdraw()
        await expect(earnVault.connect(client).deposit(ethers.utils.parseEther("10000"), false)).to.be.revertedWith("Pausable: paused")
        
        // console.log(ethers.utils.formatEther(await cvStake.balanceOf(earnStrategy.address)))
        // console.log(ethers.utils.formatEther(await lpTokenContract.balanceOf(earnVault.address)))
        await earnVault.connect(admin).reinvest()
        // console.log(ethers.utils.formatEther(await cvStake.balanceOf(earnStrategy.address)))
        // console.log(ethers.utils.formatEther(await lpTokenContract.balanceOf(earnVault.address)))

        // Withdraw
        const withdrawAmt = (await earnVault.balanceOf(client.address))
        await earnVault.connect(client).withdraw(withdrawAmt)
        console.log("LP token withdraw:", ethers.utils.formatEther(await lpTokenContract.balanceOf(client.address)))

        // Test deposit & withdraw with other contract
        const Sample = await ethers.getContractFactory("Sample", deployer)
        const sample = await Sample.deploy(lpTokenAddr, earnVault.address, curveZap.address)
        await lpTokenContract.transfer(sample.address, ethers.utils.parseUnits("2", 16))
        tx = await sample.deposit()
        // receipt = await tx.wait()
        // console.log(receipt.gasUsed.toString())
        await expect(sample.withdraw()).to.be.revertedWith("Withdraw within locked period")
        network.provider.send("evm_increaseTime", [300])
        await sample.withdraw()

    })
})