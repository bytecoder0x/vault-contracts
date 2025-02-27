import { Staking, MockERC20, Treasury, VaultFactory, MockQuadata, License, Scoring } from "../../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { deployAllContracts, createAndRepayVault } from "../utils.test";
import { loadFixture, mineUpTo, mine } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";

describe("GoilStaking", function () {
	let staking: Staking;
	let vaultFactory: VaultFactory;
	let license: License;
	let scoring: Scoring;
	let treasury: Treasury;
	let goilToken: MockERC20;
	let stableToken: MockERC20;
	let qadrataReader: MockQuadata;
	let admin: HardhatEthersSigner;
	let entity: HardhatEthersSigner;
	let user1: HardhatEthersSigner;
	let user2: HardhatEthersSigner;

	beforeEach(async () => {
		const fixture = await loadFixture(deployAllContracts);
		staking = fixture.staking;

		vaultFactory = fixture.vaultFactory;
		license = fixture.license;
		scoring = fixture.scoring;
		treasury = fixture.treasury;
		qadrataReader = fixture.quadata;
		goilToken = fixture.goilToken;
		stableToken = fixture.stableToken;
		admin = fixture.admin;
		entity = fixture.entity;
		user1 = fixture.user1;
		user2 = fixture.user2;

        const totalAmount = ethers.parseEther("1000000");
        await goilToken.connect(user1).mint(user1.address, totalAmount);
        await goilToken.connect(user2).mint(user2.address, totalAmount);
        await goilToken.connect(user1).approve(staking.target, totalAmount);
        await goilToken.connect(user2).approve(staking.target, totalAmount);
        await goilToken.connect(admin).approve(staking.target, totalAmount);
	});

	describe("Deployment Functionality", function () {
		it("Should set correct staking token", async function () {
			expect(await staking.STAKING_TOKEN()).to.equal(goilToken.target);
		});

		it("Should set correct reward token", async function () {
			expect(await staking.REWARD_TOKEN()).to.equal(goilToken.target);
		});

		it("Should set correct treasury", async function () {
			expect(await staking.TREASURY()).to.equal(treasury.target);
		});
	});

	describe("Staking Functionality", function () {
		it.skip("test for me", async function () {
			const stakeAmount = ethers.parseEther("100");
			const rewardAmount = ethers.parseEther("110");

			await goilToken.connect(user1).mint(user1.address, stakeAmount);
			await goilToken.connect(user1).approve(staking.target, stakeAmount);
			await staking.connect(user1).stakeTokens(stakeAmount);

			console.log(Number(await staking.getPendingRewardByUser(user1.address)) / 1e18);

			await goilToken.approve(staking.target, rewardAmount);
			await staking.depositReward(rewardAmount);

			const totalReward = await staking.totalReward();
			await mineUpTo((await staking.endStakingBlock()) / 2n);
			console.log(Number(await staking.getPendingRewardByUser(user1.address)) / 1e18);

			await goilToken.approve(staking.target, rewardAmount);
			await staking.depositReward(rewardAmount);

			await mineUpTo(await staking.endStakingBlock());
			console.log(Number(await staking.getPendingRewardByUser(user1.address)) / 1e18);

			await staking.connect(user1)["claimReward()"]();
		});

		it("Should allow users to stake tokens", async function () {
			const stakeAmount = ethers.parseEther("100");

			await expect(staking.connect(user1).stakeTokens(stakeAmount)).to.emit(staking, "Staked").withArgs(user1.address, stakeAmount);

			const userStake = await staking.userStakes(user1.address);
			expect(userStake.stakedAmount).to.equal(stakeAmount);
		});

		it("Should allow depositing rewards", async function () {
			const rewardAmount = ethers.parseEther("100");

			await expect(staking.connect(admin).depositReward(rewardAmount))
				.to.emit(staking, "RewardDeposited")
				.withArgs(admin.address, rewardAmount);

			const totalReward = await staking.totalReward();
			expect(totalReward).to.equal(rewardAmount);
		});

		it("Should calculate correct APY", async function () {
			const stakeAmount = ethers.parseEther("100");
			const rewardAmount = ethers.parseEther("10");

			const apyBeforeReward = await staking.getCurrentAPY();
			expect(apyBeforeReward).to.be.equal(0);

			await staking.connect(user1).stakeTokens(stakeAmount);
			await staking.connect(admin).depositReward(rewardAmount);

			const rewardPerBlock = await staking.rewardPerBlock();
			const blockAmountInOneYear = (await staking.ONE_MONTH_IN_BLOCKS()) * 12n;
			const rewardPerYear = rewardPerBlock * blockAmountInOneYear;

			const apyAfterReward = await staking.getCurrentAPY();
			const expectedApy = (rewardPerYear * 10000n / stakeAmount) // 10000 = 100%

			expect(apyAfterReward).to.be.equal(expectedApy);
		});

		it("Should allow users to unstake tokens", async function () {
			const stakeAmount = ethers.parseEther("100");

			await staking.connect(user1).stakeTokens(stakeAmount);
			await expect(staking.connect(user1)["unstakeTokens()"]()).to.emit(staking, "Unstaked").withArgs(user1.address, stakeAmount);

			const userStake = await staking.userStakes(user1.address);
			expect(userStake.stakedAmount).to.equal(0);
		});

		it("Should correctly distribute rewards to stakers", async function () {
			const stakeAmount = ethers.parseEther("100");
			const rewardAmount = ethers.parseEther("10");
            const delta = ethers.parseEther("0.0001");

			await staking.connect(user1).stakeTokens(stakeAmount);
			await staking.connect(admin).depositReward(rewardAmount);

			await mine((await staking.ONE_MONTH_IN_BLOCKS()) / 2n);

			const pendingReward = await staking.getPendingRewardByUser(user1.address);
			expect(pendingReward).to.be.closeTo(rewardAmount / 2n, delta);
		});

        it("Should allow users to claim rewards", async function () {
            const stakeAmount = ethers.parseEther("100");
            const rewardAmount = ethers.parseEther("10");
            const delta = ethers.parseEther("0.0001");

            await staking.connect(user1).stakeTokens(stakeAmount);
            await staking.connect(admin).depositReward(rewardAmount);

			await mine((await staking.ONE_MONTH_IN_BLOCKS()) / 2n);

            const balanceBefore = await goilToken.balanceOf(user1.address);
			await staking.connect(user1)["claimReward()"]();
            const balanceAfter = await goilToken.balanceOf(user1.address);

            expect(balanceAfter).to.be.closeTo(balanceBefore + rewardAmount / 2n, delta);
        });
	});
});
