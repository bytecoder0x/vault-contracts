import { ethers } from "hardhat";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import {
	AMOUNT_FOR_ROUTER,
	APPLICATION_FEE,
	COLLATERAL_AMOUNT,
	INITIAL_SUPPLY,
	LICENSE_MONTHLY_FEE,
	MARKET_CONDITION_RATIO,
	THRESHOLD_CAPITAL,
	THRESHOLD_COLLATERAL,
	VOTING_PERIOD,
} from "./constants";
import { MockQuadata } from "../typechain-types";
import { License } from "../typechain-types";
import { Scoring } from "../typechain-types";
import { Treasury, VaultFactory } from "../typechain-types";
import { MockERC20 } from "../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
export const deployAllContracts = async () => {
	const [admin, entity, entity2, user1, user2, user3, user4] = await ethers.getSigners();
	const MockERC20Factory = await ethers.getContractFactory("MockERC20");

	const goilToken = await MockERC20Factory.deploy(INITIAL_SUPPLY);
	await goilToken.waitForDeployment();

	const stableToken = await MockERC20Factory.deploy(INITIAL_SUPPLY);
	await stableToken.waitForDeployment();

	const QuadataFactory = await ethers.getContractFactory("MockQuadata");
	const quadata = await QuadataFactory.deploy();
	await quadata.waitForDeployment();

	const mockFactoryFactory = await ethers.getContractFactory("MockFactory");
	const mockFactory = await mockFactoryFactory.deploy();
	await mockFactory.waitForDeployment();

	const mockPoolFactory = await ethers.getContractFactory("MockPool");
	const mockPool = await mockPoolFactory.deploy(goilToken.target, stableToken.target);
	await mockPool.waitForDeployment();
	await mockFactory.setPool(goilToken.target, stableToken.target, 5_00, mockPool.target);

	const mockRouterV2Factory = await ethers.getContractFactory("MockRouterV2");
	const mockRouterV2 = await mockRouterV2Factory.deploy();
	await mockRouterV2.waitForDeployment();

	const mockRouterV3Factory = await ethers.getContractFactory("MockRouterV3");
	const mockRouterV3 = await mockRouterV3Factory.deploy();
	await mockRouterV3.waitForDeployment();

	const mockQuoterFactory = await ethers.getContractFactory("MockQuoterV2");
	const mockQuoter = await mockQuoterFactory.deploy();
	await mockQuoter.waitForDeployment();

	const oracleFactory = await ethers.getContractFactory("Oracle");
	const oracle = await oracleFactory.deploy(mockFactory.target, admin.address, goilToken.target, stableToken.target, 5_00);
	await oracle.waitForDeployment();

	const vaultFactoryFactory = await ethers.getContractFactory("VaultFactory");
	const vaultFactory = await vaultFactoryFactory.deploy(
		admin.address,
		goilToken.target,
		oracle.target,
		mockRouterV2.target,
		mockRouterV3.target,
		mockQuoter.target,
		[stableToken.target]
	);
	await vaultFactory.waitForDeployment();

	const TreasuryFactory = await ethers.getContractFactory("Treasury");
	const treasury = await TreasuryFactory.deploy(goilToken.target, oracle.target, vaultFactory.target, admin.address);
	await treasury.waitForDeployment();

	const LicenseFactory = await ethers.getContractFactory("License");
	const license = await LicenseFactory.deploy(
		admin.address,
		quadata.target,
		goilToken.target,
		treasury.target,
		APPLICATION_FEE,
		LICENSE_MONTHLY_FEE
	);
	await license.waitForDeployment();

	const scoringFactory = await ethers.getContractFactory("Scoring");
	const scoring = await scoringFactory.deploy(
		admin.address,
		vaultFactory.target,
		treasury.target,
		license.target,
		goilToken.target,
		THRESHOLD_CAPITAL,
		THRESHOLD_COLLATERAL,
		MARKET_CONDITION_RATIO
	);
	await scoring.waitForDeployment();

	const stakingFactory = await ethers.getContractFactory("Staking");
	const staking = await stakingFactory.deploy(treasury.target, goilToken.target, goilToken.target);
	await staking.waitForDeployment();

	await vaultFactory.setScoringContract(scoring.target);
	await vaultFactory.setStakingContract(staking.target);
	await vaultFactory.setTreasuryContract(treasury.target);
	await vaultFactory.setLicenseContract(license.target);

	await treasury.setScoringContract(scoring.target);
	await treasury.setStakingContract(staking.target);
	await treasury.setLicenseContract(license.target);

	await license.setScoringContract(scoring.target);

	await goilToken.mint(mockRouterV3.target, AMOUNT_FOR_ROUTER);

	return {
		admin,
		entity,
		entity2,
		user1,
		user2,
		user3,
		user4,
		goilToken,
		stableToken,
		mockFactory,
		mockPool,
		mockRouterV2,
		mockRouterV3,
		mockQuoter,
		quadata,
		oracle,
		vaultFactory,
		treasury,
		license,
		scoring,
		staking,
		INITIAL_SUPPLY,
		APPLICATION_FEE,
		LICENSE_MONTHLY_FEE,
		THRESHOLD_COLLATERAL,
		THRESHOLD_CAPITAL,
		MARKET_CONDITION_RATIO,
	};
};

export const createAndRepayVault = async (
	entity: HardhatEthersSigner,
	user1: HardhatEthersSigner,
	qadrataReader: MockQuadata,
	license: License,
	scoring: Scoring,
	treasury: Treasury,
	vaultFactory: VaultFactory,
	goilToken: MockERC20,
	stableToken: MockERC20,
	withLicense: boolean = true,
	indexVault: number
) => {
	if (!withLicense) {
		const licenseStartTime = BigInt(await time.latest()) + BigInt(VOTING_PERIOD) + 1n;

		const licenseEndTime = licenseStartTime + 365n * 24n * 3600n;
		const totalFeeWithCollateral = APPLICATION_FEE + LICENSE_MONTHLY_FEE * 12n + COLLATERAL_AMOUNT;

		await qadrataReader.connect(entity).mint(entity.address, 1n);
		await goilToken.connect(entity).mint(entity.address, totalFeeWithCollateral);
		await goilToken.connect(entity).approve(license.target, totalFeeWithCollateral);
		await license.connect(entity).submitLicense(licenseEndTime, COLLATERAL_AMOUNT);
		await scoring.setPerformanceData(entity.address, 50_000, 50_000);
		await license.approveLicense(entity.address, true);
	}

	const rate = 11_00; // 11%
	const startTime = (await time.latest()) + 24 * 60 * 60; // in 1 day
	const fundingPeriod = 14 * 24 * 60 * 60; // 14 days
	const unlockPeriod = 3 * 31 * 24 * 60 * 60; // 3 months
	const desiredCap = ethers.parseEther("100000");

	const requiredCollateral = await treasury.getRequiredCollateral(desiredCap);
	await goilToken.connect(entity).mint(entity.address, requiredCollateral);
	await goilToken.connect(entity).approve(treasury.target, requiredCollateral);
	await vaultFactory.connect(entity).createVault(stableToken.target, rate, desiredCap, startTime, fundingPeriod, unlockPeriod);
	const vaults = await vaultFactory.getAllVaults();
	const vault = await ethers.getContractAt("Vault", vaults[indexVault].vault);

	await stableToken.connect(user1).mint(user1.address, desiredCap);
	await stableToken.connect(user1).approve(vault.target, desiredCap);

	await time.increaseTo(startTime);
	await vault.connect(user1)["deposit(uint256)"](desiredCap);
	await time.increaseTo(startTime + fundingPeriod + 1);
	await vault.connect(entity).withdrawToEntity();
	const promisedAPY = (desiredCap * 11n) / 100n;
	const promisedCapital = desiredCap + promisedAPY;

	await stableToken.connect(entity).mint(entity.address, promisedCapital);
	await stableToken.connect(entity).approve(vault.target, promisedCapital);
	await vault.connect(entity).depositFromEntity();
};
