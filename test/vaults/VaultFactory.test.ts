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

describe("VaultFactory", function () {
    let vaultFactory: VaultFactory;
    let treasury: Treasury;
    let license: License;
    let scoring: Scoring;
    let staking: Staking;
    let oracle: Oracle;
    let goilToken: MockERC20;
    let depositToken: MockERC20;
    let depositToken2: MockERC20;
    let routerV2: MockRouterV2;
    let routerV3: MockRouterV3;
    let quoter: MockQuoterV2;
    let quadata: MockQuadata;
    let admin: HardhatEthersSigner;
    let manager: HardhatEthersSigner;
    let entity: HardhatEthersSigner;
    let user: HardhatEthersSigner;
    let user2: HardhatEthersSigner;
    let vaultImplementation: string;

    const VAULT_EXPIRY_LIMIT = 2628000; // ~30.42 days
    const MAX_BIPS = 10000;
    const DEFAULT_STAKING_PERCENTAGE = 100; // 1%
    const INTEREST_RATE = DEFAULT_VAULT_PARAMS.rate;
    const DESIRED_CAP = DEFAULT_VAULT_PARAMS.desiredCap;
    const COLLATERAL_AMOUNT_LICENSE = COLLATERAL_AMOUNT;
    
    const TOTAL_FEE_FOR_LICENSE = APPLICATION_FEE + LICENSE_MONTHLY_FEE * 12n + COLLATERAL_AMOUNT_LICENSE;

    // Function to prepare entity for vault creation
    const prepareToCreateVault = async () => {
        // Setting up license for entity
        await goilToken.connect(admin).mint(entity.address, TOTAL_FEE_FOR_LICENSE);
        await goilToken.connect(entity).approve(license.target, TOTAL_FEE_FOR_LICENSE);
        await quadata.connect(entity).mint(entity.address, 1);
        await license.connect(entity).submitLicense(12, COLLATERAL_AMOUNT_LICENSE);
        await license.connect(admin).approveLicense(entity.address, true);
        
        // Setting up scoring for entity
        await scoring.connect(admin).setPerformanceData(
            entity.address,
            50_000, // reputation
            50_000  // financial health
        );

        // for creating vault collateral
        const vaultCollateralAmount = await treasury.getRequiredCollateral(DESIRED_CAP);
        await goilToken.connect(entity).mint(entity.address, vaultCollateralAmount);
        await goilToken.connect(entity).approve(treasury.target, vaultCollateralAmount);
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
        depositToken2 = fixture.stableToken2;
        routerV2 = fixture.mockRouterV2;
        routerV3 = fixture.mockRouterV3;
        quoter = fixture.mockQuoter;
        quadata = fixture.quadata;
        admin = fixture.admin;
        manager = fixture.admin;
        entity = fixture.entity;
        user = fixture.user1;
        user2 = fixture.user2;
        
        // Getting the vault implementation address
        vaultImplementation = await vaultFactory.VAULT_IMPLEMENTATION();
    });

    describe("Deployment Functionality", function () {
        it("Should correctly set initial values", async function () {
            expect(await vaultFactory.VAULT_EXPIRY_LIMIT_AFTER_LICENSE()).to.equal(VAULT_EXPIRY_LIMIT);
            expect(await vaultFactory.ORACLE()).to.equal(oracle.target);
            expect(await vaultFactory.GOIL_TOKEN()).to.equal(goilToken.target);
            expect(await vaultFactory.ROUTER_V2()).to.equal(routerV2.target);
            expect(await vaultFactory.ROUTER_V3()).to.equal(routerV3.target);
            expect(await vaultFactory.QUOTER()).to.equal(quoter.target);
            expect(await vaultFactory.stakingPercentage()).to.equal(DEFAULT_STAKING_PERCENTAGE);
            expect(await vaultFactory.MAX_BIPS()).to.equal(MAX_BIPS);
            
            // Check if the vault implementation is a contract`
            const code = await ethers.provider.getCode(vaultImplementation);
            expect(code).not.to.equal("0x");
        });

        it("Should correctly set deposit tokens", async function () {
            expect(await vaultFactory.isDepositToken(depositToken.target)).to.be.true;
            expect(await vaultFactory.getDepositTokensCount()).to.equal(1);
            const depositTokens = await vaultFactory.getDepositTokens();
            expect(depositTokens[0]).to.equal(depositToken.target);
        });

        it("Should prevent deployment with zero admin address", async function () {
            const VaultFactoryFactory = await ethers.getContractFactory("VaultFactory");
            await expect(
                VaultFactoryFactory.deploy(
                    ethers.ZeroAddress,
                    goilToken.target,
                    oracle.target,
                    routerV2.target,
                    routerV3.target,
                    quoter.target,
                    [depositToken.target]
                )
            ).to.be.revertedWithCustomError(vaultFactory, "AdminCannotBeZeroAddress");
        });

        it("Should prevent deployment with non-contract oracle", async function () {
            const VaultFactoryFactory = await ethers.getContractFactory("VaultFactory");
            await expect(
                VaultFactoryFactory.deploy(
                    admin.address,
                    goilToken.target,
                    user.address, // not a contract
                    routerV2.target,
                    routerV3.target,
                    quoter.target,
                    [depositToken.target]
                )
            ).to.be.revertedWithCustomError(VaultFactoryFactory, "OracleMustBeContract");
        });

        it("Should prevent deployment with non-contract goilToken", async function () {
            const VaultFactoryFactory = await ethers.getContractFactory("VaultFactory");
            await expect(
                VaultFactoryFactory.deploy(
                    admin.address,
                    user.address, // not a contract
                    oracle.target,
                    routerV2.target,
                    routerV3.target,
                    quoter.target,
                    [depositToken.target]
                )
            ).to.be.revertedWithCustomError(VaultFactoryFactory, "GoilTokenMustBeContract");
        });

        it("Should prevent deployment with non-contract routerV2", async function () {
            const VaultFactoryFactory = await ethers.getContractFactory("VaultFactory");
            await expect(
                VaultFactoryFactory.deploy(
                    admin.address,
                    goilToken.target,
                    oracle.target,
                    user.address, // not a contract
                    routerV3.target,
                    quoter.target,
                    [depositToken.target]
                )
            ).to.be.revertedWithCustomError(VaultFactoryFactory, "RouterV2MustBeContract");
        });

        it("Should prevent deployment with non-contract routerV3", async function () {
            const VaultFactoryFactory = await ethers.getContractFactory("VaultFactory");
            await expect(
                VaultFactoryFactory.deploy(
                    admin.address,
                    goilToken.target,
                    oracle.target,
                    routerV2.target,
                    user.address, // not a contract
                    quoter.target,
                    [depositToken.target]
                )
            ).to.be.revertedWithCustomError(VaultFactoryFactory, "RouterV3MustBeContract");
        });

        it("Should prevent deployment with non-contract quoter", async function () {
            const VaultFactoryFactory = await ethers.getContractFactory("VaultFactory");
            await expect(
                VaultFactoryFactory.deploy(
                    admin.address,
                    goilToken.target,
                    oracle.target,
                    routerV2.target,
                    routerV3.target,
                    user.address, // not a contract
                    [depositToken.target]
                )
            ).to.be.revertedWithCustomError(VaultFactoryFactory, "QuoterMustBeContract");
        });

        it("Should prevent deployment with zero deposit tokens", async function () {
            const VaultFactoryFactory = await ethers.getContractFactory("VaultFactory");
            await expect(
                VaultFactoryFactory.deploy(
                    admin.address,
                    goilToken.target,
                    oracle.target,
                    routerV2.target,
                    routerV3.target,
                    quoter.target,
                    [] // empty array
                )
            ).to.be.revertedWithCustomError(VaultFactoryFactory, "DepositTokensLengthCannotBeZero");
        });

        it("Should prevent deployment with non-contract deposit token", async function () {
            const VaultFactoryFactory = await ethers.getContractFactory("VaultFactory");
            await expect(
                VaultFactoryFactory.deploy(
                    admin.address,
                    goilToken.target,
                    oracle.target,
                    routerV2.target,
                    routerV3.target,
                    quoter.target,
                    [user.address] // not a contract
                )
            ).to.be.revertedWithCustomError(VaultFactoryFactory, "DepositTokenMustBeContract");
        });
    });

    describe("Functionality of VaultFactoryManager", function () {
        it("Should allow manager to add new deposit token", async function () {
            await expect(
                vaultFactory.connect(admin).addDepositToken(depositToken2.target)
            ).to.emit(vaultFactory, "DepositTokenAdded")
                .withArgs(depositToken2.target);
            
            expect(await vaultFactory.isDepositToken(depositToken2.target)).to.be.true;
            const tokens = await vaultFactory.getDepositTokens();
            expect(tokens.length).to.equal(2);
            expect(tokens[1]).to.equal(depositToken2.target);
        });

        it("Should prevent adding already existing deposit token", async function () {
            await expect(
                vaultFactory.connect(admin).addDepositToken(depositToken.target)
            ).to.be.revertedWithCustomError(vaultFactory, "DepositTokenAlreadyExists");
        });

        it("Should prevent adding non-contract as deposit token", async function () {
            await expect(
                vaultFactory.connect(admin).addDepositToken(user.address)
            ).to.be.revertedWithCustomError(vaultFactory, "DepositTokenMustBeContract");
        });

        it("Should allow manager to remove deposit token", async function () {
            await vaultFactory.connect(admin).addDepositToken(depositToken2.target);
            
            await expect(
                vaultFactory.connect(admin).removeDepositToken(depositToken.target)
            ).to.emit(vaultFactory, "DepositTokenRemoved")
                .withArgs(depositToken.target);
            
            expect(await vaultFactory.isDepositToken(depositToken.target)).to.be.false;
            const tokens = await vaultFactory.getDepositTokens();
            expect(tokens.length).to.equal(1);
            expect(tokens[0]).to.equal(depositToken2.target);
        });

        it("Should prevent removing last deposit token", async function () {
            await expect(
                vaultFactory.connect(admin).removeDepositToken(depositToken.target)
            ).to.be.revertedWithCustomError(vaultFactory, "CannotRemoveLastDepositToken");
        });

        it("Should prevent removing non-existing deposit token", async function () {
            await expect(
                vaultFactory.connect(admin).removeDepositToken(depositToken2.target)
            ).to.be.revertedWithCustomError(vaultFactory, "DepositTokenDoesNotExist");
        });

        it("Should allow manager to set staking percentage", async function () {
            const newStakingPercentage = 500; // 5%
            
            await expect(
                vaultFactory.connect(admin).setStakingPercentage(newStakingPercentage)
            ).to.emit(vaultFactory, "StakingPercentageSet")
                .withArgs(newStakingPercentage);
            
            expect(await vaultFactory.stakingPercentage()).to.equal(newStakingPercentage);
        });

        it("Should prevent setting staking percentage greater than MAX_BIPS", async function () {
            await expect(
                vaultFactory.connect(admin).setStakingPercentage(MAX_BIPS + 1)
            ).to.be.revertedWithCustomError(vaultFactory, "StakingPercentageCannotBeGreaterThanMaxBips");
        });

        it("Should prevent setting zero staking percentage", async function () {
            await expect(
                vaultFactory.connect(admin).setStakingPercentage(0)
            ).to.be.revertedWithCustomError(vaultFactory, "StakingPercentageCannotBeZero");
        });

        it("Should prevent setting contracts by non-admin", async function () {
            const message = await vaultFactory.DEFAULT_ADMIN_ROLE();
            
            await expect(
                vaultFactory.connect(user).setLicenseContract(license.target)
            ).to.be.revertedWithCustomError(vaultFactory, "AccessControlUnauthorizedAccount")
                .withArgs(user.address, message);
            
            await expect(
                vaultFactory.connect(user).setScoringContract(scoring.target)
            ).to.be.revertedWithCustomError(vaultFactory, "AccessControlUnauthorizedAccount")
                .withArgs(user.address, message);
            
            await expect(
                vaultFactory.connect(user).setTreasuryContract(treasury.target)
            ).to.be.revertedWithCustomError(vaultFactory, "AccessControlUnauthorizedAccount")
                .withArgs(user.address, message);
            
            await expect(
                vaultFactory.connect(user).setStakingContract(staking.target)
            ).to.be.revertedWithCustomError(vaultFactory, "AccessControlUnauthorizedAccount")
                .withArgs(user.address, message);
        });

        it("Should prevent setting contracts that are already set", async function () {
            await expect(
                vaultFactory.connect(admin).setLicenseContract(license.target)
            ).to.be.revertedWithCustomError(vaultFactory, "LicenseContractAlreadySet");
            
            await expect(
                vaultFactory.connect(admin).setScoringContract(scoring.target)
            ).to.be.revertedWithCustomError(vaultFactory, "ScoringContractAlreadySet");
            
            await expect(
                vaultFactory.connect(admin).setTreasuryContract(treasury.target)
            ).to.be.revertedWithCustomError(vaultFactory, "TreasuryContractAlreadySet");
            
            await expect(
                vaultFactory.connect(admin).setStakingContract(staking.target)
            ).to.be.revertedWithCustomError(vaultFactory, "StakingContractAlreadySet");
        });
    });

    describe("Functionality of vault creation", function () {
        const futureTime = () => Math.floor(Date.now() / 1000) + 3600; // delay for 1 hour
        const FUNDING_PERIOD = 7 * 24 * 3600; // 7 days
        const LOCK_PERIOD = 30 * 24 * 3600; // 30 days

        beforeEach(async () => {
            await prepareToCreateVault();
        });

        it("Should successfully create vault", async function () {
            const startTime = futureTime();
            
            await expect(
                vaultFactory.connect(entity).createVault(
                    depositToken.target,
                    INTEREST_RATE,
                    DESIRED_CAP,
                    startTime,
                    FUNDING_PERIOD,
                    LOCK_PERIOD
                )
            ).to.emit(vaultFactory, "VaultCreated");

            const vaultCollateralAmount = await treasury.getRequiredCollateral(DESIRED_CAP);
            const vaultRefundableAmount = await oracle.getTokenAmountForPayment(DESIRED_CAP);

            const vaultInfo = (await vaultFactory.getAllVaults())[0];
            expect(vaultInfo.entity).to.equal(entity.address);
            expect(vaultInfo.depositToken).to.equal(depositToken.target);
            expect(vaultInfo.interestRate).to.equal(INTEREST_RATE);
            expect(vaultInfo.desiredCap).to.equal(DESIRED_CAP);
            expect(vaultInfo.startTime).to.equal(startTime);
            expect(vaultInfo.fundingEndTime).to.equal(startTime + FUNDING_PERIOD);
            expect(vaultInfo.unlockEndTime).to.equal(startTime + FUNDING_PERIOD + LOCK_PERIOD);
            expect(vaultInfo.collateralAmount).to.equal(vaultCollateralAmount);
            expect(vaultInfo.refundableAmount).to.equal(vaultRefundableAmount);
            
            // Check that vault is actually created and registered
            expect(await vaultFactory.getVaultsCount()).to.equal(1);
            expect(await vaultFactory.getVaultsCountByEntity(entity.address)).to.equal(1);
            
            const vaultAddress = vaultInfo.vault;
            expect(await vaultFactory.isVault(vaultAddress)).to.be.true;
            
            // Check getters
            expect(await vaultFactory.getVaultEntity(vaultAddress)).to.equal(entity.address);
            expect(await vaultFactory.getCollateralAmount(vaultAddress)).to.equal(vaultCollateralAmount);
            expect(await vaultFactory.getRefundableAmount(vaultAddress)).to.equal(vaultRefundableAmount);
            expect(await vaultFactory.getPoolSize(vaultAddress)).to.equal(DESIRED_CAP);
            
            const retrievedVaultInfo = await vaultFactory.getVault(vaultAddress);
            expect(retrievedVaultInfo.entity).to.equal(entity.address);
            expect(retrievedVaultInfo.depositToken).to.equal(depositToken.target);
        });

        it("Should prevent creating vault without deposit token", async function () {
            await expect(
                vaultFactory.connect(entity).createVault(
                    ethers.ZeroAddress,
                    INTEREST_RATE,
                    DESIRED_CAP,
                    futureTime(),
                    FUNDING_PERIOD,
                    LOCK_PERIOD
                )
            ).to.be.revertedWithCustomError(vaultFactory, "DepositTokenDoesNotExist");
        });

        it("Should prevent creating vault with zero desired cap", async function () {
            await expect(
                vaultFactory.connect(entity).createVault(
                    depositToken.target,
                    INTEREST_RATE,
                    0n, // zero desired cap
                    futureTime(),
                    FUNDING_PERIOD,
                    LOCK_PERIOD
                )
            ).to.be.revertedWithCustomError(vaultFactory, "DesiredCapCannotBeZero");
        });

        it("Should prevent creating vault with zero interest rate", async function () {
            await expect(
                vaultFactory.connect(entity).createVault(
                    depositToken.target,
                    0n, // zero interest rate
                    DESIRED_CAP,
                    futureTime(),
                    FUNDING_PERIOD,
                    LOCK_PERIOD
                )
            ).to.be.revertedWithCustomError(vaultFactory, "InterestRateCannotBeZero");
        });

        it("Should prevent creating vault with past start time", async function () {
            await expect(
                vaultFactory.connect(entity).createVault(
                    depositToken.target,
                    INTEREST_RATE,
                    DESIRED_CAP,
                    Math.floor(Date.now() / 1000) - 3600, // past start time
                    FUNDING_PERIOD,
                    LOCK_PERIOD
                )
            ).to.be.revertedWithCustomError(vaultFactory, "StartTimeMustBeInFuture");
        });

        it("Should prevent creating vault with funding time before start time", async function () {
            await expect(
                vaultFactory.connect(entity).createVault(
                    depositToken.target,
                    INTEREST_RATE,
                    DESIRED_CAP,
                    futureTime(),
                    0, // zero funding period
                    LOCK_PERIOD
                )
            ).to.be.revertedWithCustomError(vaultFactory, "StartTimeMustBeBeforeFundingEndTime");
        });

        it("Should prevent creating vault with unlock time before funding end time", async function () {
            await expect(
                vaultFactory.connect(entity).createVault(
                    depositToken.target,
                    INTEREST_RATE,
                    DESIRED_CAP,
                    futureTime(),
                    FUNDING_PERIOD,
                    0 // zero lock period
                )
            ).to.be.revertedWithCustomError(vaultFactory, "FundingEndTimeMustBeBeforeUnlockEndTime");
        });

        it("Should prevent creating vault with unlock period longer than license", async function () {
            // Getting license end time
            const licenseEndTime = await license.getLicenseExpirationTime(entity.address);
            const startTime = futureTime();
            const fundingEndTime = startTime + FUNDING_PERIOD;
            
            // Calculation of the period that exceeds the allowed after the license expiration
            const maxAllowedUnlockTime = Number(licenseEndTime) + VAULT_EXPIRY_LIMIT;
            const tooLongLockPeriod = maxAllowedUnlockTime - fundingEndTime + 3600; // plus one hour for guarantee
            
            await expect(
                vaultFactory.connect(entity).createVault(
                    depositToken.target,
                    INTEREST_RATE,
                    DESIRED_CAP,
                    startTime,
                    FUNDING_PERIOD,
                    tooLongLockPeriod
                )
            ).to.be.revertedWithCustomError(vaultFactory, "UnlockPeriodTooLong");
        });

        it("Should prevent creating vault with desired cap greater than max possible pool size", async function () {
            // Setting low value of max possible pool size
            const maxPossiblePoolSize = await scoring.getMaxPossiblePoolSize(entity.address);
            
            await expect(
                vaultFactory.connect(entity).createVault(
                    depositToken.target,
                    INTEREST_RATE,
                    maxPossiblePoolSize + 1n,
                    futureTime(),
                    FUNDING_PERIOD,
                    LOCK_PERIOD
                )
            ).to.be.revertedWithCustomError(vaultFactory, "NotAllowedPoolSize");
        });

        it("Should prevent creating vault with too high interest rate", async function () {
            const maxPossiblePoolSize = await scoring.getMaxPossiblePoolSize(entity.address);
            const maxInterestRate = 100_00
            
            await expect(
                vaultFactory.connect(entity).createVault(
                    depositToken.target,
                    maxInterestRate,
                    maxPossiblePoolSize,
                    futureTime(),
                    FUNDING_PERIOD,
                    LOCK_PERIOD
                )
            ).to.be.revertedWithCustomError(vaultFactory, "HighInterestRate");
        });

        it("Should prevent creating vault without set necessary contracts", async function () {
            // Creating new factory without set contracts
            const VaultFactoryFactory = await ethers.getContractFactory("VaultFactory");
            const newVaultFactory = await VaultFactoryFactory.deploy(
                admin.address,
                goilToken.target,
                oracle.target,
                routerV2.target,
                routerV3.target,
                quoter.target,
                [depositToken.target]
            );
            
            await expect(
                newVaultFactory.connect(entity).createVault(
                    depositToken.target,
                    INTEREST_RATE,
                    DESIRED_CAP,
                    futureTime(),
                    FUNDING_PERIOD,
                    LOCK_PERIOD
                )
            ).to.be.revertedWithCustomError(newVaultFactory, "ScoringContractNotSet");
            
            // Setting scoring, but not treasury
            await newVaultFactory.connect(admin).setScoringContract(scoring.target);
            
            await expect(
                newVaultFactory.connect(entity).createVault(
                    depositToken.target,
                    INTEREST_RATE,
                    DESIRED_CAP,
                    futureTime(),
                    FUNDING_PERIOD,
                    LOCK_PERIOD
                )
            ).to.be.revertedWithCustomError(newVaultFactory, "TreasuryContractNotSet");
            
            // Setting treasury, but not staking
            await newVaultFactory.connect(admin).setTreasuryContract(treasury.target);
            
            await expect(
                newVaultFactory.connect(entity).createVault(
                    depositToken.target,
                    INTEREST_RATE,
                    DESIRED_CAP,
                    futureTime(),
                    FUNDING_PERIOD,
                    LOCK_PERIOD
                )
            ).to.be.revertedWithCustomError(newVaultFactory, "StakingContractNotSet");
            
            // Setting staking, but not license
            await newVaultFactory.connect(admin).setStakingContract(staking.target);
            
            await expect(
                newVaultFactory.connect(entity).createVault(
                    depositToken.target,
                    INTEREST_RATE,
                    DESIRED_CAP,
                    futureTime(),
                    FUNDING_PERIOD,
                    LOCK_PERIOD
                )
            ).to.be.revertedWithCustomError(newVaultFactory, "LicenseContractNotSet");
        });
    });

    describe("Functionality of vault viewing", function () {
        const startTime1 = Math.floor(Date.now() / 1000) + 3600;
        const startTime2 = Math.floor(Date.now() / 1000) + 7200;
        const FUNDING_PERIOD = 7 * 24 * 3600;
        const LOCK_PERIOD = 30 * 24 * 3600;

        let vaultCollateralAmount: bigint;

        beforeEach(async () => {
            await prepareToCreateVault();
            
            // Creating two vaults from one entity
            await vaultFactory.connect(entity).createVault(
                depositToken.target,
                INTEREST_RATE,
                DESIRED_CAP,
                startTime1,
                FUNDING_PERIOD,
                LOCK_PERIOD
            );
            
            vaultCollateralAmount = await treasury.getRequiredCollateral(DESIRED_CAP);
            await goilToken.connect(entity).mint(entity.address, vaultCollateralAmount);
            await goilToken.connect(entity).approve(treasury.target, vaultCollateralAmount);

            await vaultFactory.connect(entity).createVault(
                depositToken.target,
                INTEREST_RATE * 2,
                DESIRED_CAP / 2n,
                startTime2,
                FUNDING_PERIOD * 2,
                LOCK_PERIOD / 2
            );
        });

        it("Should correctly return all vaults", async function () {
            const allVaults = await vaultFactory.getAllVaults();
            expect(allVaults.length).to.equal(2);
            
            expect(allVaults[0].startTime).to.equal(startTime1);
            expect(allVaults[1].startTime).to.equal(startTime2);
            
            expect(allVaults[0].interestRate).to.equal(INTEREST_RATE);
            expect(allVaults[1].interestRate).to.equal(INTEREST_RATE * 2);
        });

        it("Should correctly return the number of vaults", async function () {
            expect(await vaultFactory.getVaultsCount()).to.equal(2);
        });

        it("Should correctly return vaults by entity", async function () {
            const entityVaults = await vaultFactory.getVaultsByEntity(entity.address);
            expect(entityVaults.length).to.equal(2);
            
            expect(entityVaults[0].startTime).to.equal(startTime1);
            expect(entityVaults[1].startTime).to.equal(startTime2);
        });

        it("Should correctly return the number of vaults by entity", async function () {
            expect(await vaultFactory.getVaultsCountByEntity(entity.address)).to.equal(2);
            expect(await vaultFactory.getVaultsCountByEntity(user.address)).to.equal(0);
        });

        it("Should correctly return the vault information by address", async function () {
            const allVaults = await vaultFactory.getAllVaults();
            const vaultAddress = allVaults[0].vault;
            
            const vaultInfo = await vaultFactory.getVault(vaultAddress);
            expect(vaultInfo.entity).to.equal(entity.address);
            expect(vaultInfo.startTime).to.equal(startTime1);
            expect(vaultInfo.desiredCap).to.equal(DESIRED_CAP);
            expect(vaultInfo.interestRate).to.equal(INTEREST_RATE);
        });

        it("Should correctly return the vault owner entity", async function () {
            const allVaults = await vaultFactory.getAllVaults();
            const vaultAddress = allVaults[0].vault;
            
            expect(await vaultFactory.getVaultEntity(vaultAddress)).to.equal(entity.address);
        });

        it("Should correctly return the vault collateral amount", async function () {
            const allVaults = await vaultFactory.getAllVaults();
            const vaultAddress = allVaults[0].vault;
            
            expect(await vaultFactory.getCollateralAmount(vaultAddress)).to.equal(vaultCollateralAmount);
        });

        it("Should correctly return the refundable amount", async function () {
            const allVaults = await vaultFactory.getAllVaults();
            const vaultAddress = allVaults[0].vault;
            
            const vaultRefundableAmount = await oracle.getPaymentAmountForTokens(DESIRED_CAP);
            expect(await vaultFactory.getRefundableAmount(vaultAddress)).to.equal(vaultRefundableAmount);
        });

        it("Should correctly return the vault pool size", async function () {
            const allVaults = await vaultFactory.getAllVaults();
            const vaultAddress = allVaults[0].vault;
            
            expect(await vaultFactory.getPoolSize(vaultAddress)).to.equal(DESIRED_CAP);
        });

        it("Should correctly return the deposit tokens", async function () {
            await vaultFactory.connect(admin).addDepositToken(depositToken2.target);
            
            const depositTokens = await vaultFactory.getDepositTokens();
            expect(depositTokens.length).to.equal(2);
            expect(depositTokens[0]).to.equal(depositToken.target);
            expect(depositTokens[1]).to.equal(depositToken2.target);
        });

        it("Should correctly return the number of deposit tokens", async function () {
            expect(await vaultFactory.getDepositTokensCount()).to.equal(1);
            
            await vaultFactory.connect(admin).addDepositToken(depositToken2.target);
            expect(await vaultFactory.getDepositTokensCount()).to.equal(2);
        });
    });
});
