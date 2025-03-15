import hre, { ethers } from "hardhat";
import { LICENSE_MONTHLY_FEE, APPLICATION_FEE, MARKET_CONDITION_RATIO, THRESHOLD_COLLATERAL, THRESHOLD_CAPITAL } from "./arguments";

function delay(ms: number) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

async function main() {
    const [signer] = await hre.ethers.getSigners();

    const quadrataAddress = "0x73A2e70bEf04d4e6CABc0ff78fbA7B553166fCf6";

    let oracleAddress = "0x731947403026e6C5893E96b4379Cb0539CFC79ca";
    let vaultFactoryAddress = "0x41836bcC5d044DE48B2BcCa239B31E6ded956B7c";
    let vaultImplementationAddress = "0x1aAd07db81D0AE00C26528cE49d3dCfB8e2A5FD5";
    let treasuryAddress = "0x19c9696f02107cA49CF0958b38fbDe078D60Ea14";
    let licenseAddress = "0x8ee5421d69f4d614aAb3910430A5Be3a6F958739";
    let scoringAddress = "0xb8547575e02B7d1388d25199D7383658Ee28Ee42";
    let stakingAddress = "0x54eE7dA71bA070512C797c589f5f1128a3c26146";

    const quoterAddress = "0x61fFE014bA17989E743c5F6cB21bF9697530B21e";
    const routerV2Address = "0x4752ba5dbc23f44d87826276bf6fd6b1c372ad24";
    const routerV3Address = "0xE592427A0AEce92De3Edee1F18E0157C05861564";
    const uniswapV3FactoryAddress = "0x1F98431c8aD98523631AE4a59f267346ea31F984";
    const poolV3Address = "0x2d52b7221bac04705946d6d870947228decb5491";

    const goilTokenAddress = "0xE422D79FDFEb0E4AbB3efE5f413D70695a6600b2";
    const usdcTokenAddress = "0xb4f80a9Fecf326c4e820b4395DEA0bD314b4bA88";

    const adminAddress = "0xFFe82abf0Bb0d956A27338a0f3EEc350FA93cb7F";
    const managerAddress = "0xd1fEFa7ef26b6D24C9F4b274cE77Cd48769A28A4";

    const poolFee = 3000;

	const oracleFactory = await ethers.getContractFactory("Oracle");
	const oracle = await oracleFactory.deploy(uniswapV3FactoryAddress, adminAddress, goilTokenAddress, usdcTokenAddress, poolFee);
	await oracle.waitForDeployment();

    console.log("Oracle contract deployed to:", oracle.target);
    oracleAddress = oracle.target.toString();

    const vaultFactoryFactory = await ethers.getContractFactory("VaultFactory");
	const vaultFactory = await vaultFactoryFactory.deploy(
		adminAddress,
		goilTokenAddress,
		oracleAddress,
		routerV2Address,
		routerV3Address,
		quoterAddress,
		[usdcTokenAddress]

	);
	await vaultFactory.waitForDeployment();

    console.log("VaultFactory contract deployed to:", vaultFactory.target);
    vaultFactoryAddress = vaultFactory.target.toString();
    vaultImplementationAddress = await vaultFactory.VAULT_IMPLEMENTATION();

    const TreasuryFactory = await ethers.getContractFactory("Treasury");
	const treasury = await TreasuryFactory.deploy(goilTokenAddress, oracleAddress, vaultFactoryAddress, adminAddress);
	await treasury.waitForDeployment();

    console.log("Treasury contract deployed to:", treasury.target);
    treasuryAddress = treasury.target.toString();

	const LicenseFactory = await ethers.getContractFactory("License");
	const license = await LicenseFactory.deploy(
		adminAddress,
		quadrataAddress,
		goilTokenAddress,
		treasuryAddress,
		APPLICATION_FEE,
		LICENSE_MONTHLY_FEE
	);
	await license.waitForDeployment();

    console.log("License contract deployed to:", license.target);
    licenseAddress = license.target.toString();

    const scoringFactory = await ethers.getContractFactory("Scoring");
	const scoring = await scoringFactory.deploy(
		adminAddress,
		vaultFactoryAddress,
		treasuryAddress,
		licenseAddress,
		goilTokenAddress,
		THRESHOLD_CAPITAL,
		THRESHOLD_COLLATERAL,
		MARKET_CONDITION_RATIO
	);
	await scoring.waitForDeployment();

    console.log("Scoring contract deployed to:", scoring.target);
    scoringAddress = scoring.target.toString();

	const stakingFactory = await ethers.getContractFactory("Staking");
	const staking = await stakingFactory.deploy(treasuryAddress, goilTokenAddress, goilTokenAddress);
	await staking.waitForDeployment();

    console.log("Staking contract deployed to:", staking.target);
    stakingAddress = staking.target.toString();

    console.log("Waiting for block confirmations...");
    await delay(30000); // Wait for 30 seconds before verifying the contract

    await hre.run("verify:verify", {
        address: oracle.target,
        constructorArguments: [uniswapV3FactoryAddress, adminAddress, goilTokenAddress, usdcTokenAddress, poolFee],
    });

    await hre.run("verify:verify", {
        address: vaultFactory.target,
        constructorArguments: [adminAddress, goilTokenAddress, oracleAddress, routerV2Address, routerV3Address, quoterAddress, [usdcTokenAddress]],
    });

    await hre.run("verify:verify", {
        address: treasury.target,
        constructorArguments: [goilTokenAddress, oracleAddress, vaultFactoryAddress, adminAddress],
    });

    await hre.run("verify:verify", {
        address: license.target,
        constructorArguments: [adminAddress, quadrataAddress, goilTokenAddress, treasuryAddress, APPLICATION_FEE, LICENSE_MONTHLY_FEE],
    });

    await hre.run("verify:verify", {
        address: scoring.target,
        constructorArguments: [adminAddress, vaultFactoryAddress, treasuryAddress, licenseAddress, goilTokenAddress, THRESHOLD_CAPITAL, THRESHOLD_COLLATERAL, MARKET_CONDITION_RATIO],
    });

    await hre.run("verify:verify", {
        address: staking.target,
        constructorArguments: [treasuryAddress, goilTokenAddress, goilTokenAddress],
    });
    
    await hre.run("verify:verify", {
        address: vaultImplementationAddress,
    });

    // const vaultFactory = await ethers.getContractAt("VaultFactory", vaultFactoryAddress);
    // const treasury = await ethers.getContractAt("Treasury", treasuryAddress);
    // const license = await ethers.getContractAt("License", licenseAddress);

    await vaultFactory.setScoringContract(scoringAddress);
	await vaultFactory.setStakingContract(stakingAddress);
	await vaultFactory.setTreasuryContract(treasuryAddress);
	await vaultFactory.setLicenseContract(licenseAddress);

	await treasury.setScoringContract(scoringAddress);
	await treasury.setStakingContract(stakingAddress);
	await treasury.setLicenseContract(licenseAddress);

	await license.setScoringContract(scoringAddress);

    console.log("All contracts set successfully!");

    const LICENSE_MANAGER_ROLE = await license.LICENSE_MANAGER_ROLE();
    await license.grantRole(LICENSE_MANAGER_ROLE, managerAddress);

    const SCORING_MANAGER_ROLE = await scoring.SCORING_MANAGER_ROLE();
    await scoring.grantRole(SCORING_MANAGER_ROLE, managerAddress);

    const ORACLE_MANAGER_ROLE = await oracle.ORACLE_MANAGER_ROLE();
    await oracle.grantRole(ORACLE_MANAGER_ROLE, managerAddress);

    const TREASURY_MANAGER_ROLE = await treasury.TREASURY_MANAGER_ROLE();
    await treasury.grantRole(TREASURY_MANAGER_ROLE, managerAddress);

    const VAULT_FACTORY_MANAGER_ROLE = await vaultFactory.VAULT_FACTORY_MANAGER_ROLE();
    await vaultFactory.grantRole(VAULT_FACTORY_MANAGER_ROLE, managerAddress);

    console.log("All roles granted successfully!");

    const goilToken = await ethers.getContractAt("MockERC20", goilTokenAddress);
    const usdcToken = await ethers.getContractAt("MockERC20", usdcTokenAddress);
    const quadrataReader = await ethers.getContractAt("MockQuadata", quadrataAddress);

    const amountToMint = ethers.parseEther("10000000");
    
    await goilToken.mint(managerAddress, amountToMint);
    await usdcToken.mint(managerAddress, amountToMint);
    await quadrataReader.mint(managerAddress, 1);

    console.log("All tokens minted successfully!");
}



main().then(res => res).catch(err => console.log(err));
