import { ethers } from "hardhat";
import { expect } from "chai";
import { 
    VaultFactory, 
    MockERC20, 
    Treasury, 
    License, 
    Scoring,
    Staking,
    Oracle,
    Vault,
    MockRouterV2,
    MockRouterV3,
    MockQuoterV2,
    MockQuadata
} from "../../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { deployAllContracts } from "../utils";
import { APPLICATION_FEE, COLLATERAL_AMOUNT, DEFAULT_VAULT_PARAMS, INITIAL_SUPPLY, LICENSE_MONTHLY_FEE } from "../constants";

describe("GoilVault", function () {
    let vaultFactory: VaultFactory;
    let treasury: Treasury;
    let license: License;
    let scoring: Scoring;
    let staking: Staking;
    let oracle: Oracle;
    let goilToken: MockERC20;
    let depositToken: MockERC20;
    let routerV2: MockRouterV2;
    let routerV3: MockRouterV3;
    let quoter: MockQuoterV2;
    let quadata: MockQuadata;
    let admin: HardhatEthersSigner;
    let manager: HardhatEthersSigner;
    let entity: HardhatEthersSigner;
    let user1: HardhatEthersSigner;
    let user2: HardhatEthersSigner;
    let user3: HardhatEthersSigner;
    let vault: Vault;
    let vaultAddress: string;

    const VAULT_EXPIRY_LIMIT = 2628000; // ~30.42 days
    const MAX_BIPS = 10000n;
    const DEFAULT_STAKING_PERCENTAGE = 100; // 1%
    const INTEREST_RATE = BigInt(DEFAULT_VAULT_PARAMS.rate);
    const DESIRED_CAP = DEFAULT_VAULT_PARAMS.desiredCap;
    const PROMISED_CAP = (DESIRED_CAP * (MAX_BIPS + INTEREST_RATE)) / MAX_BIPS;
    const COLLATERAL_AMOUNT_LICENSE = COLLATERAL_AMOUNT;
    const TOTAL_FEE_FOR_LICENSE = APPLICATION_FEE + LICENSE_MONTHLY_FEE * 12n + COLLATERAL_AMOUNT_LICENSE;

    const setupVault = async (withLicense = false) => {
        // prepare entity to create vault
        if (!withLicense) {
            await goilToken.connect(admin).mint(entity.address, TOTAL_FEE_FOR_LICENSE);
            await goilToken.connect(entity).approve(license.target, TOTAL_FEE_FOR_LICENSE);
            await quadata.connect(entity).mint(entity.address, 1);
            await license.connect(entity).submitLicense(12, COLLATERAL_AMOUNT_LICENSE);
            await license.connect(admin).approveLicense(entity.address, true);

            // setup scoring for entity
            await scoring.connect(admin).setPerformanceData(
                entity.address,
                50_000, // reputation
                50_000  // financial health
            );
        }

        // for collateral at vault creation
        const vaultCollateralAmount = await treasury.getRequiredCollateral(DESIRED_CAP);
        await goilToken.connect(entity).mint(entity.address, vaultCollateralAmount);
        await goilToken.connect(entity).approve(treasury.target, vaultCollateralAmount);

        // define time frames for vault
        const startTime = await time.latest() + 3600; // in 1 hour
        const fundingPeriod = 7 * 24 * 3600; // 7 days
        const lockPeriod = 30 * 24 * 3600; // 30 days

        // create vault
        const tx = await vaultFactory.connect(entity).createVault(
            depositToken.target,
            INTEREST_RATE,
            DESIRED_CAP,
            startTime,
            fundingPeriod,
            lockPeriod
        );

        // get address of created vault
        const receipt = await tx.wait();
        const vaultCreatedEvent = receipt!.logs
            .filter((log) => log.topics[0] === vaultFactory.interface.getEvent("VaultCreated").topicHash)
            .map((log) => vaultFactory.interface.parseLog({ topics: log.topics, data: log.data }))
            .find(Boolean);
        
        vaultAddress = vaultCreatedEvent!.args[0];
        vault = await ethers.getContractAt("Vault", vaultAddress);

        // prepare users to work with vault
        await depositToken.connect(admin).mint(user1.address, DESIRED_CAP);
        await depositToken.connect(admin).mint(user2.address, DESIRED_CAP);
        await depositToken.connect(admin).mint(user3.address, DESIRED_CAP);
        await depositToken.connect(admin).mint(entity.address, PROMISED_CAP);

        await depositToken.connect(user1).approve(vault.target, DESIRED_CAP);
        await depositToken.connect(user2).approve(vault.target, DESIRED_CAP);
        await depositToken.connect(user3).approve(vault.target, DESIRED_CAP);
        await depositToken.connect(entity).approve(vault.target, PROMISED_CAP);
        
        return { vault, startTime, fundingPeriod, lockPeriod };
    };

    beforeEach(async () => {
        const fixture = await loadFixture(deployAllContracts);
        vaultFactory = fixture.vaultFactory;
        treasury = fixture.treasury;
        license = fixture.license;
        scoring = fixture.scoring;
        staking = fixture.staking;
        oracle = fixture.oracle;
        goilToken = fixture.goilToken;
        depositToken = fixture.stableToken;
        routerV2 = fixture.mockRouterV2;
        routerV3 = fixture.mockRouterV3;
        quoter = fixture.mockQuoter;
        quadata = fixture.quadata;
        admin = fixture.admin;
        manager = fixture.admin;
        entity = fixture.entity;
        user1 = fixture.user1;
        user2 = fixture.user2;
        user3 = fixture.user3;
    });

    describe("Deployment Functionality", function () {
        it("Should correctly initialize vault with all parameters", async function () {
            const { vault, startTime, fundingPeriod, lockPeriod } = await setupVault();
            
            // check initialization
            expect(await vault.ENTITY()).to.equal(entity.address);
            expect(await vault.SCORING()).to.equal(scoring.target);
            expect(await vault.TREASURY()).to.equal(treasury.target);
            expect(await vault.STAKING()).to.equal(staking.target);
            expect(await vault.GOIL_TOKEN()).to.equal(goilToken.target);
            expect(await vault.DEPOSIT_TOKEN()).to.equal(depositToken.target);
            
            expect(await vault.desiredCap()).to.equal(DESIRED_CAP);
            expect(await vault.promisedCap()).to.equal(PROMISED_CAP);
            expect(await vault.startTime()).to.equal(startTime);
            expect(await vault.fundingEndTime()).to.equal(startTime + fundingPeriod);
            expect(await vault.unlockEndTime()).to.equal(startTime + fundingPeriod + lockPeriod);
            
            expect(await vault.isVaultSuccess()).to.be.false;
            expect(await vault.isVaultLiquidated()).to.be.false;
        });
        
        it("Should correctly determine vault state", async function () {
            const { vault, startTime } = await setupVault();
            
            // state before start
            expect(await vault.getVaultState()).to.equal(0); // NOT_STARTED
            
            // go to start time
            await time.increaseTo(startTime + 100);
            expect(await vault.getVaultState()).to.equal(1); // FUNDING
            
            // go after funding period (but no funds collected)
            await time.increaseTo((await vault.fundingEndTime()) + 100n);
            expect(await vault.getVaultState()).to.equal(2); // NOT_RAISED
        });
        
        it("Should show correct promised and unpaid amount", async function () {
            const { vault } = await setupVault();
            
            const [promisedAmount, unpaidAmount] = await vault.getPromisedAndUnpaidAmount();
            expect(promisedAmount).to.equal(PROMISED_CAP);
            expect(unpaidAmount).to.equal(PROMISED_CAP); // since nothing was deposited
        });
    });

    describe("Deposit Functionality", function () {
        it("Users cannot deposit before funding period", async function () {
            const { vault } = await setupVault();
            
            await expect(vault.connect(user1)["deposit(uint256)"](1000))
                .to.be.revertedWithCustomError(vault, "VaultNotStarted");
        });
        
        it("Users can deposit during funding period", async function () {
            const { vault, startTime } = await setupVault();
            
            // go to funding period
            await time.increaseTo(startTime + 100);
            
            const depositAmount = ethers.parseUnits("1000", 18);
            await vault.connect(user1)["deposit(uint256)"](depositAmount);
            
            expect(await vault.balanceOf(user1.address)).to.be.greaterThan(0);
            expect(await vault.totalDepositsFromUsers()).to.equal(depositAmount);
        });
        
        it("Users cannot deposit more than desiredCap", async function () {
            const { vault, startTime } = await setupVault();
            
            // go to funding period
            await time.increaseTo(startTime + 100);
            
            // user tries to deposit more than desiredCap
            await expect(vault.connect(user1)["deposit(uint256)"](DESIRED_CAP + 1n))
                .to.be.revertedWithCustomError(vault, "ExceedsVaultSize");
        });
        
        it("Users cannot deposit after funding period", async function () {
            const { vault, startTime } = await setupVault();
            
            // go after funding period
            await time.increaseTo((await vault.fundingEndTime()) + 100n);
            
            await expect(vault.connect(user1)["deposit(uint256)"](1000))
                .to.be.revertedWithCustomError(vault, "VaultFundingTimeIsEnded");
        });
        
        it("Entity cannot deposit before funding period", async function () {
            const { vault, startTime } = await setupVault();
            
            // go to funding period
            await time.increaseTo(startTime + 100);
            
            await expect(vault.connect(entity).depositFromEntity(1000))
                .to.be.revertedWithCustomError(vault, "FundingEndTimeIsNotReached");
        });
    });

    describe("Withdrawal Functionality", function () {
        it("Users can withdraw if desiredCap is not collected", async function () {
            const { vault, startTime } = await setupVault();
            
            // go to funding period
            await time.increaseTo(startTime + 100);
            
            // user deposits
            const depositAmount = ethers.parseUnits("1000", 18);
            await vault.connect(user1)["deposit(uint256)"](depositAmount);
            
            // go after funding period
            await time.increaseTo((await vault.fundingEndTime()) + 100n);
            
            // check that desiredCap is not collected
            expect(await vault.isNotRaisedDesiredCap()).to.be.true;
            
            // user withdraws
            const withdrawAmount = await vault.maxWithdraw(user1.address);
            await vault.connect(user1)["withdraw(uint256)"](withdrawAmount);
            
            expect(await depositToken.balanceOf(user1.address)).to.equal(DESIRED_CAP);
            expect(await vault.balanceOf(user1.address)).to.equal(0);
        });
        
        it("Entity cannot withdraw if desiredCap is not collected", async function () {
            const { vault, startTime } = await setupVault();
            
            // go to funding period
            await time.increaseTo(startTime + 100);
            
            // user deposits, but less than desiredCap
            const depositAmount = ethers.parseUnits("1000", 18);
            await vault.connect(user1)["deposit(uint256)"](depositAmount);
            
            // go after funding period
            await time.increaseTo((await vault.fundingEndTime()) + 100n);
            
            // entity tries to withdraw
            await expect(vault.connect(entity).withdrawToEntity())
                .to.be.revertedWithCustomError(vault, "InsufficientBalance");
        });
        
        it("Users cannot withdraw before unlocking", async function () {
            const { vault, startTime } = await setupVault();
            
            // go to funding period
            await time.increaseTo(startTime + 100);
            
            // users deposit to reach desiredCap
            await vault.connect(user1)["deposit(uint256)"](DESIRED_CAP / 2n);
            await vault.connect(user2)["deposit(uint256)"](DESIRED_CAP / 2n);
            
            // go after funding period
            await time.increaseTo((await vault.fundingEndTime()) + 100n);
            
            // user tries to withdraw before unlocking
            await expect(vault.connect(user1)["withdraw(uint256)"](1))
                .to.be.revertedWithCustomError(vault, "VaultIsNotUnlocked");
        });
    });

    describe("Scenario 1: Insufficient funds collection", function () {
        it("Users can withdraw if desiredCap is not reached", async function () {
            const { vault, startTime } = await setupVault();
            
            // go to funding period
            await time.increaseTo(startTime + 100);
            
            // users deposit, but less than desiredCap
            await vault.connect(user1)["deposit(uint256)"](DESIRED_CAP / 4n);
            await vault.connect(user2)["deposit(uint256)"](DESIRED_CAP / 4n);
            
            // go after funding period
            await time.increaseTo((await vault.fundingEndTime()) + 100n);
            
            // check vault state
            expect(await vault.getVaultState()).to.equal(2); // NOT_RAISED
            
            // users withdraw
            const withdrawAmountUser1 = await vault.balanceOf(user1.address);
            const withdrawAmountUser2 = await vault.balanceOf(user2.address);
            
            const user1DepositBefore = await depositToken.balanceOf(user1.address);
            await vault.connect(user1)["withdraw(uint256)"](withdrawAmountUser1);
            const user1DepositAfter = await depositToken.balanceOf(user1.address);
            
            const user2DepositBefore = await depositToken.balanceOf(user2.address);
            await vault.connect(user2)["withdraw(uint256)"](withdrawAmountUser2);
            const user2DepositAfter = await depositToken.balanceOf(user2.address);
            
            // check that users received their funds back
            expect(user1DepositAfter - user1DepositBefore).to.equal(DESIRED_CAP / 4n);
            expect(user2DepositAfter - user2DepositBefore).to.equal(DESIRED_CAP / 4n);
        });
        
        it("Entity cannot withdraw if desiredCap is not reached", async function () {
            const { vault, startTime } = await setupVault();
            
            // go to funding period
            await time.increaseTo(startTime + 100);
            
            // users deposit, but less than desiredCap
            await vault.connect(user1)["deposit(uint256)"](DESIRED_CAP / 4n);
            await vault.connect(user2)["deposit(uint256)"](DESIRED_CAP / 4n);
            
            // go after funding period
            await time.increaseTo((await vault.fundingEndTime()) + 100n);
            
            // entity tries to withdraw
            await expect(vault.connect(entity).withdrawToEntity())
                .to.be.revertedWithCustomError(vault, "InsufficientBalance");
        });
    });

    describe("Scenario 2: Entity does not return funds after withdrawal", function () {
        it("Vault is liquidated if entity does not return funds by the end of the period", async function () {
            const { vault, startTime } = await setupVault();
            
            // go to funding period
            await time.increaseTo(startTime + 100);
            
            // users deposit to reach desiredCap
            await vault.connect(user1)["deposit(uint256)"](DESIRED_CAP / 2n);
            await vault.connect(user2)["deposit(uint256)"](DESIRED_CAP / 2n);
            
            // go after funding period
            await time.increaseTo((await vault.fundingEndTime()) + 100n);
            
            // entity withdraws
            await vault.connect(entity).withdrawToEntity();
            
            // go after unlocking period
            await time.increaseTo((await vault.unlockEndTime()) + 100n);
            
            // check that vault can be liquidated
            expect(await vault.isLiquidatable()).to.be.true;
            
            // monitor GOIL balance in treasury before liquidation
            const treasuryGoilBefore = await goilToken.balanceOf(treasury.target);
            
            const refundableAmount = await vault.refundableAmount();

            // vault is liquidated when user tries to withdraw
            const amountToWithdraw = DESIRED_CAP / 2n; // since 1:1 1$ = 1 goil
            await expect(vault.connect(user1)["withdraw(uint256)"](amountToWithdraw))
                .to.emit(vault, "Withdraw")
                .to.emit(scoring, "EntityScoreUpdated");
            
            // check that vault is liquidated
            expect(await vault.isVaultLiquidated()).to.be.true;
            
            // check that users receive GOIL tokens
            expect(await goilToken.balanceOf(user1.address)).to.be.equal(amountToWithdraw);
            
            // check that treasury received GOIL
            expect(await goilToken.balanceOf(treasury.target)).to.be.equal(treasuryGoilBefore - refundableAmount);
        });
        
        it("Entity score decreases when vault is liquidated without returning funds", async function () {
            const { vault, startTime } = await setupVault();
            
            // get initial entity score
            const initialScore = await scoring.getLastScore(entity.address);
            
            // go to funding period
            await time.increaseTo(startTime + 100);
            
            // users deposit to reach desiredCap
            await vault.connect(user1)["deposit(uint256)"](DESIRED_CAP / 2n);
            await vault.connect(user2)["deposit(uint256)"](DESIRED_CAP / 2n);
            
            // go after funding period
            await time.increaseTo((await vault.fundingEndTime()) + 100n);
            
            // entity withdraws
            await vault.connect(entity).withdrawToEntity();
            
            // go after unlocking period
            await time.increaseTo((await vault.unlockEndTime()) + 100n);
            
            // liquidate vault
            await vault.connect(user1).liquidate();
            
            // check that entity score decreased
            const finalScore = await scoring.getLastScore(entity.address);
            expect(finalScore).to.be.lessThan(initialScore);
        });
    });

    describe("Scenario 3: Entity returns partial funds (50-80%)", function () {
        it("Vault is liquidated and users receive GOIL tokens if entity returns partial funds", async function () {
            const { vault, startTime } = await setupVault();
            
            // go to funding period
            await time.increaseTo(startTime + 100);
            
            // users deposit to reach desiredCap
            await vault.connect(user1)["deposit(uint256)"](DESIRED_CAP / 2n);
            await vault.connect(user2)["deposit(uint256)"](DESIRED_CAP / 2n);
            
            // go after funding period
            await time.increaseTo((await vault.fundingEndTime()) + 100n);
            
            // entity withdraws
            await vault.connect(entity).withdrawToEntity();
            
            // go after unlocking period
            await time.increaseTo((await vault.unlockEndTime()) + 100n);
            
            // entity returns partial funds (70%)
            const returnAmount = DESIRED_CAP * 70n / 100n;
            await vault.connect(entity).depositFromEntity(returnAmount);
            
            // monitor GOIL balance in treasury before liquidation
            const treasuryGoilBefore = await goilToken.balanceOf(treasury.target);
            const refundableAmount = await vault.refundableAmount();

            // liquidate vault
            await vault.connect(user1).liquidate();

            // check that vault is liquidated
            expect(await vault.isVaultLiquidated()).to.be.true;
            
            // check that users receive GOIL tokens
            const withdrawAmountUser1 = await vault.maxWithdraw(user1.address);
            const withdrawAmountUser2 = await vault.maxWithdraw(user2.address);

            await vault.connect(user1)["withdraw(uint256)"](withdrawAmountUser1);
            await vault.connect(user2)["withdraw(uint256)"](withdrawAmountUser2);

            expect(await goilToken.balanceOf(user1.address)).to.be.eq(withdrawAmountUser1);
            expect(await goilToken.balanceOf(user2.address)).to.be.eq(withdrawAmountUser2);
            
            // check that treasury received GOIL after swap & sent to vault
            expect(await goilToken.balanceOf(treasury.target)).to.be.greaterThan(treasuryGoilBefore - refundableAmount);
            expect(await goilToken.balanceOf(treasury.target)).to.be.lessThan(treasuryGoilBefore);
        });
        
        it("Entity score decreases less if partial funds are returned", async function () {
            const { vault, startTime } = await setupVault();
            
            // get initial entity score
            const initialScore = await scoring.getLastScore(entity.address);
            
            // go to funding period
            await time.increaseTo(startTime + 100);
            
            // users deposit to reach desiredCap
            await vault.connect(user1)["deposit(uint256)"](DESIRED_CAP);
            
            // go after funding period
            await time.increaseTo((await vault.fundingEndTime()) + 100n);
            
            // entity withdraws & returns partial funds
            await vault.connect(entity).withdrawToEntity();
            await vault.connect(entity).depositFromEntity(DESIRED_CAP * 70n / 100n);

            // go after unlocking period
            await time.increaseTo((await vault.unlockEndTime()) + 100n);
            
            await vault.connect(user1).liquidate();
            const scoreAfterLiquidation = await scoring.getLastScore(entity.address);
            
            // check that entity score decreased less in case of partial return
            expect(scoreAfterLiquidation).to.be.lessThan(initialScore);
        });
    });

    describe("Scenario 4: Entity returns more than borrowed, but less than promised", function () {
        it("Vault is liquidated and users receive stable tokens if entity returns more than borrowed, but less than promised", async function () {
            const { vault, startTime } = await setupVault();
            
            // go to funding period
            await time.increaseTo(startTime + 100);
            
            // users deposit to reach desiredCap
            await vault.connect(user1)["deposit(uint256)"](DESIRED_CAP / 2n);
            await vault.connect(user2)["deposit(uint256)"](DESIRED_CAP / 2n);
            
            // go after funding period
            await time.increaseTo((await vault.fundingEndTime()) + 100n);
            
            // entity withdraws
            await vault.connect(entity).withdrawToEntity();
            
            // go after unlocking period
            await time.increaseTo((await vault.unlockEndTime()) + 100n);
            
            // entity returns more than borrowed, but less than promised (105%)
            const returnAmount = DESIRED_CAP * 105n / 100n;
            await vault.connect(entity).depositFromEntity(returnAmount);
            
            // check that vault has stable tokens
            expect(await depositToken.balanceOf(vault.target)).to.equal(returnAmount);
            
            // liquidate vault
            await vault.connect(user1).liquidate();
            
            // check that vault is liquidated
            expect(await vault.isVaultLiquidated()).to.be.true;
            
            // users withdraw stable tokens
            const user1WithdrawAmount = await vault.maxWithdraw(user1.address);
            const user2WithdrawAmount = await vault.maxWithdraw(user2.address);
            const user1DepositBefore = await depositToken.balanceOf(user1.address);
            const user2DepositBefore = await depositToken.balanceOf(user2.address);
            
            await vault.connect(user1)["withdraw(uint256)"](user1WithdrawAmount);
            await vault.connect(user2)["withdraw(uint256)"](user2WithdrawAmount);

            // check that users receive deposit tokens, not GOIL
            const user1DepositAfter = await depositToken.balanceOf(user1.address);
            const user2DepositAfter = await depositToken.balanceOf(user2.address);

            expect(user1DepositAfter).to.be.greaterThan(user1DepositBefore);
            expect(user2DepositAfter).to.be.greaterThan(user2DepositBefore);
            expect(await goilToken.balanceOf(user1.address)).to.equal(0);
            expect(await goilToken.balanceOf(user2.address)).to.equal(0);
        });
        
        it("Entity score decreases less if more than borrowed is returned but less than promised", async function () {
            const { vault, startTime } = await setupVault();
            
            // get initial entity score
            const initialScore = await scoring.getLastScore(entity.address);
            
            // go to funding period
            await time.increaseTo(startTime + 100);
            
            // users deposit to reach desiredCap
            await vault.connect(user1)["deposit(uint256)"](DESIRED_CAP);
            
            // go after funding period
            await time.increaseTo((await vault.fundingEndTime()) + 100n);
            
            // entity withdraws
            await vault.connect(entity).withdrawToEntity();
            
            // go after unlocking period
            await time.increaseTo((await vault.unlockEndTime()) + 100n);
            
            // entity returns more than borrowed, but less than promised (110%)
            const returnAmount = DESIRED_CAP * 110n / 100n;
            await vault.connect(entity).depositFromEntity(returnAmount);
            
            // liquidate vault
            await vault.connect(user1).liquidate();
            const scoreAfterLiquidation = await scoring.getLastScore(entity.address);
            
            // check that entity score decreased less in case of partial return
            expect(scoreAfterLiquidation).to.be.lessThan(initialScore);
        });
    });

    describe("Scenario 5: Entity returns promised amount", function () {
        it("Vault is successfully closed if entity returns promised amount", async function () {
            const { vault, startTime } = await setupVault();
            const initialScore = await scoring.getLastScore(entity.address);

            // go to funding period
            await time.increaseTo(startTime + 100);
            
            // users deposit to reach desiredCap
            await vault.connect(user1)["deposit(uint256)"](DESIRED_CAP / 2n);
            await vault.connect(user2)["deposit(uint256)"](DESIRED_CAP / 2n);
            
            // go after funding period
            await time.increaseTo((await vault.fundingEndTime()) + 100n);
            
            // entity withdraws
            await vault.connect(entity).withdrawToEntity();
            
            // go after unlocking period
            await time.increaseTo((await vault.unlockEndTime()) + 100n);
            
            // entity returns promised amount
            await vault.connect(entity).depositFromEntity(PROMISED_CAP);
            
            // check that vault is successful
            expect(await vault.isVaultSuccess()).to.be.true;
            expect(await vault.isVaultLiquidated()).to.be.false;
            
            // check that vault state is SUCCESS
            expect(await vault.getVaultState()).to.equal(4); // SUCCESS
            
            // check that staking received GOIL tokens
            expect(await goilToken.balanceOf(staking.target)).to.be.greaterThan(0);
            
            // check that entity score increased
            const finalScore = await scoring.getLastScore(entity.address);
            expect(finalScore).to.be.greaterThan(initialScore);
        });
        
        it("Users can withdraw their funds with interest after successful vault closure", async function () {
            const { vault, startTime } = await setupVault();
            
            // go to funding period
            await time.increaseTo(startTime + 100);
            
            // users deposit to reach desiredCap
            await vault.connect(user1)["deposit(uint256)"](DESIRED_CAP / 2n);
            await vault.connect(user2)["deposit(uint256)"](DESIRED_CAP / 2n);
            
            // go after funding period
            await time.increaseTo((await vault.fundingEndTime()) + 100n);
            
            // entity withdraws
            await vault.connect(entity).withdrawToEntity();
            
            // entity returns promised amount
            await vault.connect(entity).depositFromEntity(PROMISED_CAP);
            
            // users withdraw their funds with interest
            const user1WithdrawAmount = await vault.maxWithdraw(user1.address);
            const user2WithdrawAmount = await vault.maxWithdraw(user2.address);
            const user1DepositBefore = await depositToken.balanceOf(user1.address);
            const user2DepositBefore = await depositToken.balanceOf(user2.address);

            await vault.connect(user1)["withdraw(uint256)"](user1WithdrawAmount);
            await vault.connect(user2)["withdraw(uint256)"](user2WithdrawAmount);

            expect(await depositToken.balanceOf(user1.address)).to.be.eq(user1DepositBefore + user1WithdrawAmount);
            expect(await depositToken.balanceOf(user2.address)).to.be.eq(user2DepositBefore + user2WithdrawAmount);
        });
    });

    describe("Scenario 6: Entity deposit after liquidation", function () {
        it("When entity deposits after liquidation, funds are converted to GOIL and sent to treasury", async function () {
            const { vault, startTime } = await setupVault();
            
            // Move to funding period
            await time.increaseTo(startTime + 100);
            
            // Users deposit to reach desiredCap
            await vault.connect(user1)["deposit(uint256)"](DESIRED_CAP / 2n);
            await vault.connect(user2)["deposit(uint256)"](DESIRED_CAP / 2n);
            
            // Move to funding period
            await time.increaseTo((await vault.fundingEndTime()) + 100n);
            
            // Entity withdraws
            await vault.connect(entity).withdrawToEntity();
            
            // Move to unlocking period
            await time.increaseTo((await vault.unlockEndTime()) + 100n);
            
            // Liquidate vault
            await vault.connect(user1).liquidate();
            
            // Check that vault is liquidated
            expect(await vault.isVaultLiquidated()).to.be.true;
            
            // Save treasury balance before entity deposit
            const treasuryGoilBefore = await goilToken.balanceOf(treasury.target);
            
            // Entity deposits after liquidation
            const depositAmount = DESIRED_CAP / 2n;
            await vault.connect(entity).depositFromEntity(depositAmount);
            
            // Check that funds were converted to GOIL and sent to treasury
            const treasuryGoilAfter = await goilToken.balanceOf(treasury.target);
            expect(treasuryGoilAfter).to.be.eq(treasuryGoilBefore + depositAmount); // 1$ = 1 GOIL
            
            // Check that vault has no deposit tokens
            expect(await depositToken.balanceOf(vault.target)).to.equal(0);
        });
        
        it("Entity score is updated proportionally if deposit after liquidation is less than promisedCap", async function () {
            const { vault, startTime } = await setupVault();
            
            // Move to funding period
            await time.increaseTo(startTime + 100);
            
            // Users deposit to reach desiredCap
            await vault.connect(user1)["deposit(uint256)"](DESIRED_CAP);
            
            // Move to funding period
            await time.increaseTo((await vault.fundingEndTime()) + 100n);
            
            // Entity withdraws
            await vault.connect(entity).withdrawToEntity();
            
            // Move to unlocking period
            await time.increaseTo((await vault.unlockEndTime()) + 100n);
            
            // Get initial entity score
            const initialScore = await scoring.getLastScore(entity.address);
            
            // Liquidate vault
            await vault.connect(user1).liquidate();
            
            // Get entity score after liquidation
            const scoreAfterLiquidation = await scoring.getLastScore(entity.address);
            expect(scoreAfterLiquidation).to.be.lessThan(initialScore);
            
            // Entity deposits after liquidation, but less than promisedCap
            const depositAmount = PROMISED_CAP / 2n;
            await vault.connect(entity).depositFromEntity(depositAmount);
            
            // Check that entity score increased after deposit
            const scoreAfterDeposit = await scoring.getLastScore(entity.address);
            expect(scoreAfterDeposit).to.be.greaterThan(scoreAfterLiquidation);
            expect(scoreAfterDeposit).to.be.lessThan(initialScore); // But still less than initial score
        });
        
        it("Entity score is not updated if total deposits already reached promisedCap", async function () {
            const { vault, startTime } = await setupVault();
            
            // Move to funding period
            await time.increaseTo(startTime + 100);
            
            // Users deposit to reach desiredCap
            await vault.connect(user1)["deposit(uint256)"](DESIRED_CAP);
            
            // Move to funding period
            await time.increaseTo((await vault.fundingEndTime()) + 100n);
            
            // Entity withdraws
            await vault.connect(entity).withdrawToEntity();
            
            // Move to unlocking period
            await time.increaseTo((await vault.unlockEndTime()) + 100n);
            
            // Liquidate vault
            await vault.connect(user1).liquidate();
            
            // Entity first deposits promisedCap
            await depositToken.connect(entity).mint(entity.address, PROMISED_CAP * 2n);
            await depositToken.connect(entity).approve(vault.target, PROMISED_CAP * 2n);
            await vault.connect(entity).depositFromEntity(PROMISED_CAP);
            
            // Get entity score after first deposit
            const scoreAfterFirstDeposit = await scoring.getLastScore(entity.address);
            
            // Entity deposits again
            await vault.connect(entity).depositFromEntity(DESIRED_CAP);
            
            // Check that entity score did not change after second deposit
            const scoreAfterSecondDeposit = await scoring.getLastScore(entity.address);
            expect(scoreAfterSecondDeposit).to.equal(scoreAfterFirstDeposit);
        });
    });

    describe("View functions and utility functions", function () {
        it("isLiquidatable correctly determines if vault can be liquidated", async function () {
            const { vault, startTime } = await setupVault();
            
            // At the beginning, the vault cannot be liquidated
            expect(await vault.isLiquidatable()).to.be.false;
            
            // Move to funding period
            await time.increaseTo(startTime + 100);
            await vault.connect(user1)["deposit(uint256)"](DESIRED_CAP);
            await time.increaseTo((await vault.fundingEndTime()) + 100n);
            await vault.connect(entity).withdrawToEntity();
            
            // After entity withdraws, the vault cannot be liquidated
            expect(await vault.isLiquidatable()).to.be.false;
            
            // Move to unlocking period
            await time.increaseTo((await vault.unlockEndTime()) + 100n);
            
            // Now the vault can be liquidated, because the entity did not return the funds
            expect(await vault.isLiquidatable()).to.be.true;
            
            // Entity returns the full promised amount
            await vault.connect(entity).depositFromEntity(PROMISED_CAP);
            
            // After returning the promised amount, the vault cannot be liquidated
            expect(await vault.isLiquidatable()).to.be.false;
        });
        
        it("isNotRaisedDesiredCap correctly determines if desiredCap was not raised", async function () {
            const { vault, startTime } = await setupVault();
            
            // At the beginning, desiredCap was not raised
            expect(await vault.isNotRaisedDesiredCap()).to.be.false;
            
            // Move to funding period
            await time.increaseTo(startTime + 100);
            
            // Users deposit, but not enough for desiredCap
            await vault.connect(user1)["deposit(uint256)"](DESIRED_CAP / 4n);
            
            // Move to funding period
            await time.increaseTo((await vault.fundingEndTime()) + 100n);
            
            // DesiredCap was not raised
            expect(await vault.isNotRaisedDesiredCap()).to.be.true;
            
            // Create another vault
            const { vault: vault2, startTime: startTime2 } = await setupVault(true);
            
            // Move to funding period
            await time.increaseTo(startTime2 + 100);
            
            // Users deposit to reach desiredCap
            await vault2.connect(user1)["deposit(uint256)"](DESIRED_CAP);
            
            // Move to funding period
            await time.increaseTo((await vault2.fundingEndTime()) + 100n);
            
            // DesiredCap was raised
            expect(await vault2.isNotRaisedDesiredCap()).to.be.false;
        });
    });

    describe("Liquidation functions", function () {
        it("Users can call liquidation if vault is liquidatable", async function () {
            const { vault, startTime } = await setupVault();
            
            // Move to funding period
            await time.increaseTo(startTime + 100);
            
            // Users deposit to reach desiredCap
            await vault.connect(user1)["deposit(uint256)"](DESIRED_CAP);
            
            // Move to funding period
            await time.increaseTo((await vault.fundingEndTime()) + 100n);
            
            // Entity withdraws
            await vault.connect(entity).withdrawToEntity();
            
            // Move to unlocking period
            await time.increaseTo((await vault.unlockEndTime()) + 100n);
            
            // User calls liquidation
            await expect(vault.connect(user1).liquidate())
                .to.emit(scoring, "EntityScoreUpdated"); // Emits EntityScoreUpdated event when entity score is updated
            
            // Check that vault is liquidated
            expect(await vault.isVaultLiquidated()).to.be.true;
        });
        
        it("Liquidation is automatically called when a user tries to withdraw, if vault is liquidatable", async function () {
            const { vault, startTime } = await setupVault();
            
            // Move to funding period
            await time.increaseTo(startTime + 100);
            
            // Users deposit to reach desiredCap
            await vault.connect(user1)["deposit(uint256)"](DESIRED_CAP / 2n);
            await vault.connect(user2)["deposit(uint256)"](DESIRED_CAP / 2n);
            
            // Move to funding period
            await time.increaseTo((await vault.fundingEndTime()) + 100n);
            
            // Entity withdraws
            await vault.connect(entity).withdrawToEntity();
            
            // Move to unlocking period
            await time.increaseTo((await vault.unlockEndTime()) + 100n);
            
            // User tries to withdraw, which automatically triggers liquidation
            await expect(vault.connect(user1)["withdraw(uint256)"](1))
                .to.emit(scoring, "EntityScoreUpdated"); // Emits EntityScoreUpdated event when entity score is updated
            
            // Check that vault is liquidated
            expect(await vault.isVaultLiquidated()).to.be.true;
        });
        
        it("Users cannot call liquidation if vault is not liquidatable", async function () {
            const { vault, startTime } = await setupVault();
            
            // Move to funding period
            await time.increaseTo(startTime + 100);
            
            // Users deposit to reach desiredCap
            await vault.connect(user1)["deposit(uint256)"](DESIRED_CAP);
            
            // Move to funding period
            await time.increaseTo((await vault.fundingEndTime()) + 100n);
            
            // Entity withdraws
            await vault.connect(entity).withdrawToEntity();
            
            // Vault is not liquidatable yet, because the unlocking period has not ended
            await expect(vault.connect(user1).liquidate())
                .to.be.revertedWithCustomError(vault, "VaultIsNotLiquidatable");
        });
    });
});