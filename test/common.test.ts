import { ethers } from "hardhat";
import { expect } from "chai";
import {
	MockERC20,
	Staking,
	Scoring,
	License,
	Treasury,
	VaultFactory,
	Oracle,
	MockQuadata,
	MockPool,
	MockFactory,
	MockQuoterV2,
	MockRouterV3,
	MockRouterV2,
} from "../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { loadFixture, mineUpTo } from "@nomicfoundation/hardhat-network-helpers";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { deployAllContracts } from "./utils.test";

describe.only("Main Flow", function () {
	let admin: HardhatEthersSigner;
	let entity: HardhatEthersSigner;
	let user1: HardhatEthersSigner;
	let user2: HardhatEthersSigner;
	let user3: HardhatEthersSigner;
	let user4: HardhatEthersSigner;

	let goilToken: MockERC20;
	let stableToken: MockERC20;
	let mockFactory: MockFactory;
	let mockPool: MockPool;
	let mockRouterV2: MockRouterV2;
	let mockRouterV3: MockRouterV3;
	let mockQuoter: MockQuoterV2;
	let quadata: MockQuadata;
	let oracle: Oracle;
	let vaultFactory: VaultFactory;
	let treasury: Treasury;
	let license: License;
	let scoring: Scoring;
	let staking: Staking;
    let initialSupply: bigint;
    let applicationFee: bigint;
    let licenseMonthlyFee: bigint;
    let thresholdCollateral: bigint;
    let thresholdCapital: bigint;

	beforeEach(async () => {
		const fixture = await loadFixture(deployAllContracts);
		admin = fixture.admin;
		entity = fixture.entity;
		user1 = fixture.user1;
		user2 = fixture.user2;
		user3 = fixture.user3;
		user4 = fixture.user4;
		goilToken = fixture.goilToken;
		stableToken = fixture.stableToken;
		mockFactory = fixture.mockFactory;
		mockPool = fixture.mockPool;
		mockRouterV2 = fixture.mockRouterV2;
		mockRouterV3 = fixture.mockRouterV3;
		mockQuoter = fixture.mockQuoter;
		quadata = fixture.quadata;
		oracle = fixture.oracle;
		vaultFactory = fixture.vaultFactory;
		treasury = fixture.treasury;
		license = fixture.license;
		scoring = fixture.scoring;
		staking = fixture.staking;
        initialSupply = fixture.INITIAL_SUPPLY;
        applicationFee = fixture.APPLICATION_FEE;
        licenseMonthlyFee = fixture.LICENSE_MONTHLY_FEE;
        thresholdCollateral = fixture.THRESHOLD_COLLATERAL;
        thresholdCapital = fixture.THRESHOLD_CAPITAL;
	});

	it("Checks all functionality from getting license to successful vault repayment", async function () {
		const collateralAmount = ethers.parseEther("100000"); // this amount will be used for calculating initial score
		const totalFeeWithCollateral = collateralAmount + licenseMonthlyFee * 12n + applicationFee;
		const licenseEndTime = 12; // 12 months

		const tokensForTreasury = ethers.parseEther("10000000");

		await goilToken.mint(entity.address, totalFeeWithCollateral);
		await goilToken.mint(treasury.target, tokensForTreasury); // 10mln
		await goilToken.connect(entity).approve(license.target, totalFeeWithCollateral);
		await quadata.mint(entity.address, 1);

		// it means that the entity has not submitted a license yet
		expect(await license.getLicenseStatus(entity.address)).to.equal(0);

		// entity submits a license
		await license.connect(entity).submitLicense(licenseEndTime, collateralAmount);
		// application fee is transferred to treasury
		expect(await goilToken.balanceOf(treasury.target)).to.equal(applicationFee + tokensForTreasury);
		// total fee with collateral is transferred to !license during voting
		expect(await goilToken.balanceOf(license.target)).to.equal(totalFeeWithCollateral - applicationFee);

		// it means that the entity has submitted a license and it is pending - user can vote for it
		expect(await license.getLicenseStatus(entity.address)).to.equal(1);

		// admin sets initial performance data for the entity (it will be used for calculating initial score)
		await scoring.connect(admin).setPerformanceData(entity.address, 50_000, 60_000); // 50% reputation, 60% financial health

		// license manager approves the license if entity has enough votes from goverment voting
		await license.connect(admin).approveLicense(entity.address, true);

		// it means that the license is approved (3)
		expect(await license.getLicenseStatus(entity.address)).to.equal(3);

		// license monthly fee and collateral is transferred to treasury if the license is approved
		expect(await goilToken.balanceOf(treasury.target)).to.equal(totalFeeWithCollateral + tokensForTreasury);
		expect(await goilToken.balanceOf(license.target)).to.equal(0);

		// formula for calculating initial score:
		// w1 * collateralRatio + w2 * reputationRatio + w3 * financialHealthRatio + w4 * marketConditionRatio
		// collateralRatio = collateralAmount / thresholdCollateral (10000 / 10000 = 1)

		// for our case: 0.4 * 1 + 0.2 * 0.5 + 0.25 * 0.6 + 0.15 * 1 = 0.4 + 0.1 + 0.15 + 0.15 = 0.8
		const scores = await scoring.getScores(entity.address);

		// only initial score is set
		expect(scores.length).to.equal(1);

		// initial score is 0.8 * 100_000 (with precision)
		expect(scores[0]).to.equal(0.8 * 100_000);

		// since initial score is 0.8 * 1_000_000 (threshold capital = 1mln) = 800_000k
		expect((await scoring.getMaxPoolSize(entity.address)) / 10n ** 18n).to.equal(800_000n);

		const poolSize = ethers.parseEther("100000"); // 100k
		//! 1 goil = 1$
		const requiredCollateral = await treasury.getRequiredCollateral(poolSize);
		// required collateral is 10% of pool size = 100k * 10 / 100 = 10k$ = 10k goil
		expect(requiredCollateral / 10n ** 18n).to.equal(10_000n); // 10k goil

		await goilToken.mint(entity.address, requiredCollateral);
		await goilToken.connect(entity).approve(treasury.target, requiredCollateral);

		// entity creates a vault
		const depositToken = stableToken.target;
		const rate = 11_00; // 11%
		const startTime = (await time.latest()) + 24 * 60 * 60; // in 1 day
		const fundingPeriod = 14 * 24 * 60 * 60; // 14 days
		const unlockPeriod = 3 * 31 * 24 * 60 * 60; // 3 months
		const desiredCap = poolSize;

		await vaultFactory.connect(entity).createVault(depositToken, rate, desiredCap, startTime, fundingPeriod, unlockPeriod);

		const vaults = await vaultFactory.getAllVaults();
		const vault = await ethers.getContractAt("Vault", vaults[0].vault);

		// only one vault is created by the entity
		expect(vaults.length).to.equal(1);
		expect(await vault.ENTITY()).to.equal(entity.address);

		const amountToDeposit = ethers.parseEther("25000"); // 25k$
		await stableToken.connect(user1).mint(user1.address, amountToDeposit);
		await stableToken.connect(user2).mint(user2.address, amountToDeposit);
		await stableToken.connect(user3).mint(user3.address, amountToDeposit);
		await stableToken.connect(user4).mint(user4.address, amountToDeposit);
		await stableToken.connect(user1).approve(vault.target, amountToDeposit);
		await stableToken.connect(user2).approve(vault.target, amountToDeposit);
		await stableToken.connect(user3).approve(vault.target, amountToDeposit);
		await stableToken.connect(user4).approve(vault.target, amountToDeposit);

		// wait for the vault to start
		await time.increaseTo(startTime);

		// vault ready to be funded
		await vault.connect(user1)["deposit(uint256)"](amountToDeposit);
		await vault.connect(user2)["deposit(uint256)"](amountToDeposit);
		await vault.connect(user3)["deposit(uint256)"](amountToDeposit);
		await vault.connect(user4)["deposit(uint256)"](amountToDeposit);

		// buyers got shares (1:1 ratio -> 1 share = 1$)
		expect(await vault.balanceOf(user1.address)).to.equal(amountToDeposit);
		expect(await vault.balanceOf(user2.address)).to.equal(amountToDeposit);
		expect(await vault.balanceOf(user3.address)).to.equal(amountToDeposit);
		expect(await vault.balanceOf(user4.address)).to.equal(amountToDeposit);

		// wait for the funding period to end
		await time.increaseTo(startTime + fundingPeriod + 1);

		// entity can withdraw all the funds
		await vault.connect(entity).withdrawToEntity();
		expect(await stableToken.balanceOf(entity.address)).to.equal(amountToDeposit * 4n);

		const promisedProfit = (amountToDeposit * 4n * 11n) / 100n;
        const promisedCapital = (amountToDeposit * 4n) + promisedProfit;
		await stableToken.connect(entity).mint(entity.address, promisedProfit);

        // since 1$ = 1 goil i can get 1% of profit in stable token //! staking amount in goil
        const stakingAmount = (promisedProfit * 1n) / 100n; // 1% of profit successful vault transfer to staking

		// entity can deposit all the funds
		await stableToken.connect(entity).approve(vault.target, promisedCapital);
        // it needs for swap 1% of profit in stable -> goil and transfer to staking
		await goilToken.mint(mockRouterV3.target, stakingAmount);

		await vault.connect(entity).depositFromEntity();

        // vault is successfully repaid and users can withdraw their shares
        expect(await stableToken.balanceOf(vault.target)).to.equal(promisedCapital - stakingAmount); // 10% profit
		expect(await goilToken.balanceOf(staking.target)).to.equal(stakingAmount);

        // entity score is updated

        // formula for calculating new score:

        // lastScore = 0.8

        // newScore = (lastScore + (poolSizeRatio * historicalPerformance)) * penalties
        // ! score cannot be greater than 1

        // poolSizeRatio = poolSizeWeight * poolSize / maxPoolSize (0.1 * 100k / 800k = 0.0125)

        // historyScoreWeights = [0.1, 0.1, 0.1, 0.2, 0.5]  // we can get only last five scores
        // we can get only one score from history, then we use weights 0.5 for last score
        // accumulatedHistoricalScore / maxScoreByEntity (0.5 * 0.8 / 0.8 = 0.5)

        // example if we have 2 scores in history: [0.8, 0.7]
        // then accumulatedHistoricalScore = 0.7 * 0.5 + 0.8 * 0.2 = 0.35 + 0.16 = 0.51
        // maxScoreByEntity = 0.8 -> 0.51 / 0.8 = 0.6375
        
        // penalties = exp^(-totalFailedVaults) (exp^(-0) = 1)

        // newScore = (0.8 + (0.0125 * 0.5)) * 1 = 0.80625

        const updatedScores = await scoring.getScores(entity.address);
        expect(updatedScores.length).to.equal(2);
        expect(updatedScores[1]).to.equal(0.80625 * 100_000); // with precision

        // entity scores is growing, it means that entity can create pool with higher size
        const previousMaxPoolSize = ethers.parseEther("800000"); // 800k
        expect(await scoring.getMaxPoolSize(entity.address)).to.be.greaterThan(previousMaxPoolSize);

        // users can withdraw their shares
        // rate is 11% and 1% of profit transfer to staking -> 11% * 0.99 = 10.89% profit
        // users expect to get 10.89% profit of their deposit, it 2.5k$ from 25k$
        const expectedProfit = amountToDeposit * 1089n / 10000n;
        const totalStableAmountWithProfit = amountToDeposit + expectedProfit;
        
        const maxPossibleWithdrawForUser1 = await vault.maxWithdraw(user1.address);
        const maxPossibleWithdrawForUser2 = await vault.maxWithdraw(user2.address);
        const maxPossibleWithdrawForUser3 = await vault.maxWithdraw(user3.address);
        const maxPossibleWithdrawForUser4 = await vault.maxWithdraw(user4.address);

        await vault.connect(user1)["withdraw(uint256)"](maxPossibleWithdrawForUser1);
        await vault.connect(user2)["withdraw(uint256)"](maxPossibleWithdrawForUser2);
        await vault.connect(user3)["withdraw(uint256)"](maxPossibleWithdrawForUser3);
        await vault.connect(user4)["withdraw(uint256)"](maxPossibleWithdrawForUser4);

        // we have delta of "1" because of rounding in _convertToAssets (ERC4626)
        expect(await stableToken.balanceOf(user1.address)).closeTo(totalStableAmountWithProfit, 1);
        expect(await stableToken.balanceOf(user2.address)).closeTo(totalStableAmountWithProfit, 1);
        expect(await stableToken.balanceOf(user3.address)).closeTo(totalStableAmountWithProfit, 1);
        expect(await stableToken.balanceOf(user4.address)).closeTo(totalStableAmountWithProfit, 1);

        // Successfully vault is repaid and users got their profit ^:)

		const amountToStake = ethers.parseEther("1000");
		await goilToken.mint(user1.address, amountToStake);
		await goilToken.connect(user1).approve(staking.target, amountToStake);
		await staking.connect(user1).stakeTokens(amountToStake);

		await mineUpTo(await staking.endStakingBlock());
		
		const user1Reward = await staking.getPendingRewardByUser(user1.address);
		expect(user1Reward).to.be.closeTo(stakingAmount, ethers.parseEther("1"));
	});

    it("Checks all functionality from getting license to vault liquidation", async function () {
        const collateralAmount = ethers.parseEther("100000")
		const totalFeeWithCollateral = collateralAmount + licenseMonthlyFee * 12n + applicationFee;

		const licenseEndTime = 12; // 12 months
		const tokensForTreasury = ethers.parseEther("10000000");

		await goilToken.mint(entity.address, totalFeeWithCollateral);
		await goilToken.mint(treasury.target, tokensForTreasury); // 10mln
		await goilToken.connect(entity).approve(license.target, totalFeeWithCollateral);
		await quadata.mint(entity.address, 1);

        // all things the same as in successful vault repayment (license, initial score, create vault, etc.)
		await license.connect(entity).submitLicense(licenseEndTime, collateralAmount);
		await scoring.connect(admin).setPerformanceData(entity.address, 50_000, 60_000);
		await license.connect(admin).approveLicense(entity.address, true);

		const poolSize = ethers.parseEther("100000"); // 100k
		const requiredCollateral = await treasury.getRequiredCollateral(poolSize);
		await goilToken.mint(entity.address, requiredCollateral);
		await goilToken.connect(entity).approve(treasury.target, requiredCollateral);

		const depositToken = stableToken.target;
		const rate = 11_00; // 11%
		const startTime = (await time.latest()) + 24 * 60 * 60; // in 1 day
		const fundingPeriod = 14 * 24 * 60 * 60; // 14 days
		const unlockPeriod = 3 * 31 * 24 * 60 * 60; // 3 months
		const desiredCap = poolSize;
		await vaultFactory.connect(entity).createVault(depositToken, rate, desiredCap, startTime, fundingPeriod, unlockPeriod);
		const vaults = await vaultFactory.getAllVaults();
		const vault = await ethers.getContractAt("Vault", vaults[0].vault);

		const amountToDeposit = ethers.parseEther("25000"); // 25k$
		await stableToken.connect(user1).mint(user1.address, amountToDeposit);
		await stableToken.connect(user2).mint(user2.address, amountToDeposit);
		await stableToken.connect(user3).mint(user3.address, amountToDeposit);
		await stableToken.connect(user4).mint(user4.address, amountToDeposit);
		await stableToken.connect(user1).approve(vault.target, amountToDeposit);
		await stableToken.connect(user2).approve(vault.target, amountToDeposit);
		await stableToken.connect(user3).approve(vault.target, amountToDeposit);
		await stableToken.connect(user4).approve(vault.target, amountToDeposit);

		await time.increaseTo(startTime);
		await vault.connect(user1)["deposit(uint256)"](amountToDeposit);
		await vault.connect(user2)["deposit(uint256)"](amountToDeposit);
		await vault.connect(user3)["deposit(uint256)"](amountToDeposit);
		await vault.connect(user4)["deposit(uint256)"](amountToDeposit);

		// users got shares (1:1 ratio -> 1 share = 1$)
		expect(await vault.balanceOf(user1.address)).to.equal(amountToDeposit);
		expect(await vault.balanceOf(user2.address)).to.equal(amountToDeposit);
		expect(await vault.balanceOf(user3.address)).to.equal(amountToDeposit);
		expect(await vault.balanceOf(user4.address)).to.equal(amountToDeposit);

		// wait for the funding period to end
		await time.increaseTo(startTime + fundingPeriod + 1);

		// entity can withdraw all the funds
		await vault.connect(entity).withdrawToEntity();
		expect(await stableToken.balanceOf(entity.address)).to.equal(amountToDeposit * 4n);

        // wait for the unlock period to end and vault is not funded
		await time.increaseTo(startTime + fundingPeriod + unlockPeriod + 1);

        //! 1$GOIL = 1$ since we have 1:1 ratio of stable token and goil token
        await vault.connect(user1)["withdraw(uint256)"](amountToDeposit);
        await vault.connect(user2)["withdraw(uint256)"](amountToDeposit);
        await vault.connect(user3)["withdraw(uint256)"](amountToDeposit);
        await vault.connect(user4)["withdraw(uint256)"](amountToDeposit);

        expect(await stableToken.balanceOf(user1.address)).to.equal(0);
        expect(await stableToken.balanceOf(user2.address)).to.equal(0);
        expect(await stableToken.balanceOf(user3.address)).to.equal(0);
        expect(await stableToken.balanceOf(user4.address)).to.equal(0);

        // we have delta of "1" because of rounding in _convertToAssets (ERC4626)
        // it means for our case users can get 24.999k...$GOIL instead of 25k $GOIL
        //! 1$GOIL = 1$ since we have 1:1 ratio
        expect(await goilToken.balanceOf(user1.address)).closeTo(amountToDeposit, 1);
        expect(await goilToken.balanceOf(user2.address)).closeTo(amountToDeposit, 1);
        expect(await goilToken.balanceOf(user3.address)).closeTo(amountToDeposit, 1);
        expect(await goilToken.balanceOf(user4.address)).closeTo(amountToDeposit, 1);

        // entity score is updated

        // formula for calculating new score:

        // lastScore = 0.8

        // newScore = (lastScore + (poolSizeRatio * historicalPerformance)) * penalties
        // ! score cannot be greater than 1

        // poolSizeRatio = poolSizeWeight * poolSize / maxPoolSize (0.1 * 100k / 800k = 0.0125)

        // historyScoreWeights = [0.1, 0.1, 0.1, 0.2, 0.5]  // we can get only last five scores
        // we can get only one score from history, then we use weights 0.5 for last score
        // accumulatedHistoricalScore / maxScoreByEntity (0.5 * 0.8 / 0.8 = 0.5)

        // example if we have 2 scores in history: [0.8, 0.7]
        // then accumulatedHistoricalScore = 0.7 * 0.5 + 0.8 * 0.2 = 0.35 + 0.16 = 0.51
        // maxScoreByEntity = 0.8 -> 0.51 / 0.8 = 0.6375
        
        //! penalties = exp^(-totalFailedVaults) (exp^(-1) = 0.36787)

        // newScore = (0.8 + (0.0125 * 0.5)) * 0.36787 = 0.29659

        const updatedScores = await scoring.getScores(entity.address);
        expect(updatedScores.length).to.equal(2);
        expect(Number(updatedScores[1]) / Number(100_000)).to.equal(0.29659);

        // entity scores is decreasing, it means that entity can create pool with lower size
        const previousMaxPoolSize = ethers.parseEther("800000"); // 800k
        expect(await scoring.getMaxPoolSize(entity.address)).to.be.lessThan(previousMaxPoolSize);
    });
});

