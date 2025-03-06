import { Staking, MockERC20, Treasury, VaultFactory, License, Scoring, Oracle, MockQuadata } from "../../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { deployAllContracts } from "../utils";
import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { APPLICATION_FEE, LICENSE_MONTHLY_FEE, DEFAULT_VAULT_PARAMS } from "../constants";
describe("GoilTreasury", function () {
	let treasury: Treasury;
	let vaultFactory: VaultFactory;
	let license: License;
	let scoring: Scoring;
	let goilToken: MockERC20;
	let stableToken: MockERC20;
	let oracle: Oracle;
	let qadrataReader: MockQuadata;
	let admin: HardhatEthersSigner;
	let entity: HardhatEthersSigner;
	let user1: HardhatEthersSigner;
	let user2: HardhatEthersSigner;

	beforeEach(async () => {
		const fixture = await loadFixture(deployAllContracts);
		treasury = fixture.treasury;
		vaultFactory = fixture.vaultFactory;
		license = fixture.license;
		qadrataReader = fixture.quadata;
		scoring = fixture.scoring;
		oracle = fixture.oracle;
		goilToken = fixture.goilToken;
		stableToken = fixture.stableToken;
		admin = fixture.admin;
		entity = fixture.entity;
		user1 = fixture.user1;
		user2 = fixture.user2;
	});

    const collateralAmount = ethers.parseEther("10000");
    const fees = LICENSE_MONTHLY_FEE * 12n + APPLICATION_FEE;

    const submitLicense = async () => {
        await qadrataReader.connect(entity).mint(entity.address, 1n);
        await goilToken.connect(entity).mint(entity.address, collateralAmount + fees);
        await goilToken.connect(entity).approve(license.target, collateralAmount + fees);
        await license.connect(entity).submitLicense(12, collateralAmount);
    }

    const createVault = async () => {
        const startTime = (await time.latest()) + 24 * 60 * 60; // in 1 day

        const vault = await vaultFactory
			.connect(entity)
			.createVault(
				stableToken.target,
				DEFAULT_VAULT_PARAMS.rate,
				DEFAULT_VAULT_PARAMS.desiredCap,
				startTime,
				DEFAULT_VAULT_PARAMS.fundingPeriod,
				DEFAULT_VAULT_PARAMS.unlockPeriod
			);

        return vault;
    }

	describe("Deployment", function () {
		it("Should set the correct GOIL token", async function () {
			expect(await treasury.GOIL_TOKEN()).to.equal(goilToken.target);
		});

		it("Should set the correct oracle", async function () {
			expect(await treasury.ORACLE()).to.equal(oracle.target);
		});

		it("Should set the correct vault factory", async function () {
			expect(await treasury.VAULT_FACTORY()).to.equal(vaultFactory.target);
		});
	});

	it("Should allow depositing collateral and fees through license", async function () {  
        await submitLicense();
		expect(await goilToken.balanceOf(treasury.target)).to.equal(APPLICATION_FEE);

        await license.approveLicense(entity.address, true);

        expect(await goilToken.balanceOf(treasury.target)).to.equal(fees + collateralAmount);

        const collateralInfo = await treasury.collateral(entity.address);
        expect(collateralInfo.collateralLocked).to.equal(collateralAmount);
	});

    it("Should allow depositing collateral through vault factory", async function () {
        await submitLicense();
        await license.approveLicense(entity.address, true);
        await scoring.setPerformanceData(entity.address, 70_000n, 60_000n);

        const collateralBefore = (await treasury.collateral(entity.address)).collateralLocked;
        const requiredCollateral = await treasury.getRequiredCollateral(DEFAULT_VAULT_PARAMS.desiredCap);

        expect(requiredCollateral).to.equal(BigInt(Number(DEFAULT_VAULT_PARAMS.desiredCap) * 0.1)); // 10% of desired cap

        await goilToken.connect(entity).mint(entity.address, requiredCollateral);
        await goilToken.connect(entity).approve(treasury.target, requiredCollateral);
        await createVault();

        const collateralInfo = await treasury.collateral(entity.address);
        expect(collateralInfo.collateralLocked).to.equal(requiredCollateral + collateralBefore);
      });

      it("Should allow withdrawing collateral when license is inactive", async function () {
        await submitLicense();
        await license.approveLicense(entity.address, true);
        await scoring.setPerformanceData(entity.address, 70_000n, 60_000n);

        await time.increaseTo(await license.getLicenseExpirationTime(entity.address) + 1n);

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

    it("Should allow withdrawing collateral when vault is successfully funded", async function () {
        await submitLicense();
        await license.approveLicense(entity.address, true);
        await scoring.setPerformanceData(entity.address, 70_000n, 60_000n);
        const vaultAddress = await createVault();
        

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
});
