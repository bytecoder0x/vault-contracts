import { ethers } from "hardhat";
import { expect } from "chai";
import { License, MockERC20, MockQuadata, Scoring, Treasury } from "../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { deployAllContracts } from "./utils.test";

describe.only("GoilLicense", function () {
    let license: License;
    let scoring: Scoring;
    let goilToken: MockERC20;
    let qadrataReader: MockQuadata; 
    let treasury: Treasury;
    let admin: HardhatEthersSigner;

    let manager: HardhatEthersSigner;
    let applicant: HardhatEthersSigner;
    let otherAccount: HardhatEthersSigner;
    let applicationFee: bigint;
    let licenseMonthlyFee: bigint;
    let totalFeeWithCollateral: bigint;

    const COLLATERAL_AMOUNT = ethers.parseEther("10000");
    const VOTING_PERIOD = 7 * 24 * 3600;
    const LICENSE_EXPIRATION_LIMIT = 365 * 24 * 3600;

    const submitLicense = async(licenseEndTime: bigint) =>{
        await qadrataReader.connect(applicant).mint(applicant.address, 1n);
        await goilToken.connect(applicant).mint(applicant.address, totalFeeWithCollateral);
        await goilToken.connect(applicant).approve(license.target, totalFeeWithCollateral);
        await license.connect(applicant).submitLicense(licenseEndTime, COLLATERAL_AMOUNT);
    }

    beforeEach(async () => {
        const fixture = await loadFixture(deployAllContracts);
        license = fixture.license;
        goilToken = fixture.goilToken;
        qadrataReader = fixture.quadata;
        admin = fixture.admin;
        manager = fixture.admin;
        treasury = fixture.treasury;
        scoring = fixture.scoring;
        applicant = fixture.entity;
        otherAccount = fixture.user2;
        applicationFee = fixture.APPLICATION_FEE;
        licenseMonthlyFee = fixture.LICENSE_MONTHLY_FEE;
		totalFeeWithCollateral = COLLATERAL_AMOUNT + licenseMonthlyFee * 12n + applicationFee;
    });

    describe("Deployment Functionality", function () {
        it("Should set correct quadrata reader contract", async function () {
            expect(await license.QADRATA_READER()).to.equal(qadrataReader.target);
        });

        it("Should set correct goil token contract", async function () {
            expect(await license.GOIL_TOKEN()).to.equal(goilToken.target);
        });

        it("Should set correct treasury contract", async function () {
            expect(await license.TREASURY()).to.equal(treasury.target);
        });

        it("Should set correct application fee", async function () {
            expect(await license.applicationFee()).to.equal(applicationFee);
        });

        it("Should set correct license monthly fee", async function () {
            expect(await license.licenseMonthlyFee()).to.equal(licenseMonthlyFee);
        });

        it("Should set correct voting period", async function () {
            expect(await license.votingPeriod()).to.equal(7 * 24 * 3600);
        });

        it("Should set correct license expiration limit", async function () {
            expect(await license.licenseExpirationLimit()).to.equal(365 * 24 * 3600);
        });

        it("Should revert when admin address is zero", async function () {
            const LicenseFactory = await ethers.getContractFactory("License");
            await expect(
                LicenseFactory.deploy(
                    ethers.ZeroAddress,
                    qadrataReader.target,
                    goilToken.target,
                    treasury.target,
                    applicationFee,
                    licenseMonthlyFee
                )
            ).to.be.revertedWithCustomError(license, "AdminAddressCannotBeZero");
        });

        it("Should revert when Qadrata Reader address is not a contract", async function () {
            const LicenseFactory = await ethers.getContractFactory("License");
            await expect(
                LicenseFactory.deploy(
                    admin.address,
                    ethers.ZeroAddress,
                    goilToken.target,
                    treasury.target,
                    applicationFee,
                    licenseMonthlyFee
                )
            ).to.be.revertedWithCustomError(license, "QadrataAddressMustBeContract");
        });

        it("Should revert when GOIL Token address is not a contract", async function () {
            const LicenseFactory = await ethers.getContractFactory("License");
            await expect(
                LicenseFactory.deploy(
                    admin.address,
                    qadrataReader.target,
                    ethers.ZeroAddress,
                    treasury.target,
                    applicationFee,
                    licenseMonthlyFee
                )
            ).to.be.revertedWithCustomError(license, "GOILTokenAddressMustBeContract");
        });

        it("Should revert when Treasury address is not a contract", async function () {
            const LicenseFactory = await ethers.getContractFactory("License");
            await expect(
                LicenseFactory.deploy(
                    admin.address,
                    qadrataReader.target,
                    goilToken.target,
                    ethers.ZeroAddress,
                    applicationFee,
                    licenseMonthlyFee
                )
            ).to.be.revertedWithCustomError(license, "TreasuryAddressMustBeContract");
        });

        it("Should revert when application fee is zero", async function () {
            const LicenseFactory = await ethers.getContractFactory("License");
            await expect(
                LicenseFactory.deploy(
                    admin.address,
                    qadrataReader.target,
                    goilToken.target,
                    treasury.target,
                    0,
                    licenseMonthlyFee
                )
            ).to.be.revertedWithCustomError(license, "FeesCannotBeZero");
        });

        it("Should revert when license monthly fee is zero", async function () {
            const LicenseFactory = await ethers.getContractFactory("License");
            await expect(
                LicenseFactory.deploy(
                    admin.address,
                    qadrataReader.target,
                    goilToken.target,
                    treasury.target,
                    applicationFee,
                    0
                )
            ).to.be.revertedWithCustomError(license, "FeesCannotBeZero");
        });

        it("Should revert calling main function without setup scoring contract", async function () {
            const LicenseFactory = await ethers.getContractFactory("License");
            const license = await LicenseFactory.deploy(
                admin.address,
                qadrataReader.target,
                goilToken.target,
                treasury.target,
                applicationFee,
                licenseMonthlyFee
            );

            await expect(license.connect(applicant).submitLicense(1, 0)).to.be.revertedWithCustomError(license, "ScoringContractNotSet");
        });
    });

    describe("License Submission Functionality", function () {
        it("Should successfully submit a license", async function () {
            await qadrataReader.connect(applicant).mint(applicant.address, 1n);
            await goilToken.connect(applicant).mint(applicant.address, totalFeeWithCollateral);
            await goilToken.connect(applicant).approve(license.target, totalFeeWithCollateral);

            const licenseStartTime = BigInt(await time.latest()) + BigInt(VOTING_PERIOD) + 1n;
            const licenseEndTime = licenseStartTime + (365n * 24n * 3600n);
            
            await expect(license.connect(applicant).submitLicense(licenseEndTime, COLLATERAL_AMOUNT))
                .to.emit(license, "SubmittedLicense")
                .withArgs(applicant.address, licenseStartTime, licenseEndTime, licenseMonthlyFee * 12n, COLLATERAL_AMOUNT);

            const [status, startTime, endTime, approved, confirmedByAdmin] = await license.getLicenseByEntity(applicant.address);

            expect(status).to.equal(1); // PENDING
            expect(startTime).to.equal(licenseStartTime);
            expect(endTime).to.equal(licenseEndTime);
            expect(approved).to.equal(false);
            expect(confirmedByAdmin).to.equal(false);
            expect(await license.getLicenseExpirationTime(applicant.address)).to.equal(licenseEndTime);
            expect(await goilToken.balanceOf(treasury.target)).to.equal(applicationFee);
            expect(await goilToken.balanceOf(license.target)).to.equal(licenseMonthlyFee * 12n + COLLATERAL_AMOUNT);
        });

        it("Should successfully submit a license if previous license is rejected", async function () {
            const licenseEndTime = BigInt(await time.latest()) + (365n * 24n * 3600n) + BigInt(VOTING_PERIOD); 
            await submitLicense(licenseEndTime);
            expect(await goilToken.balanceOf(license.target)).to.equal(totalFeeWithCollateral - applicationFee);
            
            const balanceBeforeRefund = await goilToken.balanceOf(applicant.address);
            await license.approveLicense(applicant.address, false);

            await time.increase(10 * 24 * 3600); // 10 days
            expect(await license.getLicenseIsActive(applicant.address)).to.equal(false); 
            expect(await license.getLicenseStatus(applicant.address)).to.equal(2); // REJECTED
            expect(await goilToken.balanceOf(license.target)).to.equal(0);
            expect(await goilToken.balanceOf(applicant.address)).to.equal(balanceBeforeRefund + totalFeeWithCollateral - applicationFee);

            const newLicenseEndTime = BigInt(await time.latest()) + (365n * 24n * 3600n) + BigInt(VOTING_PERIOD);

            await goilToken.connect(applicant).mint(applicant.address, applicationFee);
            await goilToken.connect(applicant).approve(license.target, totalFeeWithCollateral);
            await license.connect(applicant).submitLicense(newLicenseEndTime, COLLATERAL_AMOUNT);

            const licenseInfo = await license.licenses(applicant.address);
            expect(licenseInfo.endTime).to.equal(newLicenseEndTime);
            expect(licenseInfo.approved).to.equal(false);
            expect(licenseInfo.confirmedByAdmin).to.equal(false);
            expect(await goilToken.balanceOf(treasury.target)).to.equal(applicationFee * 2n);
            expect(await goilToken.balanceOf(license.target)).to.equal(licenseMonthlyFee * 12n + COLLATERAL_AMOUNT);
        });

        it("Should successfully submit a license if previous license is expired", async function () {
            const licenseEndTime = BigInt(await time.latest()) + (365n * 24n * 3600n) + BigInt(VOTING_PERIOD); 
            await submitLicense(licenseEndTime);

            await time.increase(10 * 24 * 3600); // 10 days
            await license.approveLicense(applicant.address, true);

            await time.increase((365n * 24n * 3600n) + BigInt(VOTING_PERIOD)); // 1 year
            expect(await license.getLicenseIsActive(applicant.address)).to.equal(false); 
            expect(await license.getLicenseStatus(applicant.address)).to.equal(4); // EXPIRED

            const newLicenseEndTime = BigInt(await time.latest()) + (365n * 24n * 3600n) + BigInt(VOTING_PERIOD) + 1n;
            await submitLicense(newLicenseEndTime);

            const licenseInfo = await license.licenses(applicant.address);
            expect(licenseInfo.endTime).to.equal(newLicenseEndTime);
            expect(licenseInfo.approved).to.equal(false);
            expect(licenseInfo.confirmedByAdmin).to.equal(false);
            expect(await goilToken.balanceOf(treasury.target)).to.equal(licenseMonthlyFee * 12n + applicationFee * 2n + COLLATERAL_AMOUNT);
        });

        it("Should revert if applicant doesn't have the required KYB", async function () {
            // Applicant doesn't have KYB
            await goilToken.connect(applicant).mint(applicant.address, ethers.parseEther("1000"));
            await goilToken.connect(applicant).approve(license.target, applicationFee + licenseMonthlyFee);

            const licenseEndTime = BigInt(await time.latest()) + (365n * 24n * 3600n) + BigInt(VOTING_PERIOD); // 1 year

            await expect(
                license.connect(applicant).submitLicense(licenseEndTime, COLLATERAL_AMOUNT)
            ).to.be.revertedWithCustomError(license, "ApplicantMustHaveQadrataKYB");
        });

        it("Should revert if license period is too short", async function () {
            const licenseEndTime = BigInt(await time.latest()) + (15n * 24n * 3600n) + BigInt(VOTING_PERIOD); // 15 days

            await expect(submitLicense(licenseEndTime)).to.be.revertedWithCustomError(license, "LicensePeriodTooShort");
        });

        it("Should revert if license period is too long", async function () {
            const licenseEndTime = BigInt(await time.latest()) + (400n * 24n * 3600n) + BigInt(VOTING_PERIOD); // 400 days

            await expect(submitLicense(licenseEndTime)).to.be.revertedWithCustomError(license, "LicensePeriodTooLong");
        });

        it("Should revert if license is already submitted", async function () {
            const licenseEndTime = BigInt(await time.latest()) + (365n * 24n * 3600n) + BigInt(VOTING_PERIOD); // 1 year
            await submitLicense(licenseEndTime)

            await expect(submitLicense(licenseEndTime)).to.be.revertedWithCustomError(license, "LicenseAlreadySubmitted");
        });
    });

    describe("Approval Functionality", function () {
        it("Should successfully approve a license and set initial score", async function () {
            const licenseEndTime = BigInt(await time.latest()) + (365n * 24n * 3600n) + BigInt(VOTING_PERIOD); // 1 year 
            await submitLicense(licenseEndTime);
            

            await scoring.connect(admin).setPerformanceData(applicant.address, 50_000, 50_000);
            await expect(license.approveLicense(applicant.address, true))
                .to.emit(license, "LicenseApproved")
                .withArgs(applicant.address, true);

            const licenseStatus = await license.getLicenseStatus(applicant.address);
            expect(licenseStatus).to.equal(3); // ACTIVE

            const scores = await scoring.getScores(applicant.address);
            
            expect(scores.length).to.equal(1);
            expect(scores[0]).greaterThan(0);
            expect(await goilToken.balanceOf(treasury.target)).to.equal(applicationFee + licenseMonthlyFee * 12n + COLLATERAL_AMOUNT);
            expect(await goilToken.balanceOf(license.target)).to.equal(0);
        });

        it("Should successfully approve new license if previous license is expired", async function () {
            const licenseEndTime = BigInt(await time.latest()) + (365n * 24n * 3600n) + BigInt(VOTING_PERIOD);
            await submitLicense(licenseEndTime);

            await license.approveLicense(applicant.address, true);
            await scoring.connect(admin).setPerformanceData(applicant.address, 50_000, 50_000);

            const scores = await scoring.getScores(applicant.address);
            expect(scores.length).to.equal(1);
            expect(scores[0]).greaterThan(0);

            await time.increase((365n * 24n * 3600n) + BigInt(VOTING_PERIOD)); // 1 year
            expect(await license.getLicenseStatus(applicant.address)).to.equal(4); // EXPIRED

            const newLicenseEndTime = BigInt(await time.latest()) + (365n * 24n * 3600n) + BigInt(VOTING_PERIOD);
            await submitLicense(newLicenseEndTime);
            await license.approveLicense(applicant.address, true);

            expect(await license.getLicenseStatus(applicant.address)).to.equal(3); // ACTIVE
            expect(await goilToken.balanceOf(license.target)).to.equal(0);
            expect(await goilToken.balanceOf(treasury.target)).to.equal(applicationFee * 2n + (licenseMonthlyFee * 12n) * 2n + COLLATERAL_AMOUNT * 2n);
        })

        it("Should revert if license is not in PENDING state", async function () {
            const licenseEndTime = BigInt(await time.latest()) + (365n * 24n * 3600n) + BigInt(VOTING_PERIOD);
            await submitLicense(licenseEndTime)

            await goilToken.connect(otherAccount).mint(otherAccount.address, ethers.parseEther("1000"));
            await license.approveLicense(applicant.address, true);

            await expect(
                license.approveLicense(applicant.address, true)
            ).to.be.revertedWithCustomError(license, "LicenseIsNotPending");
        });

        it("Should revert if not license manager tries to approve license", async function () {
            const licenseEndTime = BigInt(await time.latest()) + (365n * 24n * 3600n) + BigInt(VOTING_PERIOD);

            await submitLicense(licenseEndTime);
            await expect(
                license.connect(otherAccount).approveLicense(applicant.address, true)
            ).to.be.revertedWithCustomError(license, "AccessControlUnauthorizedAccount")
                .withArgs(otherAccount.address, ethers.keccak256(ethers.toUtf8Bytes("LICENSE_MANAGER_ROLE")));
        });
    });

    describe("Administrative Functionality", function () {
        it("Should allow manager to change application fee", async function () {
            await expect(
                license.connect(manager).setApplicationFee(ethers.parseEther("200"))
            )
                .to.emit(license, "ApplicationFeeUpdated")
                .withArgs(ethers.parseEther("200"));

            expect(await license.applicationFee()).to.equal(ethers.parseEther("200"));
        });

        it("Should allow manager to change monthly license fee", async function () {
            await expect(
                license.connect(manager).setLicenseMonthlyFee(ethers.parseEther("60"))
            )
                .to.emit(license, "LicenseMonthlyFeeUpdated")
                .withArgs(ethers.parseEther("60"));

            expect(await license.licenseMonthlyFee()).to.equal(ethers.parseEther("60"));
        });

        it("Should allow manager to change voting period", async function () {
            const newVotingPeriod = 10 * 24 * 3600; // 10 days

            await expect(
                license.connect(manager).setVotingPeriod(newVotingPeriod)
            )
                .to.emit(license, "VotingPeriodUpdated")
                .withArgs(newVotingPeriod);

            expect(await license.votingPeriod()).to.equal(newVotingPeriod);
        });

        it("Should allow manager to change exipation limit for license", async function () {
            const newExpirationLimit = 500 * 24 * 3600; // 500 days

            await expect(
                license.connect(manager).setLicenseExpirationLimit(newExpirationLimit)
            )
                .to.emit(license, "LicenseExpirationLimitUpdated")
                .withArgs(newExpirationLimit);

            expect(await license.licenseExpirationLimit()).to.equal(newExpirationLimit);
        });

        it("Should revert set fee if its the same", async function () {
            const currentApplicationFee = await license.applicationFee();

            await expect(
                license.connect(manager).setApplicationFee(currentApplicationFee)
            ).to.be.revertedWithCustomError(license, "FeeCannotBeTheSame")

            const currentMothlyLicenseFee = await license.licenseMonthlyFee();

            await expect(
                license.connect(manager).setLicenseMonthlyFee(currentMothlyLicenseFee)
            ).to.be.revertedWithCustomError(license, "FeeCannotBeTheSame")
        });

        it("Should revert set voting period if its the same or zero", async function () {
            const currentRequiredVotingPeriod = await license.votingPeriod();

            await expect(
                license.connect(manager).setVotingPeriod(currentRequiredVotingPeriod)
            ).to.be.revertedWithCustomError(license, "VotingPeriodCannotBeTheSame");

            await expect(
                license.connect(manager).setVotingPeriod(0)
            ).to.be.revertedWithCustomError(license, "VotingPeriodCannotBeZero");
        });

        it("Should revert set expiration limit for license if its the same or zero", async function () {
            const currentLicenseExpirationLimit = await license.licenseExpirationLimit();

            await expect(
                license.connect(manager).setLicenseExpirationLimit(currentLicenseExpirationLimit)
            ).to.be.revertedWithCustomError(license, "LicenseExpirationLimitCannotBeTheSame");

            await expect(
                license.connect(manager).setLicenseExpirationLimit(0)
            ).to.be.revertedWithCustomError(license, "LicenseExpirationLimitCannotBeZero");
        });

        it("Should revert if scoring contract is not a contract or already set", async function () {
            await expect(
                license.connect(manager).setScoringContract(otherAccount.address)
            ).to.be.revertedWithCustomError(license, "ScoringContractMustBeContract");

            await expect(
                license.connect(manager).setScoringContract(scoring.target)
            ).to.be.revertedWithCustomError(license, "ScoringContractAlreadySet");
        });

        it("Should revert if non-manager tries to change parameters or set contract addresses", async function () {
            await expect(
                license.connect(otherAccount).setApplicationFee(ethers.parseEther("200"))
            ).to.be.revertedWithCustomError(license, "AccessControlUnauthorizedAccount")
                .withArgs(otherAccount.address, ethers.keccak256(ethers.toUtf8Bytes("MANAGER_ROLE")));

            await expect(
                license.connect(otherAccount).setLicenseMonthlyFee(ethers.parseEther("60"))
            ).to.be.revertedWithCustomError(license, "AccessControlUnauthorizedAccount")
                .withArgs(otherAccount.address, ethers.keccak256(ethers.toUtf8Bytes("MANAGER_ROLE")));
            
            await expect(
                license.connect(otherAccount).setVotingPeriod(10 * 24 * 3600)
            ).revertedWithCustomError(license, "AccessControlUnauthorizedAccount")
                .withArgs(otherAccount.address, ethers.keccak256(ethers.toUtf8Bytes("MANAGER_ROLE")));

            await expect(
                license.connect(otherAccount).setLicenseExpirationLimit(500 * 24 * 3600)
            ).revertedWithCustomError(license, "AccessControlUnauthorizedAccount")
                .withArgs(otherAccount.address, ethers.keccak256(ethers.toUtf8Bytes("MANAGER_ROLE")));

            const adminRole = await license.DEFAULT_ADMIN_ROLE();
            await expect(
                license.connect(otherAccount).setScoringContract(scoring.target)
            ).revertedWithCustomError(license, "AccessControlUnauthorizedAccount")
                .withArgs(otherAccount.address, adminRole);
        });
    });


    describe("License Information Retrieval Functionality", function () {
        it("Should return the correct license status", async function () {
            const licenseEndTime = BigInt(await time.latest()) + (365n * 24n * 3600n) + BigInt(VOTING_PERIOD);

            expect(await license.getLicenseStatus(applicant.address)).to.equal(0); // UNINITIALIZED

            await submitLicense(licenseEndTime);
            expect(await license.getLicenseStatus(applicant.address)).to.equal(1); // PENDING
            expect(await license.getLicenseIsPending(applicant.address)).to.equal(true);

            await license.approveLicense(applicant.address, true);

            expect(await license.getLicenseIsActive(applicant.address)).to.equal(true);
            expect(await license.getLicenseStatus(applicant.address)).to.equal(3); // ACTIVE

            await time.increase(500n * 24n * 3600n); // 500 days
            expect(await license.getLicenseStatus(applicant.address)).to.equal(4); // EXPIRED
            expect(await license.getLicenseIsActive(applicant.address)).to.equal(false);
        });

        it("Should return the correct license details by address", async function () {
            const licenseEndTime = BigInt(await time.latest()) + (365n * 24n * 3600n) + BigInt(VOTING_PERIOD);
            await submitLicense(licenseEndTime)

            const [status, startTime, endTime, approved, confirmedByAdmin] = await license.getLicenseByEntity(applicant.address);
            
            expect(status).to.equal(1); // PENDING
            expect(startTime).to.equal(BigInt(await time.latest()) + 7n * 24n * 3600n);
            expect(endTime).to.equal(licenseEndTime);
            expect(approved).to.equal(false);
            expect(confirmedByAdmin).to.equal(false);
        });
    });
});