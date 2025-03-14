import { Staking, MockERC20, Treasury, VaultFactory, License, Scoring, Oracle, MockQuadata, Vault } from "../../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { deployAllContracts } from "../utils";
import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { APPLICATION_FEE, LICENSE_MONTHLY_FEE, DEFAULT_VAULT_PARAMS, COLLATERAL_AMOUNT } from "../constants";

describe("GoilTreasury", function () {
	let treasury: Treasury;
	let vaultFactory: VaultFactory;
	let license: License;
	let scoring: Scoring;
	let staking: Staking;
	let goilToken: MockERC20;
	let stableToken: MockERC20;
	let stableToken2: MockERC20;
	let oracle: Oracle;
	let qadrataReader: MockQuadata;
	let admin: HardhatEthersSigner;
	let treasuryManager: HardhatEthersSigner;
	let entity: HardhatEthersSigner;
	let user1: HardhatEthersSigner;
	let user2: HardhatEthersSigner;
	let randomUser: HardhatEthersSigner;

	let startTime: number;
	const MAX_COLLATERAL_PERCENTAGE = 100_00;
	const DEFAULT_COLLATERAL_PERCENTAGE = 10_00;
	const collateralAmount = COLLATERAL_AMOUNT;
	const fees = LICENSE_MONTHLY_FEE * 12n + APPLICATION_FEE;

	beforeEach(async () => {
		const fixture = await loadFixture(deployAllContracts);
		treasury = fixture.treasury;
		vaultFactory = fixture.vaultFactory;
		license = fixture.license;
		scoring = fixture.scoring;
		staking = fixture.staking;
		qadrataReader = fixture.quadata;
		oracle = fixture.oracle;
		goilToken = fixture.goilToken;
		stableToken = fixture.stableToken;
		stableToken2 = fixture.stableToken2;
		admin = fixture.admin;
		treasuryManager = fixture.admin;
		entity = fixture.entity;
		user1 = fixture.user1;
		user2 = fixture.user2;
		randomUser = fixture.user3;
		startTime = (await time.latest()) + 24 * 60 * 60; // in 1 day
	});

	const createLicense = async () => {
		await qadrataReader.connect(entity).mint(entity.address, 1n);
		await goilToken.connect(entity).mint(entity.address, collateralAmount + fees);
		await goilToken.connect(entity).approve(license.target, collateralAmount + fees);
		await license.connect(entity).submitLicense(12, collateralAmount);
		await license.approveLicense(entity.address, true);
		await scoring.setPerformanceData(entity.address, 70_000n, 60_000n);
	};

	const createVault = async () => {
		const startTime = (await time.latest()) + 24 * 60 * 60; // in day
		const requiredCollateral = await treasury.getRequiredCollateral(DEFAULT_VAULT_PARAMS.desiredCap);
		await goilToken.connect(entity).mint(entity.address, requiredCollateral);
		await goilToken.connect(entity).approve(treasury.target, requiredCollateral);

		await vaultFactory
			.connect(entity)
			.createVault(
				stableToken.target,
				DEFAULT_VAULT_PARAMS.rate,
				DEFAULT_VAULT_PARAMS.desiredCap,
				startTime,
				DEFAULT_VAULT_PARAMS.fundingPeriod,
				DEFAULT_VAULT_PARAMS.unlockPeriod
			);

		const vaults = await vaultFactory.getVaultsByEntity(entity.address);
		return vaults[0].vault;
	};

	const fundAndRepayVault = async (repayPercent: number, vaultAddress: string) => {
		const vault = await ethers.getContractAt("Vault", vaultAddress);
		const capToRepay = ((await vault.promisedCap()) * BigInt(repayPercent)) / 100n;
		const poolSize = DEFAULT_VAULT_PARAMS.desiredCap;
		const startTime = Number(await vault.startTime());

		await stableToken.connect(user1).mint(user1.address, poolSize);
		await stableToken.connect(user1).approve(vaultAddress, poolSize);
		await time.increaseTo(startTime + 1);
		await vault.connect(user1)["deposit(uint256)"](poolSize);
		await time.increaseTo(startTime + DEFAULT_VAULT_PARAMS.fundingPeriod);
		await vault.connect(entity).withdrawToEntity();
		await time.increaseTo(startTime + DEFAULT_VAULT_PARAMS.fundingPeriod + DEFAULT_VAULT_PARAMS.unlockPeriod + 1);

		await stableToken.connect(entity).mint(entity.address, capToRepay);
		await stableToken.connect(entity).approve(vaultAddress, capToRepay);
		await vault.connect(entity).depositFromEntity(capToRepay);
	};

	describe("Deployment Functionality", function () {
		it("Should set the correct GOIL token", async function () {
			expect(await treasury.GOIL_TOKEN()).to.equal(goilToken.target);
		});

		it("Should set the correct oracle", async function () {
			expect(await treasury.ORACLE()).to.equal(oracle.target);
		});

		it("Should set the correct vault factory", async function () {
			expect(await treasury.VAULT_FACTORY()).to.equal(vaultFactory.target);
		});

		it("Should set the correct collateral percentage", async function () {
			expect(await treasury.requiredCollateralPercentage()).to.equal(DEFAULT_COLLATERAL_PERCENTAGE);
		});

		it("Should set the correct maximum collateral percentage", async function () {
			expect(await treasury.MAX_COLLATERAL_PERCENTAGE()).to.equal(MAX_COLLATERAL_PERCENTAGE);
		});

		it("Should assign admin roles", async function () {
			const DEFAULT_ADMIN_ROLE = await treasury.DEFAULT_ADMIN_ROLE();
			const TREASURY_MANAGER_ROLE = await treasury.TREASURY_MANAGER_ROLE();
			
			expect(await treasury.hasRole(DEFAULT_ADMIN_ROLE, admin.address)).to.be.true;
			expect(await treasury.hasRole(TREASURY_MANAGER_ROLE, admin.address)).to.be.true;
		});

		it("Should not deploy with a zero oracle address", async function () {
			const TreasuryFactory = await ethers.getContractFactory("Treasury");
			await expect(
				TreasuryFactory.deploy(
					goilToken.target,
					ethers.ZeroAddress, // zero address of oracle
					vaultFactory.target,
					admin.address
				)
			).to.be.revertedWithCustomError(TreasuryFactory, "OracleMustBeContract");
		});

		it("Should not deploy with a zero GOIL token address", async function () {
			const TreasuryFactory = await ethers.getContractFactory("Treasury");
			await expect(
				TreasuryFactory.deploy(
					ethers.ZeroAddress, // zero address of GOIL token
					oracle.target,
					vaultFactory.target,
					admin.address
				)
			).to.be.revertedWithCustomError(TreasuryFactory, "GoilTokenMustBeContract");
		});

		it("Should not deploy with a zero vault factory address", async function () {
			const TreasuryFactory = await ethers.getContractFactory("Treasury");
			await expect(
				TreasuryFactory.deploy(
					goilToken.target,
					oracle.target,
					ethers.ZeroAddress, // zero address of vault factory
					admin.address
				)
			).to.be.revertedWithCustomError(TreasuryFactory, "VaultFactoryMustBeContract");
		});

		it("Should not deploy with a zero admin address", async function () {
			const TreasuryFactory = await ethers.getContractFactory("Treasury");
			await expect(
				TreasuryFactory.deploy(
					goilToken.target,
					oracle.target,
					vaultFactory.target,
					ethers.ZeroAddress // zero address of admin
				)
			).to.be.revertedWithCustomError(TreasuryFactory, "AdminCannotBeZeroAddress");
		});

		it("Should not deploy if parameters are not contracts", async function () {
			const TreasuryFactory = await ethers.getContractFactory("Treasury");
			
			await expect(
				TreasuryFactory.deploy(
					randomUser.address, // not a contract
					oracle.target,
					vaultFactory.target,
					admin.address
				)
			).to.be.revertedWithCustomError(TreasuryFactory, "GoilTokenMustBeContract");
			
			await expect(
				TreasuryFactory.deploy(
					goilToken.target,
					randomUser.address, // not a contract
					vaultFactory.target,
					admin.address
				)
			).to.be.revertedWithCustomError(TreasuryFactory, "OracleMustBeContract");
			
			await expect(
				TreasuryFactory.deploy(
					goilToken.target,
					oracle.target,
					randomUser.address, // not a contract
					admin.address
				)
			).to.be.revertedWithCustomError(TreasuryFactory, "VaultFactoryMustBeContract");
		});
	});

	describe("Collateral Functionality", function () {
		it("Should allow depositing collateral through license", async function () {
			await qadrataReader.connect(entity).mint(entity.address, 1n);
			await goilToken.connect(entity).mint(entity.address, collateralAmount + fees);
			await goilToken.connect(entity).approve(license.target, collateralAmount + fees);
			await license.connect(entity).submitLicense(12, collateralAmount);

			// Check that the application fee is charged
			expect(await goilToken.balanceOf(treasury.target)).to.equal(APPLICATION_FEE);

			await license.approveLicense(entity.address, true);

			// After license approval, collateral should be transferred to the treasury
			expect(await goilToken.balanceOf(treasury.target)).to.equal(fees + collateralAmount);

			const collateralInfo = await treasury.collateral(entity.address);
			expect(collateralInfo.collateralLocked).to.equal(collateralAmount);
		});

		it("Should allow depositing collateral through vault factory", async function () {
			await createLicense();

			const collateralBefore = (await treasury.collateral(entity.address)).collateralLocked;
			const requiredCollateral = await treasury.getRequiredCollateral(DEFAULT_VAULT_PARAMS.desiredCap);

			// By default, collateral is 10% of the desired vault cap
			expect(requiredCollateral).to.equal(BigInt(Number(DEFAULT_VAULT_PARAMS.desiredCap) * 0.1));

			await goilToken.connect(entity).mint(entity.address, requiredCollateral);
			await goilToken.connect(entity).approve(treasury.target, requiredCollateral);
			await createVault();

			const collateralInfo = await treasury.collateral(entity.address);
			expect(collateralInfo.collateralLocked).to.equal(requiredCollateral + collateralBefore);
		});

		it("Should not allow depositing collateral directly (without license)", async function () {
			await expect(
				treasury.connect(entity)["depositCollateral(address,uint256)"](entity.address, 1000)
			).to.be.revertedWithCustomError(treasury, "OnlyLicenseAllowed");
		});

		it("Should not allow depositing collateral directly (without license) through vault factory", async function () {
			await expect(
				treasury.connect(entity)["depositCollateral(address,uint256,uint256,uint256)"](entity.address, 1000, 500, 10000)
			).to.be.revertedWithCustomError(treasury, "OnlyVaultFactoryAllowed");
		});
	});

	describe("Withdrawal Collateral Functionality", function () {
		it("Should allow withdrawing collateral after license expiration and vault expiry", async function () {
			await createLicense();

			await time.increaseTo(
				(await license.getLicenseExpirationTime(entity.address)) + 
				(await vaultFactory.VAULT_EXPIRY_LIMIT_AFTER_LICENSE()) + 1n
			);

			const entityBalanceBefore = await goilToken.balanceOf(entity.address);
			const treasuryBalanceBefore = await goilToken.balanceOf(treasury.target);

			await treasury.connect(entity).withdrawCollateral();
			
			const entityBalanceAfter = await goilToken.balanceOf(entity.address);
			const treasuryBalanceAfter = await goilToken.balanceOf(treasury.target);

			const collateralInfo = await treasury.collateral(entity.address);

			expect(collateralInfo.collateralLocked).to.equal(0n);
			expect(collateralInfo.collateralUnlocked).to.equal(0n);
			expect(entityBalanceAfter).to.equal(entityBalanceBefore + collateralAmount);
			expect(treasuryBalanceAfter).to.equal(treasuryBalanceBefore - collateralAmount);
		});

		it("Should allow withdrawing only unlocked collateral when license is still active", async function () {
			await createLicense();
			const vaultAddress = await createVault();
			
			// Get vault information
			const vaultInfo = await vaultFactory.getVault(vaultAddress);
			const requiredCollateral = vaultInfo.collateralAmount;
			
			// Successful vault funding and repayment
			await fundAndRepayVault(100, vaultAddress);
			
			// Check unlocked collateral
			const collateralInfoAfterUnlock = await treasury.collateral(entity.address);
			expect(collateralInfoAfterUnlock.collateralUnlocked).to.equal(requiredCollateral);
			
			// Withdraw unlocked collateral
			const entityBalanceBefore = await goilToken.balanceOf(entity.address);
			await treasury.connect(entity).withdrawCollateral();
			const entityBalanceAfter = await goilToken.balanceOf(entity.address);
			
			// Check balances
			const collateralInfoAfterWithdraw = await treasury.collateral(entity.address);
			expect(collateralInfoAfterWithdraw.collateralUnlocked).to.equal(0n);
			expect(entityBalanceAfter).to.equal(entityBalanceBefore + requiredCollateral);
		});

		it("Should not allow withdrawing collateral if there is no collateral to withdraw", async function () {
			await expect(
				treasury.connect(entity).withdrawCollateral()
			).to.be.revertedWithCustomError(treasury, "NoCollateralToWithdraw");
		});

		it("Should not allow withdrawing collateral if necessary contracts are not set", async function () {
			const TreasuryFactory = await ethers.getContractFactory("Treasury");
			const newTreasury = await TreasuryFactory.deploy(
				goilToken.target,
				oracle.target,
				vaultFactory.target,
				admin.address
			);

			await expect(
				newTreasury.connect(entity).withdrawCollateral()
			).to.be.revertedWithCustomError(newTreasury, "ScoringContractNotSet");
		});

		it("Should not allow withdrawing collateral if it violates the refundable amount condition", async function () {
			await createLicense();
			const vaultAddress = await createVault();
			
			// Get vault information
			const vaultInfo = await vaultFactory.getVault(vaultAddress);
			
			// Create situation where treasury balance is less than totalRefundableAmount
			// First, make some collateral unlocked
			await fundAndRepayVault(100, vaultAddress);
			await createVault();

			// Withdraw most of the tokens from the treasury (admin can do this)
			const currentBalance = await goilToken.balanceOf(treasury.target);
			const amountToWithdraw = currentBalance - (await treasury.totalRefundableAmount());
			await treasury.connect(admin).withdrawTokens(admin.address, goilToken.target, amountToWithdraw);
			

			// Now treasury balance is less than totalRefundableAmount, trying to withdraw collateral should fail
			await expect(
				treasury.connect(entity).withdrawCollateral()
			).to.be.revertedWithCustomError(treasury, "InsufficientRefundableAmount");
		});
	});

	describe("Unlock Collateral Functionality", function () {
		it("Should allow unlocking collateral through scoring", async function () {
			await createLicense();
			const vaultAddress = await createVault();
			
			// Get vault information
			const vaultInfo = await vaultFactory.getVault(vaultAddress);
			const requiredCollateral = vaultInfo.collateralAmount;
			const refundableAmount = vaultInfo.refundableAmount;
			
			// Check initial state
			const initialCollateralInfo = await treasury.collateral(entity.address);
			const initialTotalRefundable = await treasury.totalRefundableAmount();
			const initialTotalBorrowed = await treasury.getTotalBorrowed(entity.address);
			
			// Unlock collateral through scoring
			await fundAndRepayVault(100, vaultAddress);
			
			// Check state after unlocking
			const collateralInfoAfter = await treasury.collateral(entity.address);
			expect(collateralInfoAfter.collateralLocked).to.equal(initialCollateralInfo.collateralLocked - requiredCollateral);
			expect(collateralInfoAfter.collateralUnlocked).to.equal(initialCollateralInfo.collateralUnlocked + requiredCollateral);
			
			// Check totalRefundableAmount change
			expect(await treasury.totalRefundableAmount()).to.equal(initialTotalRefundable - refundableAmount);
			
			// Check totalBorrowed change
			expect(await treasury.getTotalBorrowed(entity.address)).to.equal(initialTotalBorrowed - vaultInfo.desiredCap);
		});

		it("Should not allow unlocking collateral to anyone except scoring", async function () {
			await expect(
				treasury.connect(entity).unlockCollateral(ethers.ZeroAddress)
			).to.be.revertedWithCustomError(treasury, "OnlyScoringAllowed");
		});
	});

	describe("Administrative Functions", function () {
		it("Should allow setting required collateral percentage", async function () {
			const newPercentage = 20_00; // 20%
			
			await expect(
				treasury.connect(admin).setRequiredCollateralPercentage(newPercentage)
			).to.emit(treasury, "RequiredCollateralPercentageUpdated")
			  .withArgs(newPercentage);
			
			expect(await treasury.requiredCollateralPercentage()).to.equal(newPercentage);
		});

		it("Should not allow setting zero collateral percentage", async function () {
			await expect(
				treasury.connect(admin).setRequiredCollateralPercentage(0)
			).to.be.revertedWithCustomError(treasury, "RequiredCollateralPercentageCannotBeZero");
		});

		it("Should not allow setting collateral percentage above maximum", async function () {
			await expect(
				treasury.connect(admin).setRequiredCollateralPercentage(MAX_COLLATERAL_PERCENTAGE + 1)
			).to.be.revertedWithCustomError(treasury, "RequiredCollateralPercentageTooHigh");
		});

		it("Should not allow setting the same collateral percentage", async function () {
			await expect(
				treasury.connect(admin).setRequiredCollateralPercentage(DEFAULT_COLLATERAL_PERCENTAGE)
			).to.be.revertedWithCustomError(treasury, "RequiredCollateralPercentageCannotBeTheSame");
		});

		it("Should allow treasury manager to withdraw tokens", async function () {
			// First, increase treasury balance
			await goilToken.connect(admin).mint(treasury.target, ethers.parseEther("1000"));
			await stableToken.connect(admin).mint(treasury.target, ethers.parseEther("500"));
			
			const initialRecipientBalance = await stableToken.balanceOf(user1.address);
			const initialTreasuryBalance = await stableToken.balanceOf(treasury.target);
			const amountToWithdraw = ethers.parseEther("100");
			
			// Execute withdrawal of tokens by treasury manager
			await treasury.connect(treasuryManager).withdrawTokens(
				user1.address,
				stableToken.target,
				amountToWithdraw
			);
			
			// Check balance changes
			expect(await stableToken.balanceOf(user1.address)).to.equal(initialRecipientBalance + amountToWithdraw);
			expect(await stableToken.balanceOf(treasury.target)).to.equal(initialTreasuryBalance - amountToWithdraw);
		});

		it("Should allow treasury manager to withdraw all tokens", async function () {
			// First, increase treasury balance
			const amountToMint = ethers.parseEther("500");
			await stableToken.connect(admin).mint(treasury.target, amountToMint);
			
			const initialRecipientBalance = await stableToken.balanceOf(treasuryManager.address);
			const initialTreasuryBalance = await stableToken.balanceOf(treasury.target);
			
			// Execute withdrawal of all tokens by treasury manager
			await treasury.connect(treasuryManager).withdrawAllTokens(stableToken.target);
			
			// Check balance changes
			expect(await stableToken.balanceOf(treasuryManager.address)).to.equal(initialRecipientBalance + initialTreasuryBalance);
			expect(await stableToken.balanceOf(treasury.target)).to.equal(0);
		});

		it("Should not allow withdrawing tokens to anyone except treasury manager", async function () {
			const messageId = await treasury.TREASURY_MANAGER_ROLE();
			
			await expect(
				treasury.connect(entity).withdrawTokens(user1.address, stableToken.target, 1000)
			).to.be.revertedWithCustomError(treasury, "AccessControlUnauthorizedAccount")
			  .withArgs(entity.address, messageId);
			
			await expect(
				treasury.connect(entity).withdrawAllTokens(stableToken.target)
			).to.be.revertedWithCustomError(treasury, "AccessControlUnauthorizedAccount")
			  .withArgs(entity.address, messageId);
		});

		it("Should not allow withdrawing tokens if it violates the refundable amount condition", async function () {
			await createLicense();
			const vaultAddress = await createVault();
			
			// Get vault information
			const vaultInfo = await vaultFactory.getVault(vaultAddress);
			const refundableAmount = vaultInfo.refundableAmount;
			
			// Create situation where withdrawing tokens will violate the refundable amount condition
			const currentBalance = await goilToken.balanceOf(treasury.target);
			const amountToWithdraw = currentBalance - (await treasury.totalRefundableAmount()) + 1n;
			
			await expect(
				treasury.connect(treasuryManager).withdrawTokens(user1.address, goilToken.target, amountToWithdraw)
			).to.be.revertedWithCustomError(treasury, "InsufficientRefundableAmount");
			
			await expect(
				treasury.connect(treasuryManager).withdrawAllTokens(goilToken.target)
			).to.be.revertedWithCustomError(treasury, "InsufficientRefundableAmount");
		});

		it("Should allow admin to set scoring contract", async function () {
			// Deploy new treasury without contracts
			const TreasuryFactory = await ethers.getContractFactory("Treasury");
			const newTreasury = await TreasuryFactory.deploy(
				goilToken.target,
				oracle.target,
				vaultFactory.target,
				admin.address
			);
			
			// Set scoring contract
			await expect(
				newTreasury.connect(admin).setScoringContract(scoring.target)
			).to.emit(newTreasury, "ScoringContractUpdated")
			  .withArgs(scoring.target);
			
			expect(await newTreasury.SCORING()).to.equal(scoring.target);
		});

		it("Should allow admin to set staking contract", async function () {
			// Deploy new treasury without contracts
			const TreasuryFactory = await ethers.getContractFactory("Treasury");
			const newTreasury = await TreasuryFactory.deploy(
				goilToken.target,
				oracle.target,
				vaultFactory.target,
				admin.address
			);
			
			// Set staking contract
			await expect(
				newTreasury.connect(admin).setStakingContract(staking.target)
			).to.emit(newTreasury, "StakingContractUpdated")
			  .withArgs(staking.target);
			
			expect(await newTreasury.STAKING()).to.equal(staking.target);
		});
	});
});
