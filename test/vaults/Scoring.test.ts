import { Staking, MockERC20, Treasury, VaultFactory, License, Scoring, Oracle, MockQuadata, Vault } from "../../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { deployAllContracts } from "../utils";
import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { APPLICATION_FEE, LICENSE_MONTHLY_FEE, DEFAULT_VAULT_PARAMS } from "../constants";

// TODO: scenario for old vault that was liquidated 
describe("GoilScoring", function () {
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
    let entity2: HardhatEthersSigner;
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
        entity2 = fixture.entity2;
        user1 = fixture.user1;
        user2 = fixture.user2;
    });

    const collateralAmount = ethers.parseEther("100000");
    const fees = LICENSE_MONTHLY_FEE * 12n + APPLICATION_FEE;

    const createLicense = async (currentEntity: HardhatEthersSigner = entity) => {
        await qadrataReader.connect(currentEntity).mint(currentEntity.address, 1n);
        await goilToken.connect(currentEntity).mint(currentEntity.address, collateralAmount + fees);
        await goilToken.connect(currentEntity).approve(license.target, collateralAmount + fees);
        await license.connect(currentEntity).submitLicense(12, collateralAmount);
        await license.approveLicense(currentEntity.address, true);
    };

    const createAndFundVault = async (
		percentageToFund: number,
		indexOfVault: number,
		repaidAfterLiquidation: boolean = false,
		poolSize: bigint = DEFAULT_VAULT_PARAMS.desiredCap,
        currentEntity: HardhatEthersSigner = entity,
		interestRate: number = DEFAULT_VAULT_PARAMS.rate,
	): Promise<Vault> => {
		const requiredCollateral = await treasury.getRequiredCollateral(poolSize);
		await goilToken.connect(currentEntity).mint(currentEntity.address, requiredCollateral);
		await goilToken.connect(currentEntity).approve(treasury.target, requiredCollateral);

		const startTime: number = (await time.latest()) + 24 * 60 * 60;

		await vaultFactory
			.connect(currentEntity)
			.createVault(
				stableToken.target,
				interestRate,
				poolSize,
				startTime,
				DEFAULT_VAULT_PARAMS.fundingPeriod,
				DEFAULT_VAULT_PARAMS.unlockPeriod
			);

		const vaults = await vaultFactory.getVaultsByEntity(currentEntity.address);
		const vaultAddress = vaults[indexOfVault].vault;
        
		const vault = await ethers.getContractAt("Vault", vaultAddress);
        const promisedCap = await vault.promisedCap();
		const capToRepay = ((promisedCap * BigInt(percentageToFund)) / 100n);

		await stableToken.connect(user1).mint(user1.address, poolSize);
		await stableToken.connect(user1).approve(vaultAddress, poolSize);
		await time.increaseTo(startTime + 1);
		await vault.connect(user1)["deposit(uint256)"](poolSize);
		await time.increaseTo(startTime + DEFAULT_VAULT_PARAMS.fundingPeriod + 1);
		await vault.connect(currentEntity).withdrawToEntity();
        
        await stableToken.connect(currentEntity).mint(currentEntity.address, promisedCap);
        await stableToken.connect(currentEntity).approve(vaultAddress, promisedCap);

		if (percentageToFund > 0) {
            if (repaidAfterLiquidation) {
                await time.increaseTo(startTime + DEFAULT_VAULT_PARAMS.unlockPeriod + DEFAULT_VAULT_PARAMS.fundingPeriod + 1);
                await vault.liquidate();
            }

            await vault.connect(currentEntity).depositFromEntity(capToRepay);
		} else {
            await time.increaseTo(startTime + DEFAULT_VAULT_PARAMS.unlockPeriod + DEFAULT_VAULT_PARAMS.fundingPeriod + 1);
			await vault.liquidate();
		}

		return vault;
	};

    const formatScore = (score: number) => {
        return Number((score * 100_000).toFixed(2));
    };

    describe("Deployment", function () {
        it("Should set the correct initial parameters", async function () {
            expect(await scoring.GOIL_TOKEN()).to.equal(goilToken.target);
            expect(await scoring.TREASURY()).to.equal(treasury.target);
            expect(await scoring.LICENSE()).to.equal(license.target);
            expect(await scoring.VAULT_FACTORY()).to.equal(vaultFactory.target);
            expect(await scoring.decreaseSuccessFactor()).to.equal(80_000);
            expect(await scoring.poolSizeWeight()).to.equal(10_000);
        });

        it("Should grant admin role to deployer", async function () {
            const adminRole = await scoring.DEFAULT_ADMIN_ROLE();
            const scoringManagerRole = await scoring.SCORING_MANAGER_ROLE();
            
            expect(await scoring.hasRole(adminRole, admin.address)).to.be.true;
            expect(await scoring.hasRole(scoringManagerRole, admin.address)).to.be.true;
        });
    });

    describe("Performance Data Management", function () {
        it("Should set performance data correctly", async function () {
            await createLicense();
            
            await scoring.connect(admin).setPerformanceData(entity.address, 70_000, 60_000);
            
            const data = await scoring.performanceData(entity.address);
            expect(data.reputationRatio).to.equal(70_000);
            expect(data.financialHealthRatio).to.equal(60_000);
        });

        it("Should revert when setting invalid performance data", async function () {
            await expect(scoring.connect(admin).setPerformanceData(
                ethers.ZeroAddress, 70_000, 60_000
            )).to.be.revertedWithCustomError(scoring, "EntityCannotBeZeroAddress");

            await expect(scoring.connect(admin).setPerformanceData(
                entity.address, 0, 60_000
            )).to.be.revertedWithCustomError(scoring, "InvalidReputationRatio");

            await expect(scoring.connect(admin).setPerformanceData(
                entity.address, 70_000, 0
            )).to.be.revertedWithCustomError(scoring, "InvalidFinancialHealthRatio");
        });

        it("Should set performance data in batch", async function () {
            const entities = [entity.address, user1.address, user2.address];
            const reputationRatios = [70_000, 80_000, 90_000];
            const financialHealthRatios = [60_000, 70_000, 80_000];

            await scoring.connect(admin).setPerformanceDataBatch(
                entities,
                reputationRatios,
                financialHealthRatios
            );

            for (let i = 0; i < entities.length; i++) {
                const data = await scoring.performanceData(entities[i]);
                expect(data.reputationRatio).to.equal(reputationRatios[i]);
                expect(data.financialHealthRatio).to.equal(financialHealthRatios[i]);
            }
        });
    });

    describe("Score functionallity", function () {
        beforeEach(async () => {
            await createLicense();
            await createLicense(entity2);
            await scoring.connect(admin).setPerformanceData(entity.address, 50_000, 60_000); // 50% reputation, 60% financial health
            await scoring.connect(admin).setPerformanceData(entity2.address, 50_000, 60_000); // 50% reputation, 60% financial health
        });

        it("Should calculate initial score correctly", async function () {
            const initialScore = await scoring.getLastScore(entity.address);
            // w1 * collateralRatio + w2 * reputationRatio + w3 * financialHealthRatio + w4 * marketConditionRatio

    		// collateralRatio = collateralAmount / thresholdCollateral (10000 / 10000 = 1)

    		// for our case: 0.4 * 1 + 0.2 * 0.5 + 0.25 * 0.6 + 0.15 * 1 = 0.4 + 0.1 + 0.15 + 0.15 = 0.8
            const scores = await scoring.getScores(entity.address);
            expect(scores.length).to.equal(1);
            expect(initialScore).to.equal(formatScore(0.8)); // 0.8 * 100_000 (with precision)
            expect(await scoring.getMaxPoolSize(entity.address)).to.be.equal(ethers.parseEther("800000")); // threshold capital - 1 mln
        });

        it("Should correctly update entity score after successful vaults", async function () {
            await createAndFundVault(100, 0); // 100% funded is successful
            
            // entity score is updated after successful vault
            // formula for calculating new score: newScore = (lastScore + (poolSizeRatio * historicalPerformance)) * penalties

            // lastScore = 0.8
            // poolSizeRatio = poolSizeWeight * poolSize / maxPoolSize (0.1 * 100k / 800k = 0.0125)
            // historyScoreWeights = [0.1, 0.1, 0.1, 0.2, 0.5]  // we can get only last five scores
            // we can get only one score from history, then we use weights 0.5 for last score
            // accumulatedHistoricalScore / maxScoreByEntity (0.5 * 0.8 / 0.8 = 0.5)
            // penalties = exp^(-totalFailedVaults) (exp^(-0) = 1)

            // newScore = (0.8 + (0.0125 * 0.5)) * 1 = 0.80625

            const updatedScore = await scoring.getLastScore(entity.address);
            expect(updatedScore).to.be.equal(formatScore(0.80625));
            expect(await scoring.getMaxPoolSize(entity.address)).to.be.equal(ethers.parseEther("806250")); // threshold capital - 1 mln
            
            await createAndFundVault(100, 1); // successful second vault

            // lastScore = 0.80625

            // poolSizeRatio = poolSizeWeight * poolSize / maxPoolSize (0.1 * 100k / 806.25k = 0.01240)
            // historicalPerformance = 0.80625 * 0.5 + 0.8 * 0.2 = 0.403125 + 0.16 = 0.563125 -> 0.563125 / 0.80625 = 0.69844
            // newScore = (0.80625 + (0.012400 * 0.69844)) * 1 = 0.81491
            const updatedScore2 = await scoring.getLastScore(entity.address); 
            expect(updatedScore2).to.be.equal(formatScore(0.81491));
            expect(await scoring.getMaxPoolSize(entity.address)).to.be.equal(ethers.parseEther("814910")); // threshold capital - 1 mln

            await createAndFundVault(100, 2); // successful third vault

            // lastScore = 0.81491

            // poolSizeRatio = poolSizeWeight * poolSize / maxPoolSize (0.1 * 100k / 814.91k = 0.01227)
            // historicalPerformance = 0.81491 * 0.5 + 0.80625 * 0.2 + 0.8 * 0.1 = 0.407455 + 0.16125 + 0.08 = 0.648705 -> 0.648705 / 0.81491 = 0.79604
            // newScore = (0.81491 + (0.01227 * 0.79604)) * 1 = 0.82467
            const updatedScore3 = await scoring.getLastScore(entity.address);
            expect(updatedScore3).to.be.equal(formatScore(0.82467));
            expect(await scoring.getMaxPoolSize(entity.address)).to.be.equal(ethers.parseEther("824670")); // threshold capital - 1 mln
            
            await createAndFundVault(100, 3, false, ethers.parseEther("800000")); // successful fourth vault close to max pool size

            // poolSizeRatio = poolSizeWeight * poolSize / maxPoolSize (0.1 * 800k / 824.67k = 0.097)
            // historicalPerformance = 0.82467 * 0.5 + 0.81491 * 0.2 + 0.80625 * 0.1 + 0.8 * 0.1 = 0.412335 + 0.162982 + 0.080625 + 0.08 =
            // = 0.735942 -> 0.735942 / 0.82467 = 0.89240
            // newScore = (0.82467 + (0.097 * 0.89240)) * 1 = 0.91123
            const updatedScore4 = await scoring.getLastScore(entity.address);
            expect(updatedScore4).to.be.equal(formatScore(0.91123)); 
            expect(await scoring.getMaxPoolSize(entity.address)).to.be.equal(ethers.parseEther("911230")); // threshold capital - 1 mln

            const scores = await scoring.getScores(entity.address);
            const previousScore = scores[scores.length - 2];
            const lastScore = scores[scores.length - 1];
            // we create vault is close to max pool size and our score dont increase more than 10%
            expect(Number(previousScore) * 110 / 100).to.be.lt(Number(lastScore));

            //! our score increased from 0.8 to 0.91123 step by step
        });

        it("Should correctly update score after liquidation and recovered with new successful vault", async function () {
            await createAndFundVault(0, 0);

            // poolSizeRatio = poolSizeWeight * poolSize / maxPoolSize (0.1 * 100k / 800k = 0.0125)
            // historicalPerformance = accumulatedHistoricalScore / maxScoreByEntity (0.5 * 0.8 / 0.8 = 0.5)
            // penalties = exp^(-totalFailedVaults) (exp^(-1.0) = 0.36787)
            // newScore = (0.8 + (0.0125 * 0.5)) * 0.36787 = 0.29659

            const updatedScore = await scoring.getLastScore(entity.address);
            expect(updatedScore).to.be.equal(formatScore(0.29659));
            expect(await scoring.getMaxPoolSize(entity.address)).to.be.equal(ethers.parseEther("296590")); 
            
            await createAndFundVault(100, 1);

            // poolSizeRatio = poolSizeWeight * poolSize / maxPoolSize (0.1 * 100k / 296.59k = 0.033716)
            // historicalPerformance = 0.29659 * 0.5 + 0.8 * 0.2 = 0.148295 + 0.16 = 0.308295 -> 0.30829 / 0.8 = 0.38536
            // newScore = (0.29659 + (0.033716 * 0.38536)) * 1 = 0.30958

            const updatedScore2 = await scoring.getLastScore(entity.address);
            expect(updatedScore2).to.equal(formatScore(0.30958));
            expect(await scoring.getMaxPoolSize(entity.address)).to.be.equal(ethers.parseEther("309580")); 
        });

        it("Should correctly update score after liquidation and recovered if paid", async function () {
            await createAndFundVault(100, 0, true);
            
            // penalties after liquidation = exp^(-totalFailedVaults) (exp^(-1.0) = 0.36787)
            // score after liquidation = (0.8 + (0.0125 * 0.5)) * 0.36787 = 0.29659

            //! failed will be only 0.2 because we have 80% success rate since repaid all sum but after liqudation 
            //! if deposit after liqudation success rate will be multimply by 0.8 (decrease factor)

            // penalties after deposit to vault that was liquidated = (exp^(-0.2) = 0.81873)
            // score after deposit = (0.8 + (0.0125 * 0.5)) * 0.81873 ~ 0.66008 due to rounding mb delta of 0.00001
            
            const updatedScore1 = await scoring.getLastScore(entity.address);
            expect(updatedScore1).to.equal(formatScore(0.66008));
            expect(await scoring.getMaxPoolSize(entity.address)).to.be.equal(ethers.parseEther("660080"));

            await createAndFundVault(100, 1);

            // poolSizeRatio = poolSizeWeight * poolSize / maxPoolSize (0.1 * 100k / 660.08k = 0.01514)
            // historicalPerformance = 0.66008 * 0.5 + 0.8 * 0.2 = 0.33004 + 0.16 = 0.49004 -> 0.49004 / 0.8 = 0.61255
            // newScore = (0.66008 + (0.01514 * 0.61255)) * 1 = 0.66935
            
            const updatedScore2 = await scoring.getLastScore(entity.address);
            expect(updatedScore2).to.equal(formatScore(0.66935));
        });

        it("Should correctly update score after liquidation on OLD vault and increase next scores if paid to OLD vault", async function () {
            const liquidatedVault = await createAndFundVault(0, 0);
            await createAndFundVault(100, 1);
            await createAndFundVault(100, 2);

            const scores = await scoring.getScores(entity.address);
            const score0 = scores[0];
            const score1 = scores[1];
            const score2 = scores[2];
            const score3 = scores[3];

            // linear increase of score (see previous test)
            expect(score0).to.equal(formatScore(0.80000));
            expect(score1).to.equal(formatScore(0.29659));
            expect(score2).to.equal(formatScore(0.30958));
            expect(score3).to.equal(formatScore(0.32145));

            // we paid to OLD liquidated vault and expect that our previous score after OLD vault will be increased
            await liquidatedVault.connect(entity).depositFromEntity(await liquidatedVault.promisedCap());

            const updatedScores = await scoring.getScores(entity.address);
            const updatedScore1 = updatedScores[1];
            const updatedScore2 = updatedScores[2];
            const updatedScore3 = updatedScores[3];

            // penalties after liquidation = exp^(-totalFailedVaults) (exp^(-1.0) = 0.36787)
            // score after liquidation = (0.8 + (0.0125 * 0.5)) * 0.36787 = 0.29659

            //! failed will be only 0.2 because we have 80% success rate since repaid all sum but after liqudation 
            //! if deposit after liqudation success rate will be multimply by 0.8 (decrease factor)

            // penalties after deposit to vault that was liquidated = (exp^(-0.2) = 0.81873)
            // score after deposit = (0.8 + (0.0125 * 0.5)) * 0.81873 ~ 0.66008 due to rounding mb delta of 0.00001

            expect(updatedScore1).to.equal(formatScore(0.66008));
            expect(updatedScore2).to.equal(formatScore(0.66935)); // for next scores updated history performance & last score & pool size ratio
            expect(updatedScore3).to.equal(formatScore(0.67955));

            // lets check on entity2 what will be if entity repaid immediately after liquidation
            // all parameters are the same as for entity2 only this entity is repaid immediately after liquidation
            const liquidatedVault2 = await createAndFundVault(0, 0, false, DEFAULT_VAULT_PARAMS.desiredCap, entity2);
            await liquidatedVault2.connect(entity2).depositFromEntity(await liquidatedVault2.promisedCap());
            await createAndFundVault(100, 1, false, DEFAULT_VAULT_PARAMS.desiredCap, entity2);
            await createAndFundVault(100, 2, false, DEFAULT_VAULT_PARAMS.desiredCap, entity2);

            const scoresEntity2 = await scoring.getScores(entity2.address);
            const score0Entity2 = scoresEntity2[0];
            const score1Entity2 = scoresEntity2[1];
            const score2Entity2 = scoresEntity2[2];
            const score3Entity2 = scoresEntity2[3];

            // scores the same as for entity1. Its means our history score updated correctly
            expect(score0Entity2).to.equal(formatScore(0.80000));
            expect(score1Entity2).to.equal(formatScore(0.66008));
            expect(score2Entity2).to.equal(formatScore(0.66935));    
            expect(score3Entity2).to.equal(formatScore(0.67955));
        });

        it("Should update score correctly if paid only part of pool size", async function () {
            const vault = await createAndFundVault(50, 0);
            await time.increaseTo(Number(await vault.startTime()) + DEFAULT_VAULT_PARAMS.fundingPeriod + DEFAULT_VAULT_PARAMS.unlockPeriod + 1);
            await vault.liquidate();

            // lastScore = 0.8
            // poolSizeRatio = poolSizeWeight * poolSize / maxPoolSize (0.1 * 100k / 800k = 0.0125)
            // historyScoreWeights = [0.1, 0.1, 0.1, 0.2, 0.5]  // we can get only last five scores
            // we can get only one score from history, then we use weights 0.5 for last score
            // accumulatedHistoricalScore / maxScoreByEntity (0.5 * 0.8 / 0.8 = 0.5)
            // penalties = exp^(-totalFailedVaults) (exp^(-0.5) = 0.60653) // ! 0.5 is 50% pool size is paid

            // newScore = (0.8 + (0.0125 * 0.5)) * 0.60653  = 0.48901

            const updatedScore = await scoring.getLastScore(entity.address);
            expect(updatedScore).to.equal(formatScore(0.48901));
        });
    });

    describe("Configuration Updates", function () {
        it("Should update decrease success factor", async function () {
            const newFactor = 70_000;
            await scoring.connect(admin).setDecreaseSuccessFactor(newFactor);
            expect(await scoring.decreaseSuccessFactor()).to.equal(newFactor);
        });

        it("Should update pool size weight", async function () {
            const newWeight = 15_000;
            await scoring.connect(admin).setPoolSizeWeight(newWeight);
            expect(await scoring.poolSizeWeight()).to.equal(newWeight);
        });

        it("Should update threshold capital", async function () {
            const newThreshold = ethers.parseEther("20000");
            await scoring.connect(admin).setThresholdCapital(newThreshold);
            expect(await scoring.thresholdCapital()).to.equal(newThreshold);
        });

        it("Should update threshold collateral", async function () {
            const newThreshold = ethers.parseEther("20000");
            await scoring.connect(admin).setThresholdCollateral(newThreshold);
            expect(await scoring.thresholdCollateral()).to.equal(newThreshold);
        });

        it("Should update market condition ratio", async function () {
            const newRatio = 80_000;
            await scoring.connect(admin).setMarketConditionRatio(newRatio);
            expect(await scoring.marketConditionRatio()).to.equal(newRatio);
        });
    });

    describe("View Functions", function () {
        beforeEach(async () => {
            await createLicense();
            await scoring.connect(admin).setPerformanceData(entity.address, 70_000, 60_000);
        });

        it("Should return correct scores count", async function () {
            expect(await scoring.getScoresCount(entity.address)).to.equal(1);
        });

        it("Should calculate max pool size correctly", async function () {
            const maxPoolSize = await scoring.getMaxPoolSize(entity.address);
            expect(maxPoolSize).to.be.gt(0);
        });

        it("Should check if ready to set initial score", async function () {
            const newEntity = user1.address;
            expect(await scoring.isReadyToSetInitialScore(newEntity)).to.be.false;

            await scoring.connect(admin).setPerformanceData(newEntity, 70_000, 60_000);

            expect(await scoring.isReadyToSetInitialScore(newEntity)).to.be.true;
        });
    });
}); 