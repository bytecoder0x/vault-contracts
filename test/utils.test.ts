import { ethers } from "hardhat";

export const deployAllContracts = async () => {
    const [admin, entity, user1, user2, user3, user4] = await ethers.getSigners();
    const MockERC20Factory = await ethers.getContractFactory("MockERC20");

    const INITIAL_SUPPLY = ethers.parseEther("10000000");

    const APPLICATION_FEE = ethers.parseEther("1000");
    const LICENSE_MONTHLY_FEE = ethers.parseEther("100");

    // threshold collateral is used for calculating collateral ratio that is used for calculating initial score
    const THRESHOLD_COLLATERAL = ethers.parseEther("10000");
    // threshold capital is used for calculating max pool size
    const THRESHOLD_CAPITAL = ethers.parseEther("1000000");
    const MARKET_CONDITION_RATIO = 100_000;

    const END_STAKING_BLOCK = 100000000;

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
        stableToken.target,
        goilToken.target,
        oracle.target,
        mockRouterV2.target,
        mockRouterV3.target,
        mockQuoter.target
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
    const staking = await stakingFactory.deploy(
        vaultFactory.target,
        treasury.target,
        goilToken.target,
        goilToken.target,
        END_STAKING_BLOCK
    );
    await staking.waitForDeployment();

    await vaultFactory.setScoringContract(scoring.target);
    await vaultFactory.setStakingContract(staking.target);
    await vaultFactory.setTreasuryContract(treasury.target);
    await vaultFactory.setLicenseContract(license.target);

    await treasury.setScoringContract(scoring.target);
    await treasury.setStakingContract(staking.target);
    await treasury.setLicenseContract(license.target);

    await license.setScoringContract(scoring.target);

    return {
        admin,
        entity,
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
        END_STAKING_BLOCK
    };
};